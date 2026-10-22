#!/usr/bin/env bash
# install.sh — Bootstrap installer for alloy-provisioner
#
# Usage (always latest):
#   curl -sSfL https://alloy-it.io/install.sh | bash
#
# Usage (pinned version — two equivalent forms):
#   curl -sSfL https://alloy-it.io/install.sh | bash -s -- 1.2.3
#   curl -sSfL https://alloy-it.io/install.sh | ALLOY_PROVISIONER_VERSION=1.2.3 bash
#
# When running the script directly:
#   ./install.sh            # latest
#   ./install.sh 1.2.3      # pinned version
#
# Environment variables (all optional):
#   ALLOY_PROVISIONER_VERSION  Exact version, e.g. "1.2.3" (overridden by positional arg)
#   INSTALL_DIR                Where to install the binary (default: /usr/local/bin)
#   USE_DEB                    Set to "0" to skip .deb and use tar.gz instead
#   ALLOY_REQUIRE_CHECKSUM     Set to "1" to abort when checksums.txt is missing
#   ALLOY_CHECKSUM_OVERRIDE    Test hook: force checksum verification to fail
#   NO_COLOR                   Set to any value to disable coloured output

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REPO="alloy-it/alloy-provisioner-releases"
BINARY="alloy-provisioner"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
USE_DEB="${USE_DEB:-}"                     # empty = auto-detect

# Positional argument takes precedence over the environment variable.
# Strip a leading "v" so both "1.2.3" and "v1.2.3" are accepted.
VERSION_SOURCE=""
if [ $# -ge 1 ]; then
  VERSION="${1#v}"
  VERSION_SOURCE="positional argument"
elif [ -n "${ALLOY_PROVISIONER_VERSION:-}" ]; then
  VERSION="${ALLOY_PROVISIONER_VERSION#v}"
  VERSION_SOURCE="ALLOY_PROVISIONER_VERSION environment variable"
else
  VERSION=""   # empty = latest
  VERSION_SOURCE="latest GitHub release"
fi

# ---------------------------------------------------------------------------
# Colours (disabled when not a terminal or NO_COLOR is set)
# ---------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD='\033[1m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  RED='\033[0;31m'
  CYAN='\033[0;36m'
  RESET='\033[0m'
else
  BOLD='' GREEN='' YELLOW='' RED='' CYAN='' RESET=''
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()    { printf "${CYAN}==>${RESET} %s\n" "$*"; }
success() { printf "${GREEN}✓${RESET}  %s\n" "$*"; }
warn()    { printf "${YELLOW}warn:${RESET} %s\n" "$*" >&2; }
die()     { printf "${RED}error:${RESET} %s\n" "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1 — please install it and retry."
}

# Download helper: prefer curl, fall back to wget
download() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -sSfL --retry 3 --retry-delay 2 -o "$dest" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --tries=3 --waitretry=2 -O "$dest" "$url"
  else
    die "Neither curl nor wget found — install one (e.g. apt-get install -y curl) and retry."
  fi
}

# Download without failing the script (e.g. optional checksums.txt)
download_optional() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -sSfL --retry 3 --retry-delay 2 -o "$dest" "$url" 2>/dev/null
  elif command -v wget >/dev/null 2>&1; then
    wget -q --tries=3 --waitretry=2 -O "$dest" "$url" 2>/dev/null
  else
    return 1
  fi
}

run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "Root privileges required — run as root or install sudo."
  fi
}

# Newest semver version (without "v") from GitHub releases, or empty on failure.
resolve_newest_semver_version() {
  local api_url="https://api.github.com/repos/${REPO}/releases?per_page=30"
  local releases_json
  releases_json="$(mktemp)"
  if command -v curl >/dev/null 2>&1; then
    if ! curl -sSfL --retry 3 --retry-delay 2 -o "$releases_json" "$api_url"; then
      rm -f "$releases_json"
      return 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget -q --tries=3 --waitretry=2 -O "$releases_json" "$api_url"; then
      rm -f "$releases_json"
      return 1
    fi
  else
    rm -f "$releases_json"
    return 1
  fi
  # Plain X.Y.Z tags from non-draft, non-prerelease releases only (no python/jq).
  local ver
  ver="$(awk '
    function flush() {
      if (tag == "") return
      if (pre != 0 || dr != 0) { tag = ""; return }
      if (tag ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/ || tag ~ /^[0-9]+\.[0-9]+\.[0-9]+$/) {
        sub(/^v/, "", tag)
        print tag
      }
      tag = ""
    }
    BEGIN { tag = ""; pre = 1; dr = 1 }
    /^[[:space:]]*\{/ { flush(); pre = 1; dr = 1 }
    /"tag_name"/ {
      line = $0
      sub(/.*"tag_name"[[:space:]]*:[[:space:]]*"/, "", line)
      sub(/".*/, "", line)
      tag = line
    }
    /"prerelease"/ {
      if ($0 ~ /"prerelease"[[:space:]]*:[[:space:]]*false/) pre = 0
      else pre = 1
    }
    /"draft"/ {
      if ($0 ~ /"draft"[[:space:]]*:[[:space:]]*false/) dr = 0
      else dr = 1
    }
    END { flush() }
  ' "$releases_json" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)"
  rm -f "$releases_json"
  [ -n "$ver" ] || return 1
  printf '%s\n' "$ver"
}

# Verify artifact against checksums.txt from the same release.
verify_artifact_checksum() {
  local artifact_path="$1"
  local artifact_name="$2"
  local checksums_path="$TMPDIR_WORK/checksums.txt"

  if [ -n "${ALLOY_CHECKSUM_OVERRIDE:-}" ]; then
    local actual
    if command -v sha256sum >/dev/null 2>&1; then
      actual="$(sha256sum "$artifact_path" | awk '{print $1}')"
    elif command -v shasum >/dev/null 2>&1; then
      actual="$(shasum -a 256 "$artifact_path" | awk '{print $1}')"
    else
      die "Neither sha256sum nor shasum found — cannot verify checksum."
    fi
    if [ "$actual" != "$ALLOY_CHECKSUM_OVERRIDE" ]; then
      rm -f "$artifact_path"
      die "Checksum verification failed for ${artifact_name}."
    fi
    success "Checksum verified for ${artifact_name}"
    return 0
  fi

  if ! download_optional "${BASE_URL}/checksums.txt" "$checksums_path"; then
    if [ "${ALLOY_REQUIRE_CHECKSUM:-}" = "1" ]; then
      rm -f "$artifact_path"
      die "checksums.txt not found at ${BASE_URL}/checksums.txt (ALLOY_REQUIRE_CHECKSUM=1)."
    fi
    warn "checksums.txt not found for this release — skipping verification."
    return 0
  fi

  if ! grep -qF "$artifact_name" "$checksums_path"; then
    rm -f "$artifact_path"
    die "checksums.txt has no entry for ${artifact_name}."
  fi

  local verify_dir checksum_line checksum_only
  verify_dir="$(dirname "$artifact_path")"
  checksum_line="$(grep -F "$artifact_name" "$checksums_path" | head -1)"
  checksum_only="$TMPDIR_WORK/checksum-verify.txt"
  printf '%s\n' "$checksum_line" > "$checksum_only"

  if command -v sha256sum >/dev/null 2>&1; then
    if ! (cd "$verify_dir" && sha256sum -c "$checksum_only"); then
      rm -f "$artifact_path"
      die "Checksum verification failed for ${artifact_name}."
    fi
  elif command -v shasum >/dev/null 2>&1; then
    if ! (cd "$verify_dir" && shasum -a 256 -c "$checksum_only"); then
      rm -f "$artifact_path"
      die "Checksum verification failed for ${artifact_name}."
    fi
  else
    die "Neither sha256sum nor shasum found — cannot verify checksum."
  fi
  success "Checksum verified for ${artifact_name}"
}

apt_install_deb() {
  local deb_file="$1"
  if ! run_as_root apt-get install -y "$deb_file"; then
    info "Refreshing package lists and retrying…"
    run_as_root apt-get update -qq
    run_as_root apt-get install -y "$deb_file"
  fi
}

# ---------------------------------------------------------------------------
# Platform checks
# ---------------------------------------------------------------------------
OS="$(uname -s)"
ARCH_RAW="$(uname -m)"

[ "$OS" = "Linux" ] || die "alloy-provisioner only supports Linux (detected: $OS)."

case "$ARCH_RAW" in
  x86_64)  ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *)        die "Unsupported architecture: $ARCH_RAW (only amd64 and arm64 are supported)." ;;
esac

# ---------------------------------------------------------------------------
# Detect Debian/Ubuntu for .deb preference
# ---------------------------------------------------------------------------
is_debian_based() {
  [ -f /etc/debian_version ] || grep -qiE 'debian|ubuntu' /etc/os-release 2>/dev/null
}

if [ -z "$USE_DEB" ]; then
  is_debian_based && USE_DEB="1" || USE_DEB="0"
fi

# ---------------------------------------------------------------------------
# Resolve tag and filenames
# ---------------------------------------------------------------------------
USE_FLOATING_LATEST="0"
if [ -z "$VERSION" ]; then
  if resolved="$(resolve_newest_semver_version 2>/dev/null)" && [ -n "$resolved" ]; then
    VERSION="$resolved"
    VERSION_SOURCE="newest release"
  else
    warn "Could not resolve the newest semver release from GitHub — falling back to floating 'latest' (checksum cannot be verified)."
    USE_FLOATING_LATEST="1"
    VERSION_SOURCE="floating latest (checksum not verified)"
  fi
fi

if [ -n "$VERSION" ]; then
  VERSION="${VERSION#v}"
  TAG="v${VERSION}"
  DEB_FILENAME="${BINARY}_${VERSION}_linux_${ARCH}.deb"
  TAR_FILENAME="${BINARY}_linux_${ARCH}.tar.gz"
elif [ "$USE_FLOATING_LATEST" = "1" ]; then
  TAG="latest"
  DEB_FILENAME="${BINARY}_latest_linux_${ARCH}.deb"
  TAR_FILENAME="${BINARY}_latest_linux_${ARCH}.tar.gz"
fi

BASE_URL="https://github.com/${REPO}/releases/download/${TAG}"

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
printf "\n${BOLD}alloy-provisioner installer${RESET}\n"
printf "  Binary : %s\n" "$BINARY"
if [ "$VERSION_SOURCE" = "newest release" ]; then
  printf "  Version: %s (newest release)\n" "$VERSION"
elif [ -n "$VERSION" ]; then
  printf "  Version: %s (from %s)\n" "$VERSION" "$VERSION_SOURCE"
else
  printf "  Version: latest (from %s)\n" "$VERSION_SOURCE"
fi
printf "  OS/Arch: linux/%s\n" "$ARCH"
printf "  Install: %s\n\n" "$INSTALL_DIR"

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------
need_cmd uname
need_cmd tar

# ---------------------------------------------------------------------------
# Temporary workspace
# ---------------------------------------------------------------------------
TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

# ---------------------------------------------------------------------------
# Install via .deb (Debian/Ubuntu) — preferred
# ---------------------------------------------------------------------------
if [ "$USE_DEB" = "1" ]; then
  if ! command -v dpkg >/dev/null 2>&1; then
    warn "dpkg not found — falling back to tar.gz install."
    USE_DEB="0"
  fi
fi

if [ "$USE_DEB" = "1" ]; then
  info "Downloading ${DEB_FILENAME}…"
  DEB_FILE="$TMPDIR_WORK/$DEB_FILENAME"
  if ! download "${BASE_URL}/${DEB_FILENAME}" "$DEB_FILE"; then
    die "Failed to download ${BASE_URL}/${DEB_FILENAME}"
  fi

  verify_artifact_checksum "$DEB_FILE" "$DEB_FILENAME"

  info "Installing package (resolves dependencies via apt)…"
  apt_install_deb "$DEB_FILE"

# ---------------------------------------------------------------------------
# Install via tar.gz — fallback or explicit
# ---------------------------------------------------------------------------
else
  info "Downloading ${TAR_FILENAME}…"
  TAR_FILE="$TMPDIR_WORK/$TAR_FILENAME"
  if ! download "${BASE_URL}/${TAR_FILENAME}" "$TAR_FILE"; then
    die "Failed to download ${BASE_URL}/${TAR_FILENAME}"
  fi

  verify_artifact_checksum "$TAR_FILE" "$TAR_FILENAME"

  # Extract
  info "Extracting archive…"
  tar -xzf "$TAR_FILE" -C "$TMPDIR_WORK"

  EXTRACTED_BINARY="$TMPDIR_WORK/$BINARY"
  [ -f "$EXTRACTED_BINARY" ] || die "Binary '${BINARY}' not found after extraction."

  # Install
  info "Installing to ${INSTALL_DIR}…"
  if [ -w "$INSTALL_DIR" ] 2>/dev/null; then
    install -m 0755 "$EXTRACTED_BINARY" "${INSTALL_DIR}/${BINARY}"
  else
    run_as_root install -m 0755 "$EXTRACTED_BINARY" "${INSTALL_DIR}/${BINARY}"
  fi
fi

# ---------------------------------------------------------------------------
# Verify installation
# ---------------------------------------------------------------------------
INSTALLED_PATH="$(command -v "$BINARY" 2>/dev/null || true)"
if [ -z "$INSTALLED_PATH" ]; then
  warn "${BINARY} not found in PATH after install."
  warn "Make sure ${INSTALL_DIR} is in your PATH, e.g. add to ~/.bashrc:"
  warn "  export PATH=\"\$PATH:${INSTALL_DIR}\""
else
  INSTALLED_VERSION="$("$INSTALLED_PATH" --version 2>&1 || true)"
  printf "\n${BOLD}${GREEN}Installation complete!${RESET}\n"
  success "Binary : ${INSTALLED_PATH}"
  success "Version: ${INSTALLED_VERSION}"
fi

printf "\n${CYAN}Get started:${RESET}\n"
printf "  alloy-provisioner --help\n\n"
