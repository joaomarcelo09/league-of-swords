#!/usr/bin/env bash
# Fetch pinned third-party art listed in data/art_manifest.json into assets/.
# The manifest is a JSON object {snake_case_id: {url, sha256, dest, author, license,
# source_page, [member, member_sha256, notes]}} (an object so the data registry,
# which loads every data/*.json, accepts it).
#
# - Downloads each URL once with curl into .art-cache/ and checks its sha256.
# - For zip rows, reads ONLY the named member with Python zipfile (never extracts
#   a whole archive, never runs anything from a download) and checks member_sha256.
# - Copies the verified file to its dest under assets/ (atomic rename).
# - Idempotent: a dest that already matches the expected hash is skipped.
# - Any failure (network, HTTP 403/429, hash mismatch, bad zip) exits non-zero,
#   names the URL and reason, and writes nothing into assets/ for that file.
#
# Fetched art is gitignored. Without it the game keeps using the procedural
# placeholders (tools/gen_placeholder_sprites.py).
#
# Env: FETCH_ART_MANIFEST=<path>  manifest to use (default: data/art_manifest.json)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${FETCH_ART_MANIFEST:-$ROOT/data/art_manifest.json}"
CACHE="$ROOT/.art-cache"
FALLBACK_MSG="The game keeps using the procedural placeholders (tools/gen_placeholder_sprites.py); no fetched art is required to run it."

if ! command -v curl >/dev/null 2>&1; then
	echo "fetch_art: ERROR: curl not found. $FALLBACK_MSG" >&2
	exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
	echo "fetch_art: ERROR: python3 not found. $FALLBACK_MSG" >&2
	exit 1
fi
if [[ ! -f "$MANIFEST" ]]; then
	echo "fetch_art: ERROR: manifest not found: $MANIFEST. $FALLBACK_MSG" >&2
	exit 1
fi

sha_of() {
	sha256sum "$1" | cut -d' ' -f1
}

# Validate the manifest and print one row per line, fields separated by 0x1f:
# url, sha256, dest, member, member_sha256
ROWS="$(python3 -I -c '
import json, re, sys
path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as f:
        rows = json.load(f)
except Exception as e:
    sys.exit("fetch_art: ERROR: cannot parse manifest %s: %s" % (path, e))
if not isinstance(rows, dict):
    sys.exit("fetch_art: ERROR: manifest must be a JSON object of {id: row}")
hexre = re.compile(r"^[0-9a-f]{64}$")
for i, r in rows.items():
    if not isinstance(r, dict):
        sys.exit("fetch_art: ERROR: manifest row %s must be an object" % i)
    for k in ("url", "sha256", "dest", "author", "license", "source_page"):
        if not isinstance(r.get(k), str) or not r[k].strip():
            sys.exit("fetch_art: ERROR: manifest row %s: missing field %r" % (i, k))
    if not r["url"].startswith("https://"):
        sys.exit("fetch_art: ERROR: manifest row %s: url must be https" % i)
    if not hexre.match(r["sha256"]):
        sys.exit("fetch_art: ERROR: manifest row %s: bad sha256" % i)
    dest = r["dest"]
    if not dest.startswith("assets/") or ".." in dest.split("/") or "\\" in dest:
        sys.exit("fetch_art: ERROR: manifest row %s: dest must be a relative path under assets/" % i)
    member = r.get("member", "")
    msha = r.get("member_sha256", "")
    if member:
        if member.startswith("/") or ".." in member.split("/") or member.startswith("__MACOSX/"):
            sys.exit("fetch_art: ERROR: manifest row %s: unsafe zip member %r" % (i, member))
        if not hexre.match(msha):
            sys.exit("fetch_art: ERROR: manifest row %s: member needs a 64-hex member_sha256" % i)
    fields = [r["url"], r["sha256"], dest, member, msha]
    if any(("\x1f" in x or "\n" in x) for x in fields):
        sys.exit("fetch_art: ERROR: manifest row %s: control characters in fields" % i)
    print("\x1f".join(fields))
' "$MANIFEST")" || {
	echo "fetch_art: $FALLBACK_MSG" >&2
	exit 1
}

mkdir -p "$CACHE"

ok=0
fetched=0
failures=()

fail() {
	# $1 url, $2 dest, $3 reason
	echo "fetch_art: FAIL $2 <- $1: $3" >&2
	failures+=("$1: $3")
}

# Download $1 into the cache (once per URL) and check sha256 $2.
# On success sets DL_PATH and returns 0; on failure sets DL_ERR and returns 1.
DL_PATH=""
DL_ERR=""
download() {
	local url="$1" want="$2"
	local name cached tmp err code got
	DL_PATH=""
	DL_ERR=""
	name="$(basename "${url%%\?*}")"
	cached="$CACHE/${want}-${name}"
	if [[ -f "$cached" ]] && [[ "$(sha_of "$cached")" == "$want" ]]; then
		DL_PATH="$cached"
		return 0
	fi
	tmp="$(mktemp "$CACHE/.dl.XXXXXX")"
	echo "fetch_art: downloading $url"
	code=0
	err="$(curl -fsSL --retry 2 --connect-timeout 20 --max-time 300 -o "$tmp" "$url" 2>&1)" || code=$?
	if ((code != 0)); then
		rm -f "$tmp"
		case "$err" in
			*" 403"*) DL_ERR="download failed: HTTP 403 forbidden (host refused the request or rate limit) [curl: ${err}]" ;;
			*" 429"*) DL_ERR="download failed: HTTP 429 rate limited [curl: ${err}]" ;;
			*) DL_ERR="download failed (curl exit ${code}; network down or HTTP error) [curl: ${err:-no message}]" ;;
		esac
		return 1
	fi
	got="$(sha_of "$tmp")"
	if [[ "$got" != "$want" ]]; then
		rm -f "$tmp"
		DL_ERR="sha256 mismatch for downloaded file: expected $want, got $got"
		return 1
	fi
	mv -f "$tmp" "$cached"
	fetched=$((fetched + 1))
	DL_PATH="$cached"
}

while IFS=$'\x1f' read -r url sha dest member msha; do
	[[ -z "$url" ]] && continue
	want="$sha"
	[[ -n "$member" ]] && want="$msha"
	target="$ROOT/$dest"

	if [[ -f "$target" ]] && [[ "$(sha_of "$target")" == "$want" ]]; then
		echo "fetch_art: up to date  $dest"
		ok=$((ok + 1))
		continue
	fi

	if ! download "$url" "$sha"; then
		fail "$url" "$dest" "$DL_ERR"
		continue
	fi
	src="$DL_PATH"

	staged="$(mktemp "$CACHE/.stage.XXXXXX")"
	if [[ -n "$member" ]]; then
		if ! err="$(python3 -I -c '
import sys, zipfile
zpath, member, out = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with zipfile.ZipFile(zpath) as z:
        info = z.getinfo(member)
        if info.file_size > 64 * 1024 * 1024:
            sys.exit("zip member too large")
        data = z.read(info)
except KeyError:
    sys.exit("zip member not found: %s" % member)
except zipfile.BadZipFile as e:
    sys.exit("bad zip: %s" % e)
with open(out, "wb") as f:
    f.write(data)
' "$src" "$member" "$staged" 2>&1)"; then
			rm -f "$staged"
			fail "$url" "$dest" "${err}"
			continue
		fi
	else
		cp "$src" "$staged"
	fi

	got="$(sha_of "$staged")"
	if [[ "$got" != "$want" ]]; then
		rm -f "$staged"
		fail "$url" "$dest" "sha256 mismatch for ${member:-file}: expected $want, got $got"
		continue
	fi

	mkdir -p "$(dirname "$target")"
	# Stage next to the target, then rename, so a partial file never lands in assets/.
	part="$(mktemp "$(dirname "$target")/.fetch.XXXXXX")"
	cp "$staged" "$part"
	rm -f "$staged"
	chmod 0644 "$part"
	mv -f "$part" "$target"
	echo "fetch_art: installed   $dest"
	ok=$((ok + 1))
done <<<"$ROWS"

echo "fetch_art: ${ok} file(s) ok, ${fetched} download(s), ${#failures[@]} failure(s)."
if ((${#failures[@]} > 0)); then
	echo "fetch_art: ERROR: some art could not be fetched:" >&2
	for f in "${failures[@]}"; do
		echo "  - $f" >&2
	done
	echo "fetch_art: $FALLBACK_MSG" >&2
	exit 1
fi
