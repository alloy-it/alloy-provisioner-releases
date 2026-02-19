# alloy-provisioner User Guide

**alloy-provisioner** is the Alloy guest VM provisioning engine: a Go CLI binary that runs inside a Linux guest (VM or bare-metal machine) and applies a declarative YAML blueprint to install packages, download toolchains, run setup commands, and configure the environment. It is designed to be idempotent, reproducible, and architecture-aware.

This guide explains what the tool does, all implemented features, and how to use it in two scenarios:

- **Inside an alloy-host VM** — the managed workflow where `alloy-host` creates and orchestrates the VM; provisioning runs automatically.
- **Natively on Linux** — the direct workflow where you install and run the provisioner yourself on any Debian/Ubuntu machine.

---

## Table of Contents

1. [Concepts](#concepts)
2. [Features](#features)
3. [Running Inside an alloy-host VM](#running-inside-an-alloy-host-vm)
4. [Running Natively on Linux](#running-natively-on-linux)
5. [Reference](#reference)

---

## Concepts

### Blueprints

A **blueprint** is a directory of YAML files that describes how to provision a development environment. It always contains:

- **`manifest.yml`** — required metadata file: blueprint name, version, global variables, toolchain references, and the explicit execution order (`run_order`).
- **Task files** — one or more YAML files listing provisioning tasks (e.g. `00-system-base.yml`, `10-arm-toolchain.yml`, `99-cleanup.yml`). Only files listed in `run_order` are executed.
- **`alloy.state.yml`** — automatically created and maintained by the provisioner to track which tasks have been completed (used for idempotency; do not commit).
- **`alloy.lock.yml`** — optional resolved lockfile mapping toolchain references to exact URLs and SHA256 checksums.

**Example blueprint directory layout:**

```TOML
my-blueprint/
├── manifest.yml
├── alloy.lock.yml        # resolved by alloy-host resolve (optional)
├── 00-system-base.yml
├── 10-toolchain.yml
├── 20-setup.yml
├── 99-cleanup.yml
└── alloy.state.yml       # auto-created; do not commit
```

**Example `manifest.yml`:**

```yaml
name: "My Dev Environment"
version: "1.0.0"
description: "Example blueprint."

variables:
  VM_USER: "vagrant"
  TOOLCHAIN_DEST: "/opt/my-toolchain"

toolchains:
  - ref: "toolchain.arm-gnu.arm-none-eabi@stable"
    alias: ARM_TOOLCHAIN

run_order:
  - "00-system-base.yml"
  - "10-toolchain.yml"
  - "99-cleanup.yml"
```

### Task Execution Order

Tasks are executed in the order specified by `run_order` in `manifest.yml`, and within each file from top to bottom. The order is explicit and deterministic — there is no implicit ordering or dependency resolution.

### Idempotency

The provisioner is safe to run multiple times. It tracks what has already been done and skips completed tasks. This means re-provisioning only applies what has changed or not yet been applied. See [Idempotency System](#idempotency-system) for full details.

### Variables and Secrets

Global variables defined in `manifest.yml` under `variables:` are expanded in task fields using Go template syntax: `{{.Vars.VARIABLE_NAME}}`. Environment variables are merged into the variable set and can override manifest values; they are also accessible directly as `$VAR` in some fields.

Secrets (tokens, passwords) should be passed as environment variables, never hardcoded in blueprint files.

### Architecture Support

The provisioner automatically detects the host architecture (`amd64` or `arm64`) and merges architecture-specific values from `per_arch:` blocks in tasks. This allows a single blueprint to support both architectures without conditional logic.

---

## Features

### Task Actions

The provisioner supports **9 built-in actions**. Each task in a YAML file must have a `name` (identifier) and an `action` (one of the values below).

---

#### `apt_install` — Install packages via apt-get

Installs one or more Debian/Ubuntu packages. Smart idempotency: only installs packages that are not already present.

```yaml
- name: "Install build tools"
  action: "apt_install"
  packages:
    - "git"
    - "cmake"
    - "ninja-build"
    - "python3"
    - "python3-pip=23.0.1-1" # version pinning supported
```

**Fields:**

| Field      | Required | Description                                                      |
| ---------- | -------- | ---------------------------------------------------------------- |
| `packages` | yes      | List of package names. Supports version pinning with `=version`. |

---

#### `run_command` — Execute a shell command

Runs an arbitrary bash command. Runs as root by default. Use `run_as` to run as a different user (via `su - user -c`).

```yaml
- name: "Update APT cache"
  action: "run_command"
  command: "apt-get update -y"
  always_run: true

- name: "Install west as user"
  action: "run_command"
  run_as: "vagrant"
  command: |
    pip3 install --user west
    west --version
```

**Fields:**

| Field     | Required | Description                                                                                            |
| --------- | -------- | ------------------------------------------------------------------------------------------------------ |
| `command` | yes      | Shell command or multi-line block scalar. Not expanded for environment variables (prevents injection). |
| `run_as`  | no       | Run command as this user via `su -`. Loads user's login environment.                                   |

---

#### `get_file` — Download a file with checksum verification

Downloads a file to a destination path and verifies its SHA256 checksum. Fails if checksum does not match.

```yaml
- name: "Download SDK installer"
  action: "get_file"
  url: "https://example.com/sdk-installer.sh"
  sha256: "abc123..."
  dest: "/tmp/sdk-installer.sh"
  creates: "/tmp/sdk-installer.sh"
```

**Fields:**

| Field    | Required | Description                                                          |
| -------- | -------- | -------------------------------------------------------------------- |
| `url`    | yes      | HTTPS URL to download from.                                          |
| `sha256` | yes      | Expected SHA256 checksum of the file.                                |
| `dest`   | yes      | Destination file path. Parent directories are created automatically. |

---

#### `unpack` — Extract a local archive

Unpacks a local `.tar` archive to a destination directory.

```yaml
- name: "Unpack downloaded archive"
  action: "unpack"
  source: "/tmp/toolchain.tar.gz"
  dest: "/opt/toolchain"
  strip_components: 1
```

**Fields:**

| Field              | Required | Description                                                                 |
| ------------------ | -------- | --------------------------------------------------------------------------- |
| `source`           | yes      | Path to the local archive file.                                             |
| `dest`             | yes      | Destination directory.                                                      |
| `strip_components` | no       | Number of leading path components to strip (like `tar --strip-components`). |

---

#### `unarchive_from_url` — Download and extract in one step

Downloads an archive from a URL, verifies its checksum, and extracts it. Equivalent to `get_file` + `unpack`.

```yaml
- name: "Install Go"
  action: "unarchive_from_url"
  url: "https://go.dev/dl/go1.22.linux-amd64.tar.gz"
  sha256: "abc123..."
  dest: "/usr/local"
  strip_components: 0
  creates: "/usr/local/go/bin/go"
  per_arch:
    amd64:
      url: "https://go.dev/dl/go1.22.linux-amd64.tar.gz"
      sha256: "amd64-hash"
    arm64:
      url: "https://go.dev/dl/go1.22.linux-arm64.tar.gz"
      sha256: "arm64-hash"
```

**Fields:**

| Field              | Required | Description                                 |
| ------------------ | -------- | ------------------------------------------- |
| `url`              | yes      | HTTPS URL to download from.                 |
| `sha256`           | yes      | Expected SHA256 checksum.                   |
| `dest`             | yes      | Destination directory for extraction.       |
| `strip_components` | no       | Number of leading path components to strip. |

---

#### `unarchive_from_ref` — Extract from a catalog toolchain reference

Downloads and extracts an archive whose URL and checksum are resolved from the `alloy.lock.yml` lockfile (generated by `alloy-host resolve`). This is the recommended way to install versioned toolchains defined in the blueprint's `toolchains:` section.

```yaml
- name: "Install ARM GNU Embedded Toolchain"
  action: "unarchive_from_ref"
  ref: "toolchain.arm-gnu.arm-none-eabi@stable"
  dest: "{{.Vars.ARM_TOOLCHAIN_DEST}}"
  strip_components: 1
  creates: "{{.Vars.ARM_TOOLCHAIN_DEST}}/bin/arm-none-eabi-gcc"
  mode: "USER_RWX GROUP_RX OTHER_RX"
  owner: "root:root"
```

**Fields:**

| Field              | Required | Description                                                 |
| ------------------ | -------- | ----------------------------------------------------------- |
| `ref`              | yes      | Catalog reference key, must match an alias in the lockfile. |
| `dest`             | yes      | Destination directory.                                      |
| `strip_components` | no       | Leading path components to strip.                           |

---

#### `write_env_file` — Write a configuration file

Writes text content to a file. Smart idempotency: if the file already exists and the content is identical (SHA256 match), the write is skipped.

```yaml
- name: "Add ARM toolchain to PATH"
  action: "write_env_file"
  file: "/etc/profile.d/10-arm-toolchain.sh"
  content: |
    #!/bin/sh
    export PATH=$PATH:{{.Vars.ARM_TOOLCHAIN_DEST}}/bin
  mode: "USER_RWX GROUP_RX OTHER_RX"
```

**Fields:**

| Field     | Required | Description                                 |
| --------- | -------- | ------------------------------------------- |
| `file`    | yes      | Destination file path.                      |
| `content` | yes      | File content (supports variable expansion). |

---

#### `install_target_lib` — Install a .deb into a toolchain sysroot

Downloads a `.deb` package and installs its contents into an SDK sysroot directory (via `dpkg-deb` + `rsync`). Used for cross-compilation target libraries.

```yaml
- name: "Install libssl into sysroot"
  action: "install_target_lib"
  url: "https://example.com/libssl-dev_arm64.deb"
  sha256: "abc123..."
```

**Fields:**

| Field    | Required | Description                             |
| -------- | -------- | --------------------------------------- |
| `url`    | yes      | URL of the `.deb` package.              |
| `sha256` | yes      | Expected SHA256 checksum of the `.deb`. |

The sysroot destination is read from the `SDK_SYSROOT` variable.

---

#### `build_from_source` — Download, extract, and build from source

Downloads a source archive, extracts it, and runs a build command inside the extracted directory.

```yaml
- name: "Build custom tool from source"
  action: "build_from_source"
  url: "https://example.com/tool-src.tar.gz"
  sha256: "abc123..."
  dest: "/opt/tool"
  command: "./configure && make && make install"
  creates: "/opt/tool/bin/tool"
```

**Fields:**

| Field     | Required | Description                                          |
| --------- | -------- | ---------------------------------------------------- |
| `url`     | yes      | URL of the source archive.                           |
| `sha256`  | yes      | Expected SHA256 checksum.                            |
| `dest`    | yes      | Directory where sources are extracted.               |
| `command` | yes      | Build command to run inside the extracted directory. |

---

### Common Task Options

These options are available on **all** task actions:

| Option       | Description                                                                                                                                     |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `name`       | Human-readable task identifier (required).                                                                                                      |
| `creates`    | If this path exists, skip the task entirely before any other check. Most efficient idempotency guard.                                           |
| `always_run` | Set to `true` to bypass all idempotency checks and always execute.                                                                              |
| `skip_if`    | Shell expression: skip the task if exit code is 0. E.g. `skip_if: "[ \"$ALLOY_BACKEND\" = \"wsl2\" ]"`.                                         |
| `run_as`     | Execute as this user (only applies to `run_command`).                                                                                           |
| `owner`      | Set ownership of `dest` or `file` after task success. Format: `user:group`. Applied recursively.                                                |
| `mode`       | Set permissions of `dest` or `file` after task success. Accepts octal (`0755`) or symbolic (`USER_RWX GROUP_RX OTHER_RX`). Applied recursively. |
| `per_arch`   | Architecture-specific value overrides. See [Architecture Support](#architecture-support-per_arch).                                              |

---

### Idempotency System

The provisioner uses a three-layer idempotency system to ensure safe re-runs:

**Layer 1: `creates:` guard** (fastest)

If the specified path already exists, the task is skipped before anything else runs. Use this when the task's result is a file or directory:

```yaml
- name: "Install Go"
  action: "unarchive_from_url"
  url: "..."
  dest: "/usr/local"
  creates: "/usr/local/go/bin/go" # skip if this binary already exists
```

**Layer 2: State file tracking (`alloy.state.yml`)**

After each task completes, the provisioner records a SHA256 fingerprint of the task's resolved inputs in `alloy.state.yml`. On subsequent runs:

- Matching fingerprint → task skipped.
- Different fingerprint (e.g. URL or package list changed) → task re-executed.
- Failed tasks are always retried.

To force a full re-provision from scratch, delete the state file:

```bash
rm ~/.alloy-it/alloy.state.yml
alloy-provisioner
```

#### **Layer 3: Adapter-level smart checks**

Some adapters perform their own checks before executing:

- `apt_install`: Checks each package with `dpkg -s`; only installs missing packages.
- `write_env_file`: Compares SHA256 of file content; skips if identical.

**Override: `always_run`**

To bypass all idempotency and always execute (e.g. for cache cleanup):

```yaml
- name: "Update APT cache"
  action: "run_command"
  command: "apt-get update -y"
  always_run: true
```

---

### Variable Expansion

Variables from `manifest.yml`'s `variables:` block are available in task fields using Go template syntax:

```yaml
# manifest.yml
variables:
  TOOLCHAIN_DEST: "/opt/arm-none-eabi"

# task file
- name: "Create toolchain dir"
  action: "run_command"
  command: "mkdir -p {{.Vars.TOOLCHAIN_DEST}}"
  creates: "{{.Vars.TOOLCHAIN_DEST}}"
```

**Environment variable injection:**

Environment variables present in the process environment at runtime are merged into the variable set. This allows overriding manifest variables or injecting secrets:

```bash
export VM_USER=myuser
export GITLAB_TOKEN=glpat-xxx
alloy-provisioner
```

In task fields (other than `run_command`'s `command`), environment variables are expanded via `$VAR` or `${VAR}` syntax.

**Toolchain reference variables:**

When a `toolchains:` entry is defined in `manifest.yml` with an alias (e.g. `alias: ARM_TOOLCHAIN`), the executor injects two variables after resolving `alloy.lock.yml`:

- `ARM_TOOLCHAIN_URL` — the resolved download URL
- `ARM_TOOLCHAIN_SHA` — the resolved SHA256 checksum

These can be used in `unarchive_from_url` tasks or accessed via `unarchive_from_ref`.

---

### Architecture Support (`per_arch`)

The provisioner detects the current system architecture (`amd64` or `arm64`) automatically using `uname -m`. Task fields can be overridden per architecture using a `per_arch:` block:

```yaml
- name: "Install cross-compiler"
  action: "unarchive_from_url"
  dest: "/opt/toolchain"
  creates: "/opt/toolchain/bin/gcc"
  per_arch:
    amd64:
      url: "https://example.com/toolchain-amd64.tar.gz"
      sha256: "amd64-checksum-here"
    arm64:
      url: "https://example.com/toolchain-arm64.tar.gz"
      sha256: "arm64-checksum-here"
```

The matching architecture block is merged into the task before execution. Fields present in `per_arch` override the top-level values. Fields not present in `per_arch` keep their top-level values.

Supported fields in `per_arch`: `url`, `sha256`, `command`, `source`.

---

### Security

- **SHA256 verification:** All downloads (`get_file`, `unarchive_from_url`, `install_target_lib`, `build_from_source`) require a `sha256` field and fail if the checksum does not match. This prevents tampering and MITM attacks.
- **No command injection:** The `command` field in `run_command` is not expanded for environment variables, preventing accidental or malicious injection through variable values.
- **Path sandboxing:** Blueprint YAML files are parsed with a sandbox check that prevents tasks from reading files outside the blueprint directory.
- **Secure file permissions:** Temporary files created during downloads use restrictive permissions (`0600`/`0700`) by default.
- **HTTPS only:** Download URLs must use `http://` or `https://`; other schemes are rejected.

---

## Running Inside an alloy-host VM

This is the **primary and recommended workflow**. `alloy-host` manages the full VM lifecycle: it creates the VM, generates the bootstrap script, installs `alloy-provisioner` inside the guest, and runs the blueprint automatically. You do not interact with `alloy-provisioner` directly.

### Prerequisites (host machine)

- [`alloy-host`](https://github.com/alloy-it/alloy-host) installed and in `PATH`
- [VirtualBox](https://www.virtualbox.org/) and [Vagrant](https://developer.hashicorp.com/vagrant) installed (on Windows: WSL2 is also supported)
- Internet access (to download the Ubuntu base box and blueprint toolchains)

### Step 1: Initialize the VM

```bash
alloy-host init <vm-name> --blueprint <project/blueprint-name>
```

**Example:**

```bash
alloy-host init nrf91-dev --blueprint nordic/nrf91
```

This creates a local directory `nrf91-dev/` containing:

```TOML
nrf91-dev/
├── Vagrantfile           # VirtualBox VM configuration (Ubuntu 22.04, 2GB RAM, 2 CPUs)
├── home-data.vdi         # 10 GB persistent virtual disk (mounted at /home/vagrant)
├── scripts/
│   └── bootstrap.sh      # Provisioning entry point (downloads + runs alloy-provisioner)
├── .alloy-blueprint      # Stores the blueprint identifier
└── .alloy-backend        # Backend type (vagrant or wsl2)
```

The VM is registered in `~/.alloy-it/vm/vms.yaml`. The `home-data.vdi` disk persists across VM rebuilds — your source code, builds, and configuration survive even if you destroy and recreate the VM.

### Step 2: Start and Provision the VM

```bash
alloy-host up <vm-name>
```

**Example:**

```bash
alloy-host up nrf91-dev
```

`alloy-host` starts the VM via Vagrant (or WSL2) and runs `bootstrap.sh` inside the guest. The bootstrap script:

1. Detects the guest architecture (`dpkg --print-architecture`)
2. Downloads the correct `alloy-provisioner` `.deb` package for that architecture from this releases repository
3. Installs `alloy-provisioner` via `dpkg`
4. Calls `alloy-provisioner install nordic/nrf91` (or `alloy-provisioner --blueprint-dir ...` for local blueprints)

`alloy-provisioner` then runs the blueprint: it pulls the blueprint from the registry (`api.alloy-it.io`), reads `manifest.yml`, and executes all tasks in `run_order`. Progress is printed to stdout.

This step can take several minutes on first run, depending on the blueprint (toolchain downloads, package installs).

### Step 3: Re-provision

To apply changes after a blueprint update or to retry failed tasks:

```bash
alloy-host provision <vm-name>
```

**Example:**

```bash
alloy-host provision nrf91-dev
```

This re-runs `bootstrap.sh` inside the running guest. Because `alloy-provisioner` is idempotent, only changed or not-yet-completed tasks are executed. Tasks that completed successfully on a prior run are skipped.

### Step 4: Connect to the VM

```bash
alloy-host ssh <vm-name>
```

**Example:**

```bash
alloy-host ssh nrf91-dev
```

Opens an SSH shell inside the VM as the `vagrant` user.

### Step 5: Manage the VM Lifecycle

```bash
# Pause the VM (saves state, fast resume)
alloy-host stop nrf91-dev

# Resume a stopped VM (without re-provisioning)
alloy-host up nrf91-dev

# Destroy the VM (removes the OS disk and VM; keeps home-data.vdi and config)
alloy-host destroy nrf91-dev

# Rebuild from scratch (provision again after destroy)
alloy-host up nrf91-dev

# Completely wipe everything including the persistent data disk
alloy-host destroy nrf91-dev --all
```

### Persistent Data Disk

The `home-data.vdi` is a 10 GB virtual disk mounted at `/home/vagrant` inside the guest. It is preserved when you run `alloy-host destroy` (without `--all`). This means:

- Your source code, build artifacts, and configuration in `/home/vagrant` survive a VM rebuild.
- After `alloy-host destroy && alloy-host up`, the OS and tools are reinstalled from the blueprint, but your personal files remain.
- Only `alloy-host destroy --all` removes the persistent disk.

### Multiple VMs

You can have multiple VMs for different projects or blueprints:

```bash
alloy-host init nrf91-dev --blueprint nordic/nrf91
alloy-host init rpi5-dev  --blueprint raspberry-pi/raspberry-pi-5

alloy-host list              # Show all VMs and their status
alloy-host up nrf91-dev
alloy-host up rpi5-dev
alloy-host ssh nrf91-dev
```

### USB Device Passthrough

To connect hardware devices (debuggers, development kits) to the VM:

```bash
alloy-host usb list                         # List available USB devices on the host
alloy-host usb attach "J-Link"              # Attach device to running VM
alloy-host usb detach "J-Link"             # Detach device from VM
```

### Complete Example: Nordic nRF91

```bash
# 1. Initialize the VM with the Nordic nRF91 blueprint
alloy-host init nrf91-dev --blueprint nordic/nrf91

# 2. Start the VM and run provisioning (first run: ~10-20 min)
alloy-host up nrf91-dev

# 3. Connect and verify the environment
alloy-host ssh nrf91-dev
arm-none-eabi-gcc --version
west --version
nrfjprog --version

# 4. Work on your project inside the VM...

# 5. Pause when not in use
alloy-host stop nrf91-dev

# 6. Resume later
alloy-host up nrf91-dev
```

---

## Running Natively on Linux

Use this workflow to run `alloy-provisioner` directly on a Linux machine (e.g. a Raspberry Pi, a cloud instance, or a CI runner) without `alloy-host` or VirtualBox.

### Prerequisites

- Linux (Debian/Ubuntu-based, glibc)
- Architecture: `amd64` or `arm64`
- Standard Linux tools available: `apt-get`, `dpkg`, `tar`, `bash`, `su`, `rsync`, `uname`
- Internet access (to download toolchains and pull blueprints from the registry)
- Root or `sudo` access (most provisioning tasks require root)

### Step 1: Install alloy-provisioner

#### Option A: Debian/Ubuntu package (recommended)

The `.deb` package installs the binary to `/usr/local/bin/alloy-provisioner`.

```bash
# Detect your architecture
ARCH=$(dpkg --print-architecture)   # prints "amd64" or "arm64"

# Download and install the latest release
wget "https://github.com/alloy-it/alloy-provisioner-releases/releases/download/latest/alloy-provisioner_latest_linux_${ARCH}.deb"
sudo dpkg -i "alloy-provisioner_latest_linux_${ARCH}.deb"

# Verify installation
alloy-provisioner -version
```

For a specific version (replace `v1.2.3` and `1.2.3` with the desired tag and version):

```bash
wget "https://github.com/alloy-it/alloy-provisioner-releases/releases/download/v1.2.3/alloy-provisioner_1.2.3_linux_amd64.deb"
sudo dpkg -i "alloy-provisioner_1.2.3_linux_amd64.deb"
```

#### Option B: Tar.gz archive

```bash
ARCH=$(dpkg --print-architecture)
wget "https://github.com/alloy-it/alloy-provisioner-releases/releases/download/latest/alloy-provisioner_linux_${ARCH}.tar.gz"
tar -xzf "alloy-provisioner_linux_${ARCH}.tar.gz"
sudo mv alloy-provisioner /usr/local/bin/
alloy-provisioner -version
```

Optionally verify checksums before installing:

```bash
wget "https://github.com/alloy-it/alloy-provisioner-releases/releases/download/latest/checksums.txt"
sha256sum -c checksums.txt --ignore-missing
```

### Step 2: Prepare Your Blueprint

#### **Option A: Use a community blueprint from the registry (easiest)**

The public registry at `api.alloy-it.io` hosts community blueprints. No credentials required.

Pull a blueprint to `~/.alloy-it/` (the default blueprint directory):

```bash
alloy-provisioner clone community/raspberry-pi
```

This downloads the blueprint files to `~/.alloy-it/` and prints the path.

#### **Option B: Write your own blueprint**

Create the blueprint directory and add your files:

```bash
mkdir -p ~/.alloy-it

# Create manifest.yml
cat > ~/.alloy-it/manifest.yml << 'EOF'
name: "My Dev Environment"
version: "1.0.0"

variables:
  VM_USER: "myuser"

run_order:
  - "00-system.yml"
EOF

# Create a task file
cat > ~/.alloy-it/00-system.yml << 'EOF'
- name: "Install dev tools"
  action: "apt_install"
  packages:
    - "git"
    - "curl"
    - "build-essential"
EOF
```

### Step 3: Configure Secrets and Environment (Optional)

If your blueprint needs credentials (e.g. for a private registry or private downloads), create a `.env` file:

```bash
# Create env file next to your blueprint
cat > ~/.alloy-it/.env << 'EOF'
ALLOY_REGISTRY_USERNAME=myuser
ALLOY_REGISTRY_PASSWORD=my-token
GITLAB_TOKEN=glpat-xxx
EOF

# Restrict permissions
chmod 600 ~/.alloy-it/.env
```

The provisioner does **not** load `.env` files automatically. Source the file before running:

```bash
set -a && source ~/.alloy-it/.env && set +a
```

### Step 4: Run the Provisioner

#### Run with a local blueprint directory

```bash
# Run with the default blueprint directory (~/.alloy-it)
sudo alloy-provisioner

# Or specify a different directory
sudo alloy-provisioner -blueprint-dir /path/to/my-blueprint

# Or set via environment variable
export ALLOY_BLUEPRINT_DIR=/path/to/my-blueprint
sudo alloy-provisioner
```

> **Note:** Most tasks require root privileges (package installation, writing to `/opt`, `/etc`, etc.). Run as root or with `sudo`. Tasks using `run_as: myuser` still need the process to start as root to perform the `su` switch.

#### Pull from registry and run in one step (`install` subcommand)

```bash
# Pull the blueprint from the registry and run it immediately
sudo alloy-provisioner install community/raspberry-pi

# Specify a tag
sudo alloy-provisioner install community/nrf91:1.0.13

# Use a custom registry
sudo alloy-provisioner install myproject/my-blueprint --registry my-registry.example.com
```

#### Pull only, without running (`clone` subcommand)

```bash
# Pull blueprint files to ~/.alloy-it without running
alloy-provisioner clone community/raspberry-pi

# Inspect the downloaded blueprint, then run manually
sudo alloy-provisioner
```

#### Pull then run (legacy `-pull` flag)

```bash
sudo alloy-provisioner -pull -repository community/raspberry-pi
sudo alloy-provisioner -pull -repository community/nrf91 -tag 1.0.13
```

### Step 5: Re-run and Re-provision

If you run the provisioner again, it reads `alloy.state.yml` and skips already-completed tasks. This is safe and fast:

```bash
sudo alloy-provisioner   # only runs tasks that haven't completed or have changed
```

To force a full re-provision (re-run all tasks from scratch):

```bash
sudo rm ~/.alloy-it/alloy.state.yml
sudo alloy-provisioner
```

To force a single task to re-run, set `always_run: true` in its definition.

### Complete Example: Provision a Raspberry Pi

```bash
# 1. Install alloy-provisioner on the Raspberry Pi (arm64)
ARCH=$(dpkg --print-architecture)
wget "https://github.com/alloy-it/alloy-provisioner-releases/releases/download/latest/alloy-provisioner_latest_linux_${ARCH}.deb"
sudo dpkg -i "alloy-provisioner_latest_linux_${ARCH}.deb"

# 2. Run the Raspberry Pi community blueprint
sudo alloy-provisioner install community/raspberry-pi

# 3. Check provisioning completed successfully
alloy-provisioner -version

# 4. Re-provision after a blueprint update (safe, idempotent)
sudo alloy-provisioner install community/raspberry-pi
```

---

## Reference

### CLI Subcommands

| Command                                  | Description                                          |
| ---------------------------------------- | ---------------------------------------------------- |
| `alloy-provisioner`                      | Run provisioning from the local blueprint directory. |
| `alloy-provisioner install <name[:tag]>` | Pull blueprint from registry and run it.             |
| `alloy-provisioner clone <name[:tag]>`   | Pull blueprint from registry without running it.     |

### Flags and Parameters

| Flag / Env variable   | Description                                                                        | Default           |
| --------------------- | ---------------------------------------------------------------------------------- | ----------------- |
| `-blueprint-dir`      | Path to the blueprint directory. Overrides `ALLOY_BLUEPRINT_DIR`.                  | `$HOME/.alloy-it` |
| `ALLOY_BLUEPRINT_DIR` | Same as `-blueprint-dir`; flag takes precedence.                                   | —                 |
| `-pull`               | Pull blueprint from registry before running (legacy; prefer `install` subcommand). | `false`           |
| `-registry`           | Registry URL. Overrides `ALLOY_REGISTRY`.                                          | `api.alloy-it.io` |
| `ALLOY_REGISTRY`      | Same as `-registry`; flag takes precedence.                                        | `api.alloy-it.io` |
| `-repository`         | Repository path (e.g. `community/raspberry-pi`). Required with `-pull`.            | (none)            |
| `-tag`                | Blueprint tag/version.                                                             | `latest`          |
| `-platform`           | Force OS/architecture (e.g. `linux/arm64`). Default: current machine.              | (auto-detect)     |
| `-version`            | Print version and exit.                                                            | —                 |
| `-config`             | **Deprecated.** Use `-blueprint-dir` instead.                                      | (none)            |

### Environment Variables

| Variable                  | Purpose                                                                                      |
| ------------------------- | -------------------------------------------------------------------------------------------- |
| `ALLOY_BLUEPRINT_DIR`     | Blueprint directory path.                                                                    |
| `ALLOY_REGISTRY`          | Registry URL for pulling blueprints.                                                         |
| `ALLOY_REGISTRY_USERNAME` | Username for private registry authentication.                                                |
| `ALLOY_REGISTRY_PASSWORD` | Password or token for private registry authentication.                                       |
| Any custom variable       | Merged into blueprint global vars; available via `{{.Vars.NAME}}` or `$NAME` in task fields. |

### Blueprint `manifest.yml` Reference

| Field             | Required | Description                                                                          |
| ----------------- | -------- | ------------------------------------------------------------------------------------ |
| `name`            | yes      | Human-readable blueprint name.                                                       |
| `version`         | yes      | Blueprint version string.                                                            |
| `description`     | no       | Short description.                                                                   |
| `variables`       | no       | Key-value map of global variables, expanded in tasks.                                |
| `toolchains`      | no       | List of catalog toolchain references (`ref`, `alias`) resolved via `alloy.lock.yml`. |
| `supported_hosts` | no       | List of supported OS/arch platforms (e.g. `linux/amd64`).                            |
| `run_order`       | yes      | Ordered list of task YAML filenames to execute.                                      |

### Task Action Quick Reference

| Action               | Main Fields                                 | Description                                 |
| -------------------- | ------------------------------------------- | ------------------------------------------- |
| `apt_install`        | `packages`                                  | Install Debian packages via apt-get.        |
| `run_command`        | `command`, `run_as`                         | Run a shell command.                        |
| `get_file`           | `url`, `sha256`, `dest`                     | Download a file with checksum verification. |
| `unpack`             | `source`, `dest`, `strip_components`        | Extract a local archive.                    |
| `unarchive_from_url` | `url`, `sha256`, `dest`, `strip_components` | Download and extract.                       |
| `unarchive_from_ref` | `ref`, `dest`, `strip_components`           | Extract from a catalog toolchain reference. |
| `write_env_file`     | `file`, `content`                           | Write a configuration file.                 |
| `install_target_lib` | `url`, `sha256`                             | Install a .deb into a toolchain sysroot.    |
| `build_from_source`  | `url`, `sha256`, `dest`, `command`          | Download, extract, and build from source.   |
