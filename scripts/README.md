# install.sh — Bootstrap Installer

`install.sh` is the one-liner bootstrap script for **alloy-provisioner**. Visitors run it in a single `curl | bash` command and the script handles platform detection, download, checksum verification, and installation automatically.

---

## Where to host the script

The script must be reachable at a **stable, short URL** that you can post everywhere. There are two options — pick one:

### Option A — Serve it from the website (recommended)

Place `install.sh` at the root of the **alloy-it.io** web server so it is reachable at:

```
https://alloy-it.io/install.sh
```

Concretely, copy the file to the static assets directory of your site (e.g. `docs/install.sh` in MkDocs, or whatever the web root is) **and make sure it is served with `Content-Type: text/plain`** so browsers / curl / wget receive it as plain text.

For MkDocs Material, drop it here:

```
alloy-docs/
└── docs/
    └── install.sh   ← copy this file here
```

MkDocs copies anything that is not `.md` straight to the site root, so it will be published at the URL above without extra configuration.

### Option B — Use the raw GitHub URL (zero-effort)

No hosting setup is required. Use the raw GitHub URL directly:

```
https://raw.githubusercontent.com/alloy-it/alloy-provisioner-releases/main/scripts/install.sh
```

This works immediately but the URL is long and hard to type. Use Option A for anything user-facing; keep this URL as a fallback.

---

## What to post on the website

### Short form (after Option A is set up)

```bash
curl -fsSL https://alloy-it.io/install.sh | bash
```

### Long form / GitHub fallback

```bash
curl -fsSL https://raw.githubusercontent.com/alloy-it/alloy-provisioner-releases/main/scripts/install.sh | bash
```

### Pin to a specific version

Pass the version as a positional argument using `bash -s --`:

```bash
curl -fsSL https://alloy-it.io/install.sh | bash -s -- 1.2.3
```

Or via environment variable (both forms accept `1.2.3` and `v1.2.3`):

```bash
ALLOY_PROVISIONER_VERSION=1.2.3 curl -fsSL https://alloy-it.io/install.sh | bash
```

When running the script directly:

```bash
./install.sh            # latest
./install.sh 1.2.3      # pinned version
./install.sh v1.2.3     # leading "v" is also accepted
```

---

## Complete copy-paste block for the website

Below is a ready-to-paste block that covers the three most common cases. Drop this into any docs page (MkDocs, Notion, a landing page, etc.):

````markdown
## Install alloy-provisioner

The fastest way to install is with the bootstrap script:

```bash
curl -fsSL https://alloy-it.io/install.sh | bash
```

> **Requirements:** Linux only (`amd64` or `arm64`). The script needs `curl` or `wget`, `tar`, `sha256sum`, and `sudo` access.

The script auto-detects your architecture and installs the binary to `/usr/local/bin/alloy-provisioner`.

**Install a specific version:**

```bash
# Positional argument form (recommended for curl | bash)
curl -fsSL https://alloy-it.io/install.sh | bash -s -- 1.2.3

# Environment variable form
ALLOY_PROVISIONER_VERSION=1.2.3 curl -fsSL https://alloy-it.io/install.sh | bash
```

**Verify the install:**

```bash
alloy-provisioner -version
```

Prefer a manual install? Download `.deb` packages or tar.gz archives directly from the
[releases page](https://github.com/alloy-it/alloy-provisioner-releases/releases).
````

---

## How the script works (summary for the website FAQ)

| Step | What happens |
|------|-------------|
| 1 | Detects OS (`Linux` only) and architecture (`amd64` / `arm64`) |
| 2 | Downloads `checksums.txt` from the release |
| 3 | Downloads the `.deb` package on Debian/Ubuntu, or a `tar.gz` on other distros |
| 4 | Verifies the SHA256 checksum before touching anything on disk |
| 5 | Installs the binary to `/usr/local/bin` (via `dpkg -i` or `install -m 0755`) |
| 6 | Prints the installed version to confirm success |

All downloaded files are placed in a temporary directory that is cleaned up automatically on exit, whether the install succeeds or fails.

---

## Environment variables (advanced)

| Variable | Default | Purpose |
|----------|---------|---------|
| `ALLOY_PROVISIONER_VERSION` | *(latest)* | Install an exact version, e.g. `1.2.3` (overridden by positional arg) |
| `INSTALL_DIR` | `/usr/local/bin` | Override the installation directory |
| `USE_DEB` | auto | Set to `1` to force `.deb`, `0` to force `tar.gz` |
| `NO_COLOR` | unset | Set to any value to disable coloured output |
