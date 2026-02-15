# alloy-provisioner-releases

Public release repository for **alloy-provisioner**: the Alloy guest VM provisioning engine. Binaries and packages are published here for download; the source code lives in a separate private repository.

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

| Variable                  | Purpose                                                                                                |
| ------------------------- | ------------------------------------------------------------------------------------------------------ |
| `ALLOY_BLUEPRINT_DIR`     | Blueprint directory (overridden by `-blueprint-dir`).                                                  |
| `ALLOY_REGISTRY`          | Registry URL when using `-pull` (overridden by `-registry`). Default: `api.alloy-it.io` (public community registry). |
| `ALLOY_REGISTRY_USERNAME` | Username for a **private** registry (only needed when pulling from non-public registries).              |
| `ALLOY_REGISTRY_PASSWORD` | Password or token for a **private** registry (only needed when pulling from non-public registries).    |
| Any other vars            | Merged into blueprint global vars; useful for task expansion (e.g. `GITLAB_TOKEN`, `SDK_DESTINATION`). |

Restrict permissions on the env file so only your user can read it: `chmod 600 $HOME/.alloy-it/.env`.

### Pull blueprint from registry, then run

The provisioner defaults to the **public community registry** at `api.alloy-it.io`. No credentials are needed to pull community blueprints from this registry (see [alloy-publisher](https://github.com/alloy-it/alloy-publisher) for how blueprints are published there).

**Using the default community registry (no auth):**

```bash
# Pull a community blueprint; only -repository is required (registry defaults to api.alloy-it.io)
alloy-provisioner -pull -repository community/raspberry-pi
alloy-provisioner -pull -repository community/esp32 -tag latest
```

Repository path format is `project/blueprint-name`, e.g. `community/raspberry-pi`, `community/esp32`, `community/nrf91`.

**Using a custom registry (e.g. private):**

```bash
# Override registry via flag or ALLOY_REGISTRY; set ALLOY_REGISTRY_USERNAME / ALLOY_REGISTRY_PASSWORD if the registry is private
alloy-provisioner -pull -registry <registry-url> -repository <project/blueprint-name> [-tag <tag>]
```

Example with env file for private registry auth:

```bash
set -a && source "$HOME/.alloy-it/.env" && set +a
alloy-provisioner -pull -registry my-registry.example.com -repository myproject/my-blueprint -tag latest
```

---

## Flags and parameters

| Flag / env            | Description                                                                                 | Default                  |
| --------------------- | ------------------------------------------------------------------------------------------- | ------------------------ |
| `-blueprint-dir`      | Path to the blueprint directory (contains `manifest.yml`). Overrides `ALLOY_BLUEPRINT_DIR`. | `$HOME/.alloy-it` or `.` |
| `ALLOY_BLUEPRINT_DIR` | Same as `-blueprint-dir`; flag takes precedence.                                            | —                        |
| `-pull`               | Pull blueprint from Alloy Imageregistry before running.                                           | `false`                  |
| `-registry`           | Alloy Imageregistry URL. Overrides `ALLOY_REGISTRY`.                                               | `api.alloy-it.io`   |
| `ALLOY_REGISTRY`      | Same as `-registry`; flag takes precedence.                                                | `api.alloy-it.io`   |
| `-repository`         | Repository path (e.g. `community/raspberry-pi`). **Required when `-pull` is set.**         | (none)                   |
| `-tag`                | Alloy Imageartifact tag.                                                                          | `latest`                 |
| `-version`            | Print version and exit.                                                                     | —                        |
| `-config`             | **Deprecated.** Use `-blueprint-dir` or `ALLOY_BLUEPRINT_DIR` instead.                      | (none)                   |

---

## Release assets

Each versioned release (e.g. `v1.2.3`) includes:

- **Packages:** `alloy-provisioner_<version>_linux_amd64.deb`, `alloy-provisioner_<version>_linux_arm64.deb`
- **Archives:** `alloy-provisioner_linux_amd64.tar.gz`, `alloy-provisioner_linux_arm64.tar.gz`
- **Checksums:** `checksums.txt`
- **SBOM:** `alloy-provisioner_linux_amd64.sbom.json`, `alloy-provisioner_linux_arm64.sbom.json`

The **latest** release provides the same artifacts under fixed filenames (`..._latest_linux_amd64.deb`, etc.) for stable download URLs.
