#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Usage help
usage() {
  local exit_code="${1:-0}"
  if [[ "$exit_code" -eq 0 ]]; then
    echo "Usage: $0 [--scene=res://path.tscn] [--frames=N] [--out=path.png] [--timeout=SECS] [--preview=NAME] [--focus-tile=X,Y] [-- ...]"
  else
    echo "Usage: $0 [--scene=res://path.tscn] [--frames=N] [--out=path.png] [--timeout=SECS] [--preview=NAME] [--focus-tile=X,Y] [-- ...]" >&2
  fi
  exit "$exit_code"
}

# Parse arguments first so --help works without xvfb
SCENE="res://scenes/main.tscn"
FRAMES=60
OUT=""
DEFAULT_OUT="$REPO_ROOT/.screenshots/shot.png"
TIMEOUT="${SCREENSHOT_TIMEOUT:-60}"
EXTRA_ARGS=()

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
    --timeout=*)
      TIMEOUT="${1#*=}"
      shift
      ;;
    --timeout)
      if [[ $# -lt 2 ]]; then
        echo "Error: --timeout requires an argument." >&2
        usage 1
      fi
      TIMEOUT="$2"
      shift 2
      ;;
    --preview=*)
      EXTRA_ARGS+=("$1")
      shift
      ;;
    --preview)
      if [[ $# -lt 2 ]]; then
        echo "Error: --preview requires an argument." >&2
        usage 1
      fi
      EXTRA_ARGS+=("--preview=$2")
      shift 2
      ;;
    --focus-tile=*)
      EXTRA_ARGS+=("--focus_tile=${1#*=}")
      shift
      ;;
    --focus-tile)
      if [[ $# -lt 2 ]]; then
        echo "Error: --focus-tile requires an argument." >&2
        usage 1
      fi
      EXTRA_ARGS+=("--focus_tile=$2")
      shift 2
      ;;
    --)
      shift
      EXTRA_ARGS+=("$@")
      break
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

# Validate frames (positive integer: error + usage to stderr, exit 1)
if [[ ! "$FRAMES" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --frames must be a positive integer, got '$FRAMES'." >&2
  usage 1
fi

# Validate timeout
if [[ ! "$TIMEOUT" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [[ "$TIMEOUT" =~ ^0+(\.0+)?$ ]]; then
  echo "Error: --timeout must be a positive number, got '$TIMEOUT'." >&2
  usage 1
fi

# Validate scene
# --scene accepts only res://... or a repo-relative path (resolved against REPO_ROOT, converted to res://). Reject absolute and CWD-relative paths.
if [[ "$SCENE" =~ ^res://(.*) ]]; then
  SCENE_FILE="$REPO_ROOT/${BASH_REMATCH[1]}"
  if [[ ! -f "$SCENE_FILE" ]]; then
    echo "Error: Scene file does not exist: $SCENE" >&2
    exit 1
  fi
elif [[ "$SCENE" = /* ]]; then
  echo "Error: Absolute paths not allowed for --scene: $SCENE" >&2
  exit 1
elif [[ "$SCENE" == .* ]]; then
  echo "Error: CWD-relative paths not allowed for --scene: $SCENE" >&2
  exit 1
else
  SCENE_FILE="$REPO_ROOT/$SCENE"
  if [[ ! -f "$SCENE_FILE" ]]; then
    echo "Error: Scene file does not exist in repository: $SCENE" >&2
    exit 1
  fi
  SCENE="res://$SCENE"
fi

# Determine absolute path for output PNG
if [[ -z "$OUT" ]]; then
  ABS_OUT="$DEFAULT_OUT"
elif [[ "$OUT" = /* ]]; then
  ABS_OUT="$OUT"
else
  ABS_OUT="$PWD/$OUT"
fi

# Check for xvfb-run
if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "Error: xvfb-run is required but not installed or not found in PATH." >&2
  exit 1
fi

# Check for timeout
if ! command -v timeout >/dev/null 2>&1; then
  echo "Error: timeout is required but not installed or not found in PATH." >&2
  exit 1
fi

# Check for Godot wrapper
if [[ ! -x "$REPO_ROOT/tools/godot" ]]; then
  echo "Error: Godot wrapper script not found or not executable at $REPO_ROOT/tools/godot" >&2
  exit 1
fi

# Ensure output directory exists
mkdir -p "$(dirname "$ABS_OUT")"
rm -f "$ABS_OUT"

# Import first if needed (reusing the same import-trigger as tools/test.sh)
CACHE_FILE="$REPO_ROOT/.godot/global_script_class_cache.cfg"
SEARCH_DIRS=()
for dir in "$REPO_ROOT/src" "$REPO_ROOT/test" "$REPO_ROOT/scenes"; do
  if [[ -d "$dir" ]]; then
    SEARCH_DIRS+=("$dir")
  fi
done

NEED_IMPORT=0
if [[ ! -f "$CACHE_FILE" || ! -d "$REPO_ROOT/.godot/imported" || "$REPO_ROOT/project.godot" -nt "$CACHE_FILE" ]]; then
  NEED_IMPORT=1
elif [[ ${#SEARCH_DIRS[@]} -gt 0 ]] && [[ -n "$(find "${SEARCH_DIRS[@]}" -type f -name "*.gd" -newer "$CACHE_FILE" -print -quit 2>/dev/null)" ]]; then
  NEED_IMPORT=1
fi

if [[ "$NEED_IMPORT" -eq 1 ]]; then
  "$REPO_ROOT/tools/godot" --headless --import --path "$REPO_ROOT"
  touch "$CACHE_FILE"
fi

OUTPUT_FILE="$(mktemp)"
cleanup() {
  rm -f "$OUTPUT_FILE"
  local child_pids
  child_pids="$(jobs -p 2>/dev/null || true)"
  if [[ -n "$child_pids" ]]; then
    kill -TERM $child_pids 2>/dev/null || true
    sleep 0.1
    kill -KILL $child_pids 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

set +e
timeout --kill-after=5s "${TIMEOUT}s" xvfb-run -a -s "-screen 0 1280x720x24" "$REPO_ROOT/tools/godot" \
  --path "$REPO_ROOT" \
  --rendering-driver opengl3 \
  --resolution 1280x720 \
  "$SCENE" \
  -- \
  --screenshot="$ABS_OUT" \
  --frames="$FRAMES" \
  ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} > "$OUTPUT_FILE" 2>&1
EXIT_CODE="$?"
set -e

if [[ "$EXIT_CODE" -eq 124 || "$EXIT_CODE" -eq 137 ]]; then
  echo "Error: timed out" >&2
  exit 124
fi

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
  echo "Error: Screenshot file was not created at $ABS_OUT" >&2
  cat "$OUTPUT_FILE" >&2
  exit 1
fi

echo "$ABS_OUT"
exit 0
