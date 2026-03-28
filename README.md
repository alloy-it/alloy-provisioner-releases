# alloy-provisioner-releases

Public release repository for **alloy-provisioner**: the Alloy guest VM provisioning engine. Binaries and packages are published here for download; the source code lives in a separate private repository.

For a full walkthrough of features and usage see the **[User Guide](docs/user-guide.md)**.

---

## Compatibility

| Platform  | Architectures    | Notes                                                             |
| --------- | ---------------- | ----------------------------------------------------------------- |
| **Linux** | `amd64`, `arm64` | Only Linux builds are published. Static binary (`CGO_ENABLED=0`). |

- **OS:** Linux only (e.g. Debian, Ubuntu, other glibc-based distros).
- **Architectures:** `linux/amd64`, `linux/arm64`.
- Versioned releases (e.g. `v1.2.3`) and a **latest** release (stable URLs) are available.

---

## Download & Unpack

### Option 1: Debian/Ubuntu package (recommended)

Installs the binary to `/usr/local/bin/alloy-provisioner`.

**Versioned (e.g. v1.2.3):**

```bash
# amd64
wget https://github.com/alloy-it/alloy-provisioner-releases/releases/download/<TAG>/alloy-provisioner_<VERSION>_linux_amd64.deb
sudo dpkg -i alloy-provisioner_<VERSION>_linux_amd64.deb

# arm64
wget https://github.com/alloy-it/alloy-provisioner-releases/releases/download/<TAG>/alloy-provisioner_<VERSION>_linux_arm64.deb
sudo dpkg -i alloy-provisioner_<VERSION>_linux_arm64.deb
```

**Always latest (stable URLs):**

```bash
# amd64
wget https://github.com/alloy-it/alloy-provisioner-releases/releases/download/latest/alloy-provisioner_latest_linux_amd64.deb
sudo dpkg -i alloy-provisioner_latest_linux_amd64.deb

# arm64
wget https://github.com/alloy-it/alloy-provisioner-releases/releases/download/latest/alloy-provisioner_latest_linux_arm64.deb
sudo dpkg -i alloy-provisioner_latest_linux_arm64.deb
```

Replace `<TAG>` with a release tag (e.g. `v1.2.3`) and `<VERSION>` with the numeric version (e.g. `1.2.3`).

### Option 2: Tar.gz archive

Unpack the archive and run the binary from the extracted directory.

**Download (example for amd64, versioned):**

```bash
wget https://github.com/alloy-it/alloy-provisioner-releases/releases/download/<TAG>/alloy-provisioner_linux_amd64.tar.gz
```

**Unpack:**

```bash
tar -xzf alloy-provisioner_linux_amd64.tar.gz
```

This produces an `alloy-provisioner` binary in the current directory. Optionally move it to a directory in your `PATH` (e.g. `/usr/local/bin`):

```bash
sudo mv alloy-provisioner /usr/local/bin/
chmod +x /usr/local/bin/alloy-provisioner
```

**Verify:**

```bash
alloy-provisioner -version
```

Optional: verify checksums using `checksums.txt` from the same release before unpacking or installing.

### Checking for updates

To see whether a newer release is available, run:

```bash
alloy-provisioner update-check
```

If an update is available, download the new `.deb` or archive from the [releases page](https://github.com/alloy-it/alloy-provisioner-releases/releases/latest) (see [Download & Unpack](#download--unpack) above). When using alloy-host, re-provisioning or creating a new dev-vm will typically pull the provisioner version configured by the blueprint or the latest from this repo.

---

## Usage

### Basic run (local blueprint directory)

Default blueprint directory is `$HOME/.alloy-it` (or `.` if home cannot be determined). Override with a flag or environment variable:

```bash
# Use default directory ($HOME/.alloy-it)
./alloy-provisioner

# Specify blueprint directory
./alloy-provisioner -blueprint-dir /path/to/your/blueprint

# Or set once via environment
export ALLOY_BLUEPRINT_DIR=/path/to/your/blueprint
./alloy-provisioner
```

### Environment file

alloy-provisioner does **not** load a `.env` file itself; it only reads variables from the **process environment**. To use an env file on the host machine, put it in a fixed location and **source it** before running the binary so those variables are in the environment when the provisioner runs.

#### **Where to save the env file**

- **Recommended:** In your **blueprint directory**, e.g. `$HOME/.alloy-it/.env`. That keeps secrets and config next to the blueprint and works whether you use the default blueprint dir or override it with `-blueprint-dir`.
- **Alternative:** Any path you prefer (e.g. `$HOME/.config/alloy-provisioner/env`), as long as you source that file before running the tool.

#### **How to use it**

1. Copy the example and edit (do not commit the file with real secrets):

   ```bash
   cp /path/to/.env.example $HOME/.alloy-it/.env
   # edit $HOME/.alloy-it/.env and set ALLOY_REGISTRY_*, GITLAB_TOKEN, etc.
   ```

2. Source the env file, then run the provisioner in the same shell:

   ```bash
   set -a
   source "$HOME/.alloy-it/.env"
   set +a
   alloy-provisioner
   ```

   Or in one line:

   ```bash
   set -a && source "$HOME/.alloy-it/.env" && set +a && alloy-provisioner
   ```

   If your blueprint dir is elsewhere, use that path: `source "/path/to/your/blueprint/.env"`.

#### **Variables the tool reads from the environment**

| Variable                  | Purpose                                                                                                              |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `ALLOY_BLUEPRINT_DIR`     | Blueprint directory (overridden by `-blueprint-dir`).                                                                |
| `ALLOY_REGISTRY`          | Registry URL when using `-pull` (overridden by `-registry`). Default: `api.alloy-it.io` (public community registry). |
| `ALLOY_REGISTRY_USERNAME` | Username for a **private** registry (only needed when pulling from non-public registries).                           |
| `ALLOY_REGISTRY_PASSWORD` | Password or token for a **private** registry (only needed when pulling from non-public registries).                  |
| Any other vars            | Merged into blueprint global vars; useful for task expansion (e.g. `GITLAB_TOKEN`, `SDK_DESTINATION`).               |

Restrict permissions on the env file so only your user can read it: `chmod 600 $HOME/.alloy-it/.env`.

### Browse and pull blueprints from the registry

The provisioner defaults to the **public community registry** at `api.alloy-it.io`. No credentials are needed for community blueprints.

**Discover available blueprints:**

```bash
# List all community blueprints (no auth required)
alloy-provisioner clone --list community
```

**Clone (inspect before installing):**

```bash
alloy-provisioner clone community/nordic/nrf91:1.1.3 --output ./my-blueprint
# inspect files, then:
sudo alloy-provisioner install --blueprint-dir ./my-blueprint
```

**Pull and run immediately:**

```bash
sudo alloy-provisioner install community/nordic/nrf91:1.1.3
sudo alloy-provisioner install community/raspberry-pi/raspberry-pi-5:1.0.3
```

**Using a custom/private registry:**

```bash
set -a && source "$HOME/.alloy-it/.env" && set +a
sudo alloy-provisioner install myproject/my-blueprint:1.0.0 --registry my-registry.example.com
```

Legacy flags `-pull`, `-repository`, `-tag` are still accepted but the `install` and `clone` subcommands are preferred.

---

## Subcommands

| Subcommand                       | Description                                                               |
| -------------------------------- | ------------------------------------------------------------------------- |
| `install [name[:tag]]`           | Pull a blueprint from the registry and run it; or run a local blueprint with `--blueprint-dir`. |
| `clone <name[:tag]>`             | Pull blueprint files locally without running them.                        |
| `clone --list <project>`         | List all blueprints available in a registry project (no auth required for `community`). |
| `catalog update`                 | Clone/pull the alloy-catalog repo into `~/.alloy-it/catalog/`.           |
| `catalog search <query>`         | Search toolchain descriptors by ID, name, or tag.                        |
| `catalog info <id[@version]>`    | Show versions, providers, and platform assets for a toolchain.           |
| `update-check`                   | Check whether a newer provisioner release is available.                  |

## Flags and parameters

| Flag / env            | Description                                                                                 | Default                  |
| --------------------- | ------------------------------------------------------------------------------------------- | ------------------------ |
| `--blueprint-dir`     | Path to the blueprint directory (contains `manifest.yml`). Overrides `ALLOY_BLUEPRINT_DIR`. | `$HOME/.alloy-it` or `.` |
| `ALLOY_BLUEPRINT_DIR` | Same as `--blueprint-dir`; flag takes precedence.                                           | —                        |
| `--registry`          | Alloy registry URL for `install`/`clone`. Overrides `ALLOY_REGISTRY`.                      | `api.alloy-it.io`        |
| `ALLOY_REGISTRY`      | Same as `--registry`; flag takes precedence.                                                | `api.alloy-it.io`        |
| `--env-file`          | Path to a KEY=VALUE env file to load before provisioning.                                   | (none)                   |
| `--dry-run`           | Validate blueprint and print execution plan without running tasks.                          | `false`                  |
| `--docker`            | Activate the `docker` environment tag (skips tasks with `exclude: [docker]`).              | `false`                  |
| `--wsl2`              | Activate the `wsl2` environment tag (skips tasks with `exclude: [wsl2]`).                  | `false`                  |
| `--version`           | Print version and exit.                                                                     | —                        |
| `-pull`, `-repository`, `-tag` | **Deprecated legacy flags.** Use `install`/`clone` subcommands instead.          | —                        |

---

## Release assets

Each versioned release (e.g. `v1.2.3`) includes:

- **Packages:** `alloy-provisioner_<version>_linux_amd64.deb`, `alloy-provisioner_<version>_linux_arm64.deb`
- **Archives:** `alloy-provisioner_linux_amd64.tar.gz`, `alloy-provisioner_linux_arm64.tar.gz`
- **Checksums:** `checksums.txt`
- **SBOM:** `alloy-provisioner_linux_amd64.sbom.json`, `alloy-provisioner_linux_arm64.sbom.json`

The **latest** release provides the same artifacts under fixed filenames (`..._latest_linux_amd64.deb`, etc.) for stable download URLs.
