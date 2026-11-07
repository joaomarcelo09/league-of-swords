#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ ! -x "$REPO_ROOT/tools/godot" ]]; then
  echo "Error: Godot wrapper script not found or not executable at $REPO_ROOT/tools/godot" >&2
  exit 1
fi

# Import first if needed (e.g. freshly cloned worktree, updated project configuration, or new/updated scripts)
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

GUT_ARGS=(--headless --path "$REPO_ROOT" -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json -gexit)

FILTER=""
if [[ $# -ge 1 ]]; then
  if [[ -n "$1" ]]; then
    FILTER="$1"
    GUT_ARGS+=("-gselect=$1")
  fi
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
# Detect parse/load failures in output and fail. Plain runtime SCRIPT ERRORs are handled by GUT assertions.
if grep -i -E "Parse Error|Failed to load script|Failed to compile" "$OUTPUT_FILE" > /dev/null; then
  echo "Error: GDScript parse error or script load failure detected during test run." >&2
  exit 1
fi

if [[ -n "$FILTER" ]]; then
  TESTS_COUNT=$(sed -nE 's/^[[:space:]]*Tests[[:space:]]+([0-9]+).*/\1/p' "$OUTPUT_FILE" | tail -n 1)
  if [[ -z "$TESTS_COUNT" || "$TESTS_COUNT" -eq 0 ]]; then
    echo "Error: No tests ran for filter '$FILTER'." >&2
    exit 1
  fi
fi

exit 0
