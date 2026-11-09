#!/usr/bin/env bash
set -euo pipefail

# Upfront system and tool checks
if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Error: Unsupported OS '$(uname -s)'. This script requires Linux." >&2
  exit 1
fi

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "Error: Unsupported architecture '$(uname -m)'. This script requires x86_64." >&2
  exit 1
fi

for cmd in curl unzip sha512sum; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: Required command '$cmd' not found in PATH." >&2
    exit 1
  fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$SCRIPT_DIR/godot-version.txt"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "Error: Version file not found at $VERSION_FILE" >&2
  exit 1
fi

GODOT_VERSION="$(grep -E '^GODOT_VERSION=' "$VERSION_FILE" | cut -d= -f2- || true)"
GODOT_SHA512="$(grep -E '^GODOT_SHA512=' "$VERSION_FILE" | cut -d= -f2- || true)"

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

# Download and extract into a temporary directory inside the same filesystem
mkdir -p "$REPO_ROOT/.tools"
TMP_DIR="$(mktemp -d "$REPO_ROOT/.tools/tmp.XXXXXXXXXX")"
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

# Extract into temp directory, verify binary, chmod +x, and mv into .tools/godot/ last
UNPACK_DIR="$TMP_DIR/unpack"
mkdir -p "$UNPACK_DIR"
echo "Extracting $ZIP_NAME into temporary directory..."
unzip -q -o "$ZIP_PATH" -d "$UNPACK_DIR"

EXTRACTED_BINARY="$UNPACK_DIR/$BINARY_NAME"
if [[ ! -f "$EXTRACTED_BINARY" ]]; then
  echo "Error: Expected binary $BINARY_NAME not found after extraction." >&2
  exit 1
fi

chmod +x "$EXTRACTED_BINARY"
mkdir -p "$INSTALL_DIR"
mv -f "$EXTRACTED_BINARY" "$INSTALL_DIR/"

echo "Godot installed successfully:"
"$BINARY_PATH" --version
