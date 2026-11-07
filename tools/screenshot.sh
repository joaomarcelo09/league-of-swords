#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Usage help
usage() {
  echo "Usage: $0 [--scene=res://path.tscn] [--frames=N] [--out=path.png]"
  exit "${1:-0}"
}

# Check for xvfb-run
if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "Error: xvfb-run is required but not installed or not found in PATH." >&2
  exit 1
fi

# Check for Godot wrapper
if [[ ! -x "$REPO_ROOT/tools/godot" ]]; then
  echo "Error: Godot wrapper script not found or not executable at $REPO_ROOT/tools/godot" >&2
  exit 1
fi

# Parse arguments
SCENE="res://scenes/main.tscn"
FRAMES=60
OUT=".screenshots/shot.png"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scene=*)
      SCENE="${1#*=}"
      shift
      ;;
    --scene)
      if [[ $# -lt 2 ]]; then
        echo "Error: --scene requires an argument." >&2
        usage 1
      fi
      SCENE="$2"
      shift 2
      ;;
    --frames=*)
      FRAMES="${1#*=}"
      shift
      ;;
    --frames)
      if [[ $# -lt 2 ]]; then
        echo "Error: --frames requires an argument." >&2
        usage 1
      fi
      FRAMES="$2"
      shift 2
      ;;
    --out=*)
      OUT="${1#*=}"
      shift
      ;;
    --out)
      if [[ $# -lt 2 ]]; then
        echo "Error: --out requires an argument." >&2
        usage 1
      fi
      OUT="$2"
      shift 2
      ;;
    -h|--help)
      usage 0
      ;;
    *)
      echo "Error: Unknown argument: $1" >&2
      usage 1
      ;;
  esac
done

# Validate scene existence
if [[ "$SCENE" =~ ^res://(.*) ]]; then
  SCENE_FILE="$REPO_ROOT/${BASH_REMATCH[1]}"
  if [[ ! -f "$SCENE_FILE" ]]; then
    echo "Error: Scene file does not exist: $SCENE" >&2
    exit 1
  fi
elif [[ "$SCENE" = /* ]]; then
  if [[ ! -f "$SCENE" ]]; then
    echo "Error: Scene file does not exist: $SCENE" >&2
    exit 1
  fi
else
  if [[ -f "$REPO_ROOT/$SCENE" ]]; then
    SCENE="res://$SCENE"
  elif [[ -f "$SCENE" ]]; then
    # Keep as-is or relative
    true
  else
    echo "Error: Scene file does not exist: $SCENE" >&2
    exit 1
  fi
fi

# Determine absolute path for output PNG
if [[ "$OUT" = /* ]]; then
  ABS_OUT="$OUT"
else
  ABS_OUT="$PWD/$OUT"
fi

# Ensure output directory exists
mkdir -p "$(dirname "$ABS_OUT")"

# Remove pre-existing file if present
rm -f "$ABS_OUT"

# Import assets first if needed
if [[ ! -f "$REPO_ROOT/.godot/global_script_class_cache.cfg" || ! -d "$REPO_ROOT/.godot/imported" || "$REPO_ROOT/project.godot" -nt "$REPO_ROOT/.godot/global_script_class_cache.cfg" ]]; then
  "$REPO_ROOT/tools/godot" --headless --import --path "$REPO_ROOT"
fi

OUTPUT_FILE="$(mktemp)"
cleanup() {
  rm -f "$OUTPUT_FILE"
}
trap cleanup EXIT

set +e
xvfb-run -a -s "-screen 0 1280x720x24" "$REPO_ROOT/tools/godot" \
  --path "$REPO_ROOT" \
  --rendering-driver opengl3 \
  --resolution 1280x720 \
  "$SCENE" \
  -- \
  --screenshot="$ABS_OUT" \
  --frames="$FRAMES" > "$OUTPUT_FILE" 2>&1
EXIT_CODE="$?"
set -e

if [[ "$EXIT_CODE" -ne 0 ]]; then
  echo "Error: Godot exited with code $EXIT_CODE" >&2
  cat "$OUTPUT_FILE" >&2
  exit "$EXIT_CODE"
fi

if grep -E "SCRIPT ERROR|Parse Error" "$OUTPUT_FILE" >/dev/null; then
  echo "Error: Script error detected in Godot output:" >&2
  cat "$OUTPUT_FILE" >&2
  exit 1
fi

if [[ ! -f "$ABS_OUT" ]]; then
  echo "Error: Screenshot file was not created at $OUT" >&2
  cat "$OUTPUT_FILE" >&2
  exit 1
fi

echo "$OUT"
exit 0
