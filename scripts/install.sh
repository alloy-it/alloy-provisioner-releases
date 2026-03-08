#!/usr/bin/env bash
# install.sh — Bootstrap installer for alloy-provisioner
#
# Usage (always latest):
#   curl -sSfL https://alloy-it.io/install.sh | bash
#
# Usage (pinned version — two equivalent forms):
#   curl -sSfL https://alloy-it.io/install.sh | bash -s -- 1.2.3
#   ALLOY_PROVISIONER_VERSION=1.2.3 curl -sSfL https://alloy-it.io/install.sh | bash
#
# When running the script directly:
#   ./install.sh            # latest
#   ./install.sh 1.2.3      # pinned version
#
# Environment variables (all optional):
#   ALLOY_PROVISIONER_VERSION  Exact version, e.g. "1.2.3" (overridden by positional arg)
#   INSTALL_DIR                Where to install the binary (default: /usr/local/bin)
#   USE_DEB                    Set to "0" to skip .deb and use tar.gz instead
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
if [ $# -ge 1 ]; then
  VERSION="${1#v}"
elif [ -n "${ALLOY_PROVISIONER_VERSION:-}" ]; then
  VERSION="${ALLOY_PROVISIONER_VERSION#v}"
else
  VERSION=""   # empty = latest
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
    die "Neither curl nor wget found. Please install one and retry."
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
if [ -n "$VERSION" ]; then
  # Strip leading "v" if the user includes it
  VERSION="${VERSION#v}"
  TAG="v${VERSION}"
  DEB_FILENAME="${BINARY}_${VERSION}_linux_${ARCH}.deb"
else
  TAG="latest"
  DEB_FILENAME="${BINARY}_latest_linux_${ARCH}.deb"
fi

TAR_FILENAME="${BINARY}_linux_${ARCH}.tar.gz"
CHECKSUMS_FILENAME="checksums.txt"

BASE_URL="https://github.com/${REPO}/releases/download/${TAG}"

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
printf "\n${BOLD}alloy-provisioner installer${RESET}\n"
printf "  Binary : %s\n" "$BINARY"
printf "  Version: %s\n" "${VERSION:-latest}"
printf "  OS/Arch: linux/%s\n" "$ARCH"
printf "  Install: %s\n\n" "$INSTALL_DIR"

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------
need_cmd uname
need_cmd tar
need_cmd sha256sum

# ---------------------------------------------------------------------------
# Temporary workspace
# ---------------------------------------------------------------------------
TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

# ---------------------------------------------------------------------------
# Download checksums
# ---------------------------------------------------------------------------
info "Downloading checksums from ${TAG} release…"
CHECKSUMS_FILE="$TMPDIR_WORK/$CHECKSUMS_FILENAME"
if ! download "${BASE_URL}/${CHECKSUMS_FILENAME}" "$CHECKSUMS_FILE"; then
  die "Failed to download checksums from ${BASE_URL}/${CHECKSUMS_FILENAME}"
fi

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

  # Verify checksum
  info "Verifying checksum…"
  EXPECTED_SUM="$(grep " ${DEB_FILENAME}$" "$CHECKSUMS_FILE" | awk '{print $1}')"
  if [ -z "$EXPECTED_SUM" ]; then
    warn "No checksum entry found for ${DEB_FILENAME} in checksums.txt — skipping verification."
  else
    ACTUAL_SUM="$(sha256sum "$DEB_FILE" | awk '{print $1}')"
    [ "$ACTUAL_SUM" = "$EXPECTED_SUM" ] || die "Checksum mismatch!\n  expected: ${EXPECTED_SUM}\n  got:      ${ACTUAL_SUM}"
    success "Checksum verified."
  fi

  info "Installing package (requires sudo)…"
  sudo dpkg -i "$DEB_FILE"

# ---------------------------------------------------------------------------
# Install via tar.gz — fallback or explicit
# ---------------------------------------------------------------------------
else
  info "Downloading ${TAR_FILENAME}…"
  TAR_FILE="$TMPDIR_WORK/$TAR_FILENAME"
  if ! download "${BASE_URL}/${TAR_FILENAME}" "$TAR_FILE"; then
    die "Failed to download ${BASE_URL}/${TAR_FILENAME}"
  fi

  # Verify checksum
  info "Verifying checksum…"
  EXPECTED_SUM="$(grep " ${TAR_FILENAME}$" "$CHECKSUMS_FILE" | awk '{print $1}')"
  if [ -z "$EXPECTED_SUM" ]; then
    warn "No checksum entry found for ${TAR_FILENAME} in checksums.txt — skipping verification."
  else
    ACTUAL_SUM="$(sha256sum "$TAR_FILE" | awk '{print $1}')"
    [ "$ACTUAL_SUM" = "$EXPECTED_SUM" ] || die "Checksum mismatch!\n  expected: ${EXPECTED_SUM}\n  got:      ${ACTUAL_SUM}"
    success "Checksum verified."
  fi

  # Extract
  info "Extracting archive…"
  tar -xzf "$TAR_FILE" -C "$TMPDIR_WORK"

  EXTRACTED_BINARY="$TMPDIR_WORK/$BINARY"
  [ -f "$EXTRACTED_BINARY" ] || die "Binary '${BINARY}' not found after extraction."

  # Install
  info "Installing to ${INSTALL_DIR} (requires sudo)…"
  sudo install -m 0755 "$EXTRACTED_BINARY" "${INSTALL_DIR}/${BINARY}"
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
  INSTALLED_VERSION="$("$INSTALLED_PATH" -version 2>&1 || true)"
  printf "\n${BOLD}${GREEN}Installation complete!${RESET}\n"
  success "Binary : ${INSTALLED_PATH}"
  success "Version: ${INSTALLED_VERSION}"
fi

printf "\n${CYAN}Get started:${RESET}\n"
printf "  alloy-provisioner -help\n\n"
