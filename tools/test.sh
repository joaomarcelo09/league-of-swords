#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ ! -x "$REPO_ROOT/tools/godot" ]]; then
  echo "Error: Godot wrapper script not found or not executable at $REPO_ROOT/tools/godot" >&2
  exit 1
fi

# Import first if needed (e.g. freshly cloned worktree or updated project configuration)
if [[ ! -f "$REPO_ROOT/.godot/global_script_class_cache.cfg" || ! -d "$REPO_ROOT/.godot/imported" || "$REPO_ROOT/project.godot" -nt "$REPO_ROOT/.godot/global_script_class_cache.cfg" ]]; then
  "$REPO_ROOT/tools/godot" --headless --import --path "$REPO_ROOT"
fi

GUT_ARGS=(--headless --path "$REPO_ROOT" -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json -gexit)

if [[ $# -ge 1 && -n "${1:-}" ]]; then
  GUT_ARGS+=("-gselect=$1")
  shift
  if [[ $# -gt 0 ]]; then
    GUT_ARGS+=("$@")
  fi
fi

OUTPUT_FILE="$(mktemp)"
cleanup() {
  rm -f "$OUTPUT_FILE"
}
trap cleanup EXIT

set +e
"$REPO_ROOT/tools/godot" "${GUT_ARGS[@]}" 2>&1 | tee "$OUTPUT_FILE"
EXIT_CODE="${PIPESTATUS[0]}"
set -e

if [[ "$EXIT_CODE" -ne 0 ]]; then
  exit "$EXIT_CODE"
fi

# GUT may treat GDScript parse errors in test scripts as warnings and exit 0.
# Detect parse errors / script errors in output and fail.
if grep -E "SCRIPT ERROR|Parse Error" "$OUTPUT_FILE" > /dev/null; then
  echo "Error: GDScript parse error or script error detected during test run." >&2
  exit 1
fi

exit 0
