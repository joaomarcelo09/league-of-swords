# Developer Notes

Run all commands from the repository root.

## After pulling

After pulling, run `tools/godot --headless --import` if new `class_name` scripts arrived, otherwise tests/scenes fail with unknown class errors.

```sh
tools/godot --headless --import
```

## Fetching third-party art: `tools/fetch_art.sh`

Downloads the pinned third-party art listed in `data/art_manifest.json` into `assets/`.
The art is optional: without it the game keeps using the procedural placeholders
(`tools/gen_placeholder_sprites.py`).

```sh
tools/fetch_art.sh
```

- Needs `curl` and `python3` on `PATH`, plus network access.
- Each manifest row gives a `url`, `sha256`, and `dest` (a path under `assets/`), plus
  `author`, `license`, and `source_page`. Zip rows also give `member` and `member_sha256`:
  only that one file is read from the archive.
- Downloads are cached once per URL in `.art-cache/` and checked against `sha256`.
  The verified file is then copied to its `dest` with an atomic rename.
- Idempotent: a `dest` that already matches its expected hash is reported as `up to date`
  and skipped, so re-running is cheap.
- Ends with a summary line: `fetch_art: N file(s) ok, N download(s), N failure(s).`
- Exit code: `0` when every file is ok; non-zero on any failure (missing `curl`/`python3`,
  missing or invalid manifest, network or HTTP 403/429 error, hash mismatch, bad zip).
  Each failure names the URL and reason, and nothing is written into `assets/` for that file.
- Use another manifest with the `FETCH_ART_MANIFEST` environment variable
  (default: `data/art_manifest.json`):

  ```sh
  FETCH_ART_MANIFEST=data/art_manifest.json tools/fetch_art.sh
  ```

Fetched art and `.art-cache/` are gitignored and never committed. Every asset listed in the
manifest must also be credited in `assets/CREDITS.md`.
