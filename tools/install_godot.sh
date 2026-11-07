#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$SCRIPT_DIR/godot-version.txt"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "Error: Version file not found at $VERSION_FILE" >&2
  exit 1
fi

GODOT_VERSION="$(grep -E '^GODOT_VERSION=' "$VERSION_FILE" | cut -d= -f2-)"
GODOT_SHA512="$(grep -E '^GODOT_SHA512=' "$VERSION_FILE" | cut -d= -f2-)"

if [[ -z "$GODOT_VERSION" || -z "$GODOT_SHA512" ]]; then
  echo "Error: GODOT_VERSION or GODOT_SHA512 missing in $VERSION_FILE" >&2
  exit 1
fi

BINARY_NAME="Godot_v${GODOT_VERSION}_linux.x86_64"
INSTALL_DIR="$REPO_ROOT/.tools/godot"
BINARY_PATH="$INSTALL_DIR/$BINARY_NAME"

# Check if pinned version is already installed
if [[ -x "$BINARY_PATH" ]]; then
  echo "Godot $GODOT_VERSION is already installed at $BINARY_PATH."
  exit 0
fi

# Download into a fresh temporary directory
TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ZIP_NAME="${BINARY_NAME}.zip"
DOWNLOAD_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${ZIP_NAME}"
ZIP_PATH="$TMP_DIR/$ZIP_NAME"

echo "Downloading Godot ${GODOT_VERSION} from ${DOWNLOAD_URL}..."
curl -fsSL "$DOWNLOAD_URL" -o "$ZIP_PATH"

# Verify SHA-512
echo "Verifying SHA-512 checksum..."
CALCULATED_SHA512="$(sha512sum "$ZIP_PATH" | awk '{print $1}')"

if [[ "$CALCULATED_SHA512" != "$GODOT_SHA512" ]]; then
  echo "Error: SHA-512 checksum mismatch for $ZIP_NAME" >&2
  echo "Expected: $GODOT_SHA512" >&2
  echo "Got:      $CALCULATED_SHA512" >&2
  rm -f "$ZIP_PATH"
  exit 1
fi

# Extract into .tools/godot/
mkdir -p "$INSTALL_DIR"
echo "Extracting $ZIP_NAME into $INSTALL_DIR..."
unzip -q -o "$ZIP_PATH" -d "$INSTALL_DIR"

if [[ ! -f "$BINARY_PATH" ]]; then
  echo "Error: Expected binary $BINARY_PATH not found after extraction." >&2
  exit 1
fi

chmod +x "$BINARY_PATH"
echo "Godot installed successfully:"
"$BINARY_PATH" --version
