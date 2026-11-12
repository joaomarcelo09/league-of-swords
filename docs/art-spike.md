# Art Spike (M2 S1): LPC sources and licenses

Card: JGT-70. This file only records research. No art files are added to the repository by this card.

- **Date checked:** 2026-11-11 (UTC evening; the GitHub/OGA servers reported 2026-11-12 01:45 UTC).
- **Network:** worked. GitHub API (unauthenticated, 60 requests/hour; about 10 used), `raw.githubusercontent.com` and `opengameart.org` all answered. Not rate limited. `kenney.nl` returned **HTTP 403** for plain `curl` and only answered with a browser User-Agent.
- **Method:** each file was fetched with `curl -L` into a new empty `mktemp -d` folder outside the repo. Hashes come from `sha256sum` and sizes from `file`. For zips, the archive was opened in memory with `python3 -I` (`zipfile`) to list members and hash or read single files. Nothing was extracted into the repo, and no script from any pack was run. A few PNGs were viewed as images to check the frame layout.
- **Hash rule:** for GitHub sources the pin is the **commit SHA**, and the per-file sha256 is listed too. OGA has no commits, so the pin is the **sha256 of the downloaded file** (zip or PNG). `tools/fetch_art.sh` (S2) must check these hashes and fail on any mismatch.

---

## 1. Summary table

| Need | Chosen source | License we use (options offered) | Author(s) | Pinned commit / sha256 | Frame size |
| --- | --- | --- | --- | --- | --- |
| Player/NPC body (human) | Universal LPC Spritesheet Character Generator, `spritesheets/body/bodies/male/*.png` + `head/heads/human/male/*.png` | **CC-BY-SA 3.0** (options: OGA-BY 3.0, CC-BY-SA 3.0, GPL 3.0) | bluecarrot16, JaidynReiman, Benjamin K. Smith (BenCreating), Evert, Eliza Wyatt (ElizaWy), TheraHedwig, MuffinElZangano, Durrani, Johannes Sjölund (wulax), Stephen Challener (Redshrike) | commit `04140673ec02906f8233523639733c83690df750` | 64x64 |
| Skeleton enemy body | same repo, `body/bodies/skeleton/*.png` + `head/heads/skeleton/adult/*.png` | **CC-BY-SA 3.0** (options: OGA-BY 3.0, CC-BY-SA 3.0, GPL 3.0) | bluecarrot16, Napsio, JaidynReiman, Johannes Sjölund (wulax), Stephen Challener (Redshrike) | same commit | 64x64 |
| Orc enemy | same repo, `head/heads/orc/male/*.png` on the human male body (**no orc body exists**, only an orc head) | **CC-BY-SA 3.0** (options: OGA-BY 3.0, CC-BY-SA 3.0, GPL 3.0) | bluecarrot16, Matthew Krohn (makrohn), Stephen Challener (Redshrike), Zi Ye (+ body authors above) | same commit | 64x64 |
| Tiles (floors, walls, dungeon) | OGA "Liberated Pixel Cup (LPC) Base Assets", `lpc_base_assets.zip` | **CC-BY-SA 3.0** (options: CC-BY-SA 3.0, GPL 3.0; Sharm and Redshrike parts also OGA-BY 3.0) | Lanea "Sharm" Zimmerman, Stephen "Redshrike" Challener, Charles Sanchez (CharlesGabriel), Manuel Riecke (MrBeast), Daniel Armstrong (HughSpectrum) | zip sha256 `69efec8a26ef20b26cfd7a8de370e87d0e667136eba2d00392dde13d2ac52465` | 32x32 |
| Tiles (terrain/atlas, optional) | OGA "LPC Tile Atlas", `Atlas_0.zip` | CC-BY-SA 3.0 / GPL 3.0 on the page, **but see the open question in 3.2** | Compiled by adrix89; art by LPC base artists, Casper Nilsson, Daniel Eddeland, Johann Charlot, Skyler Robert Colladay | zip sha256 `4b8d0030c4e5c18029a0298caf11c74d38eb10273ac44e364ef620b81bcaa5fd` | 32x32 (1024x1024 atlas) |
| Monster 1: slime | OGA "[LPC] Monsters", `lpc-monsters.zip` → `lpc-monsters/slime.png` | **CC-BY-SA 3.0** (options: CC-BY-SA 3.0+, GPL 3.0+) | Charles Sanchez (CharlesGabriel), bluecarrot16 | zip sha256 `2c591d0e0c89dd579f84fb10ac9b24b97836941d6881abb5db85dc257892878f`; member sha256 `cb7ed15208ad569cf4c8d9b80dd639b835f2131c8b82cea4cb510c0a3fa45ab7` | 64x64 |
| Monster 2: wolf | OGA "[LPC] Wolf Animation", `wolfsheet1.png` | **CC-BY 3.0** (options: CC-BY 4.0, CC-BY 3.0, GPL 3.0, GPL 2.0, OGA-BY 3.0) | Stephen "Redshrike" Challener (artist), William.Thompsonj (contributor) | sha256 `35037f84c065844cb974d7d692875115b4c6ebf34e242921991351f370e1fa4f` | mixed: 32x64 (up/down), 64x32 (left/right) |
| Skill icons (Q/W/E/R) | game-icons.net (GitHub `game-icons/icons`), SVG | **CC-BY 3.0** | Lorc, Delapouite | commit `82d948812bfe3f269ef8f731dcdb07b08160edc4` | 512x512 SVG viewBox (vector) |

---

## 2. (a) Characters: Universal LPC Spritesheet Character Generator

- **Page:** https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator
- **Pinned commit:** `04140673ec02906f8233523639733c83690df750` (HEAD of `master` on 2026-11-11; message "docs: document weapon/tool oversize animation frame sizes").
- **Raw URL pattern:** `https://raw.githubusercontent.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator/04140673ec02906f8233523639733c83690df750/spritesheets/<path>.png`
- **License list:** `.../04140673ec02906f8233523639733c83690df750/CREDITS.csv`, sha256 `9bc3c6fc660946a8f36cefe8df8196884ac0309869cdcf3a8741f40577eb8c50` (3,987,290 bytes, 13,916 lines; columns `filename,notes,authors,licenses,urls`).
- The repo's own `LICENSE` file is GPL 3.0. It covers the generator code, not the art. Each art file's license is given in `CREDITS.csv`.

### Important format note (affects S2)

The generator no longer ships one combined "universal" sheet per layer. Each layer is **one PNG per animation** (`walk.png`, `slash.png`, `hurt.png`, `idle.png`, `spellcast.png`, `thrust.png`, `shoot.png`, plus `run`, `jump`, `sit`, `emote`, `climb`, `combat_idle`, `backslash`, `halfslash` for human bases). Our `data/sprites/layout_lpc.json` expects the classic combined layout: walk rows 8-11, slash rows 12-15, hurt row 20, on a 64x64 grid. Stacking the per-animation sheets in classic order (spellcast 4 rows, thrust 4, walk 4, slash 4, shoot 4, hurt 1) gives exactly that layout (832 px wide = 13 frames). There are two options for S2:
1. `fetch_art.sh` stacks the sheets into the classic layout. This is a small stdlib image step, and `layout_lpc.json` stays unchanged.
2. `layout_lpc.json` gets a per-animation `file` field. This is a data-only change.

Small mismatch to know about: `CREDITS.csv` names some files `combat.png`, `1h_backslash.png` and `1h_halfslash.png`, but the files on disk are `combat_idle.png`, `backslash.png` and `halfslash.png`. The licenses are the same, so only the credit lookup needs a name mapping.

### Files checked (all 64x64 frames; rows are up, left, down, right)

| File (under `spritesheets/`) | PNG size | Grid | sha256 |
| --- | --- | --- | --- |
| `body/bodies/male/walk.png` | 576x256 | 9 frames x 4 dirs | `1e0e8f0c11ba5f4f7b3d4439fc416802b4227da2fe146c13de3de254d9f87f77` |
| `body/bodies/male/slash.png` | 384x256 | 6 x 4 | `662e208502b0f060041cd3e8c65b6445117f174e9435b68e619b874e36b0069d` |
| `body/bodies/male/hurt.png` | 384x64 | 6 x 1 (single "fall down" row, used for hurt and death) | `417684c67b26467347953542069791af43a607008ddcb9f444a53aca3e10b820` |
| `body/bodies/male/idle.png` | 128x256 | 2 x 4 | `9c3d17def9bd0574e25ce3162a243f18654479e38c04164bc12607429b013fa2` |
| `head/heads/human/male/walk.png` | 576x256 | 9 x 4 | `7e863954dc8c3c748d0727415c39888106bdd3779beb2e3b18011a3a9ef3e53c` |
| `body/bodies/skeleton/walk.png` | 576x256 | 9 x 4 | `bcd603edb4b58741ba971b11b1f12a7fddf84ac0886005b36200cb19a6d37985` |
| `body/bodies/skeleton/slash.png` | 384x256 | 6 x 4 | `a78eb8e9077c5a7c50f9865fd4e2fcc005ac66b351c2af0b73a32d653f3e711f` |
| `body/bodies/skeleton/hurt.png` | 384x64 | 6 x 1 | `ba7952ad1463bc10d769acc810ef821d65fa9bad2c407b824b4385395972b64c` |
| `body/bodies/skeleton/idle.png` | 128x256 | 2 x 4 | `b0c7003813aabce6d675560faaa5b6b6d74d7119f135ff99415b53be01168a11` |
| `head/heads/skeleton/adult/walk.png` | 576x256 | 9 x 4 | `dc126515750aa4d17c36ac511f7d860968155ff35c55111fa94e1894e23b2f6c` |
| `head/heads/skeleton/adult/slash.png` | 384x256 | 6 x 4 | `517ae23655079164748f3d6a4360dbce28458671276b1bd111906f653d9299fc` |
| `head/heads/skeleton/adult/hurt.png` | 384x64 | 6 x 1 | `67e986b30cfc3fe8470ec74398fbe4c58520ed27ec7f1e738e97ba78d40b8167` |
| `head/heads/orc/male/walk.png` | 576x256 | 9 x 4 | `f674158c9ab2c6ef73fc7131120aa5e641d541003ba4d42b9133371d0a3ef0e6` |
| `head/heads/orc/male/slash.png` | 384x256 | 6 x 4 | `df673a91461b26e73bf0310d96e293e65e9b3a7de2552d60cc72a0ad457a13bf` |
| `head/heads/orc/male/hurt.png` | 384x64 | 6 x 1 | `941723567b639dc53b449ba46d024ef5796e0906b8d46bebb6f0f9b28519faa9` |
| `head/heads/orc/male/idle.png` | 128x256 | 2 x 4 | `806de604082adbc2c56e64482932cf1c6b5ecba27a15c2e55470c5d90704ea89` |

**Animations available:** idle yes, walk yes, slash yes, hurt/death yes (one 6-frame row; the last frame lies on the ground, so it works as death). Spellcast, thrust and shoot also exist. Skeleton bodies have only spellcast, thrust, walk, slash, shoot, hurt and idle (no run or jump). There is **no orc or zombie body for the orc**: the orc is an orc head drawn over a (green-tinted) human body. The body PNGs are paletted (`8-bit colormap`), and skin colour comes from the palette.

**License text quoted from `CREDITS.csv` (pinned commit):**

```
"body/bodies/male/walk.png","see details at https://opengameart.org/content/lpc-character-bases; 'Thick' Male Revised Run/Climb by JaidynReiman (based on ElizaWy's LPC Revised)" ,"bluecarrot16,JaidynReiman,Benjamin K. Smith (BenCreating),Evert,Eliza Wyatt (ElizaWy),TheraHedwig,MuffinElZangano,Durrani,Johannes Sjölund (wulax),Stephen Challener (Redshrike)" ,"OGA-BY 3.0,CC-BY-SA 3.0,GPL 3.0" ,"https://opengameart.org/content/liberated-pixel-cup-lpc-base-assets-sprites-map-tiles,https://opengameart.org/content/lpc-medieval-fantasy-character-sprites,https://opengameart.org/content/lpc-male-jumping-animation-by-durrani,https://opengameart.org/content/lpc-runcycle-and-diagonal-walkcycle,https://opengameart.org/content/lpc-revised-character-basics,https://opengameart.org/content/lpc-be-seated,https://opengameart.org/content/lpc-runcycle-for-male-muscular-and-pregnant-character-bases-with-modular-heads,https://opengameart.org/content/lpc-jump-expanded,https://opengameart.org/content/lpc-character-bases"
"body/bodies/skeleton/walk.png","" ,"bluecarrot16,Napsio,JaidynReiman,Johannes Sjölund (wulax),Stephen Challener (Redshrike)" ,"OGA-BY 3.0,CC-BY-SA 3.0,GPL 3.0" ,"https://opengameart.org/content/liberated-pixel-cup-lpc-base-assets-sprites-map-tiles,https://opengameart.org/content/lpc-medieval-fantasy-character-sprites,https://opengameart.org/content/lpc-skeleton,https://opengameart.org/content/lpc-character-bases"
"head/heads/skeleton/adult/walk.png","" ,"bluecarrot16,Napsio,JaidynReiman,Johannes Sjölund (wulax),Stephen Challener (Redshrike)" ,"OGA-BY 3.0,CC-BY-SA 3.0,GPL 3.0" ,"https://opengameart.org/content/liberated-pixel-cup-lpc-base-assets-sprites-map-tiles,https://opengameart.org/content/lpc-medieval-fantasy-character-sprites,https://opengameart.org/content/lpc-skeleton,https://opengameart.org/content/lpc-character-bases"
"head/heads/human/male/walk.png","original head by Redshrike, tweaks by BenCreating, modular version by bluecarrot16" ,"bluecarrot16,Benjamin K. Smith (BenCreating),Stephen Challener (Redshrike)" ,"OGA-BY 3.0,CC-BY-SA 3.0,GPL 3.0" ,"https://opengameart.org/content/liberated-pixel-cup-lpc-base-assets-sprites-map-tiles,https://opengameart.org/content/lpc-character-bases"
"head/heads/orc/male/walk.png","Sinbad the ogre design by Zi Ye, original 4-direction sprite by Redshrike, additional hurt/cast animations by makrohn, headless version by bluecarrot16" ,"bluecarrot16,Matthew Krohn (makrohn),Stephen Challener (Redshrike),Zi Ye" ,"OGA-BY 3.0,CC-BY-SA 3.0,GPL 3.0" ,"https://opengameart.org/content/four-characters-my-lpc-entries,https://opengameart.org/content/sinbad-the-ogre,https://opengameart.org/content/lpc-male-sheets,https://opengameart.org/content/lpc-character-bases"
```

**README (pinned commit), quoted:**

> Each piece of artwork distributed from this project (all images in the `spritesheets` subdirectory) is licensed under one or more of the following supported open license(s):

> [CC-BY-SA] This is the most restrictive license for any art supplied by this generator. You may use all the art in this repository if you follow all the terms of this license. Yes, this license allows you to use the art in this generator in commercial games.

> **If you generate a sprite using this tool, or use individual images taken directly from the `spritesheets` subdirectory from this repo, you must at least credit all the authors (except for CC0 licensed artwork).**

> Make sure this credits file is accessible from within your game or app and can be reasonably discovered by users (for instance, show the information on the "Credits" screen directly, or provide a visible link).

**What this means:** each file lists three licenses, and we may pick one of them. We pick **CC-BY-SA 3.0** because it is on the preferred list. OGA-BY 3.0 would also be allowed and drops share-alike, so it is flagged as **[OWNER decision]**. Credits must be visible in the game, for example on a Credits screen.

---

## 3. (b) Tiles

### 3.1 LPC Base Assets (recommended tile source)

- **Page:** https://opengameart.org/content/liberated-pixel-cup-lpc-base-assets-sprites-map-tiles
- **Raw file:** https://opengameart.org/sites/default/files/lpc_base_assets.zip, sha256 `69efec8a26ef20b26cfd7a8de370e87d0e667136eba2d00392dde13d2ac52465` (712.9 KB). Only this zip is offered. The PNGs inside are listed below and should be pinned by member hash too.
- **Author field on page:** "See CREDITS.TXT (Submitted by bart)".
- **License field on page (quoted):** "License(s): CC-BY-SA 3.0 GPL 3.0"
- **Attribution instructions (quoted):** "Images are copyright their respective authors, as listed in CREDITS.TXT. NOTE: The assets by Leana "Sharm" Zimmerman and Stephen "Redshrike" Challener are also available under the OGA-BY 3.0 License."
- **CREDITS.TXT inside the zip** names: Lanea Zimmerman (Sharm) for the base tileset (grass, dirt, water, dungeon, house, inside, mountains, …); Stephen Challener (Redshrike) for character templates; Charles Sanchez (CharlesGabriel) for monsters (bat, bee, slime, snake, …); Manuel Riecke (MrBeast) for hair and soldier; Daniel Armstrong (HughSpectrum) for castle walls and floors.
- **Tile size:** 32x32. This matches `data/balance.json` `"tile_px": 32`. Tiles use the LPC "terrain" layout (96x192 = 3x6 tiles per terrain: centre, edges and inner corners).

| Member | Size | sha256 |
| --- | --- | --- |
| `LPC Base Assets/tiles/grass.png` | 96x192 | `9fad54558dcb0aa91859869c603e76fe362ae320e0c4b1e873266566cb0d73a0` |
| `LPC Base Assets/tiles/dungeon.png` | 416x256 | `58e59996e37244f5dff6a98fd9da4e00fa55b4e4858291c06b918af9853eb3fe` |
| `LPC Base Assets/tiles/castlefloors.png` | 320x320 | `5244b8ee8ff88d5ce553a0cf332b8bdcbfe8394e16cfff16b93fa44357644415` |
| `LPC Base Assets/tiles/castlewalls.png` | 384x480 | `b832d6815ff9a860055196243195f6c12eaac54ec3545c7d6cb0c2593f8afb3d` |

Other tile members include water, dirt, lava, cement, stairs, house, inside, mountains, treetop/trunk, bridges, chests, barrel and signs.

### 3.2 LPC Tile Atlas (optional; license has an open question)

- **Page:** https://opengameart.org/content/lpc-tile-atlas
- **Raw files:** https://opengameart.org/sites/default/files/Atlas_0.zip, sha256 `4b8d0030c4e5c18029a0298caf11c74d38eb10273ac44e364ef620b81bcaa5fd`. It contains `terrain_atlas.png` (1024x1024, sha256 `139693a61792d7880e79d3f7dc8f868b3bde0eb525bdd936bde2e852ba9e24f9`), `base_out_atlas.png` (1024x1024, sha256 `81a37fefd8d5e1ce72e6b82a51f494aaf3324ec526c10bb8c2cbd30afa7d943e`) and `Attribution.txt`. `base_out_atlas.png` can also be downloaded directly: https://opengameart.org/sites/default/files/base_out_atlas.png (same hash). The page also links `build_atlas_0.png` (1024x1024, sha256 `dbdeaa1d1c19c10c2d1b756bab1c3bb31cb2d547e4cd5a6c78252f6b37f4046d`).
- **Author field (quoted):** "See Attribution.txt (Submitted by adrix89)".
- **License field (quoted):** "License(s): CC-BY-SA 3.0 GPL 3.0"
- **Attribution instructions (quoted):** "The zip contains a nifty attribution file so you can drop it and forget."
- **Tile size:** 32x32.
- **Open question (license unclear):** `Attribution.txt` lists per-author terms that do not all match the page. "Johann CHARLOT *GNU LGPL Version 3. *Later versions are permitted." (Shoot'em up graphic kit). "Skyler Robert Colladay" (FeralFantom's Entry) has **no license line at all**. "Casper Nilsson" and "Daniel Eddeland" are "*GNU GPL 3.0 or later" only, with no CC-BY-SA stated. The file also says: "Note the file is based on the LCP contest readme so don't expect the exact little pieces used like the base one." **Recommendation:** use Base Assets (3.1) for M2 tiles. Use the Atlas only if the owner accepts the GPL/LGPL parts and the unclear Colladay part, or if we only cut tiles from the base-asset regions.

---

## 4. (c) Small monsters

### 4.1 Slime: "[LPC] Monsters" (chosen)

- **Page:** https://opengameart.org/content/lpc-monsters
- **Raw file:** https://opengameart.org/sites/default/files/lpc-monsters.zip, sha256 `2c591d0e0c89dd579f84fb10ac9b24b97836941d6881abb5db85dc257892878f` (78.1 KB). Member `lpc-monsters/slime.png` is 512x256, sha256 `cb7ed15208ad569cf4c8d9b80dd639b835f2131c8b82cea4cb510c0a3fa45ab7`. The zip also has `__MACOSX/` junk entries, which S2 should skip.
- **Author (page):** bluecarrot16. The animations build on Charles Sanchez (CharlesGabriel) base monsters; the bat is by bagzie.
- **License field (quoted):** "License(s): CC-BY-SA 3.0 GPL 3.0"
- **Copyright/Attribution Notice (quoted):** "\"[LPC] Monsters\" by Charles Sanchez (CharlesGabriel), bagzie, and bluecarrot16. License: CC-BY-SA 3.0+ or GPL 3.0+. https://opengameart.org/content/lpc-monsters https://opengameart.org/content/liberated-pixel-cup-lpc-base-assets-sprites-map-tiles https://opengameart.org/content/bat-sprite"
- **Description excerpt (quoted):** "My contributions are licensed OGA-BY 3.0 (…). However, since the original work is CC-BY-SA 3.0, and this pack is derived from those original sprites, this submission is licensed CC-BY-SA 3.0 as well. The entire bat sprite is OGA-BY 3.0."
- **Frame size:** 64x64. 8 columns x 4 rows; the rows are the 4 directions (up, left, down, right). Rows 0 and 2 (up/down) use 6 frames, and rows 1 and 3 (left/right) use 8.
- **Animations:** idle/move (the first 3 frames per row, the classic hop) followed by **attack** (lunge/spit). There is a separate `slime-projectile.png` (64x16). **No hurt or death rows.** Hurt and death must be done in code (flash, fade or squash) or with the 32x32 base slime.
- **Fallback:** the original 32x32 slime from Base Assets, `LPC Base Assets/sprites/monsters/slime.png` (96x128 = 3 frames x 4 directions, move only), sha256 `49a1775bd8c0a89cf054a69207c2edd771cda9164d1d452fa3baaa57414eae1a`, by Charles Sanchez, CC-BY-SA 3.0 / GPL 3.0.

### 4.2 Wolf: "[LPC] Wolf Animation" (chosen)

- **Page:** https://opengameart.org/content/lpc-wolf-animation
- **Raw file:** https://opengameart.org/sites/default/files/wolfsheet1.png (85,794 bytes), sha256 `35037f84c065844cb974d7d692875115b4c6ebf34e242921991351f370e1fa4f`. `wolfsheet1_0.png` is byte-identical. Colour variants `wolfsheet2.png` … `wolfsheet6.png` were not hashed.
- **Author (page):** William.Thompsonj; collaborator Redshrike.
- **License field (quoted):** "License(s): CC-BY 4.0 CC-BY 3.0 GPL 3.0 GPL 2.0 OGA-BY 3.0"
- **Attribution instructions (quoted):** "Attribute Stephen \"Redshrike\" Challener as graphic artist and William.Thompsonj as contributor. If reasonable link back to this page or the OGA homepage."
- **Description (quoted):** "This is a commissioned work made by Redshrike. This is an LPC style wolf animation. It includes walking, running, biting, howling, and dying animations. There are a total of 6 colors to choose from, all the same setup."
- **Frame size:** **not a uniform grid.** The sheet is 640x384. The left half (x 0-319) holds up/down-facing frames at **32x64** (10 columns x 6 rows). The right half (x 320-639) holds left/right-facing frames at **64x32** (5 columns x 12 rows). S2 needs a small wolf layout JSON with explicit regions per animation.
- **Animations:** walk yes, run yes, bite (attack) yes, howl yes, **death yes** (lying-down frames are visible). There is no separate hurt; reuse the first death frame or flash.
- **License choice:** **CC-BY 3.0**, which is attribution only with no share-alike. This is the cleanest license in the whole set.

### 4.3 Bat (looked at, not chosen)

The bat in `lpc-monsters.zip` (`lpc-monsters/bat.png`, 448x256, 64x64, 7 frames x 4 directions; fly plus bite; no hurt/death; sha256 `009bd52b156b386e56b7e48d4512fd2df77e6cd2e1a376df4e5ca7ff28c9d7b0`) is by bagzie. The pack text says "The entire bat sprite is OGA-BY 3.0", while the page license is CC-BY-SA 3.0 / GPL 3.0. That makes it **OGA-BY 3.0 → [OWNER decision]** if we want it. The original page (https://opengameart.org/content/bat-sprite) was not checked. Base Assets also has a 32x32 bat by CharlesGabriel (CC-BY-SA 3.0 / GPL 3.0, sha256 `0da4eb935b49dbe41e9fb27b69da1451973f87242b3211944bb4ec95f8917ed8`, 3 frames x 4 directions, move only).

Pages that do **not** exist (HTTP 200 "Page not found"): `opengameart.org/content/lpc-slime`, `/lpc-bat`, `/bat-rat-and-slime`.

---

## 5. (d) Skill icons

### 5.1 game-icons.net (chosen)

- **Page:** https://game-icons.net, source repo https://github.com/game-icons/icons
- **Pinned commit:** `82d948812bfe3f269ef8f731dcdb07b08160edc4` (HEAD of `master`, committed 2026-04-23).
- **Raw URL pattern:** `https://raw.githubusercontent.com/game-icons/icons/82d948812bfe3f269ef8f731dcdb07b08160edc4/<author>/<name>.svg`
- **License text (quoted from `license.txt`):** "Icons provided under the Creative Commons 3.0 BY or CC0 if mentioned below." The list names "Lorc, http://lorcblog.blogspot.com" and "Delapouite, http://delapouite.com" without a CC0 mark, so both are **CC-BY 3.0**. The README "License" section says "CC-BY".
- **Format:** SVG, `viewBox="0 0 512 512"`, white glyph on a black square. Godot imports SVG natively, and the colour can be changed with a modulate shader. The files were checked: no `<script>`, `href` or `foreignObject`.
- **Animations:** n/a (static icons).

| Use (our skill) | File | sha256 |
| --- | --- | --- |
| Q Ember Lance | `lorc/fire-dash.svg` | `49e19abf0c84ac9459ddad7da919e94edecf12145b4fdf40db9f64e1b8b0675e` |
| W Crescent Sweep | `lorc/quick-slash.svg` | `d34c6112c7c315cad55f2d2318adcc20c7b324154a3bbcb604d1ba2cb66b31ce` |
| E Dash | `lorc/run.svg` | `0369d4afd39c8e363ced47bca93e9974adf77108891d38e30c68c71afcaeaac4` |
| R Mending Gale | `delapouite/healing-shield.svg` | `e6e93185ef859eb8cd71cdef2de7991995e977a0eab465a30f2a45ac9ed22a25` |
| spare | `lorc/crossed-slashes.svg` | `3d1f21988b66bfa1f0873cb737c5e8eba01ea548105236a814fd8b8fcae51fc7` |
| spare | `lorc/lightning-slashes.svg` | `fab637b539a8e3bec1578525ca639a1c46cd01dde59975897a3adf5e7caee22c` |
| spare | `lorc/tornado.svg` | `714db5052a1fbafb19a7e26e41fed4e87fe849d51b5cdd7d1878c83a840114cc` |
| spare | `lorc/whirlwind.svg` | `5ae969795fd335cd06c0de9cbeb2887895358ac072053142288ce1993ef11eef` |

Note: the GitHub contents API lists at most 1000 entries per folder. To find a name, use https://game-icons.net, then fetch the raw path.

### 5.2 Kenney (looked at, not chosen)

- **Page:** https://kenney.nl/assets/game-icons. The page says "Creative Commons CC0" (105 assets).
- Plain `curl` got **HTTP 403**; only a browser User-Agent got the page. No direct zip URL was found in the HTML because the download goes through the site's donation/download flow. So no file hash or pin is possible. The pack is UI glyphs (arrows, gears, buttons), not combat skill art. **Not usable from a script; not chosen.** It is still a CC0 option for generic UI glyphs if downloaded by hand.

---

## 6. Owner sign-off

The owner must approve each of these before S2 adds any art:

1. **CC-BY-SA 3.0 art in this repo.** The character sprites (generator), LPC Base Assets tiles and the [LPC] Monsters slime would be used under CC-BY-SA 3.0. Any edited or recoloured version of that art must also stay CC-BY-SA, and the art cannot become "all rights reserved". The game **code** keeps its own license (the brief says MIT; note that the repo has **no `LICENSE` file yet**). CC-BY-SA 3.0 also forbids adding technical (DRM) restrictions to the art. The generator README warns this may matter on stores that wrap games in DRM. Please approve: **[ ] use CC-BY-SA 3.0 art.**
2. **GPL 3.0 option.** Everywhere GPL is offered we pick a CC option instead (CC-BY-SA 3.0 or CC-BY 3.0), so no GPL-only file is chosen. Exception: the LPC Tile Atlas has GPL-only and LGPL-only parts plus one part with no stated license (section 3.2). Please approve: **[ ] skip the Tile Atlas for now** (recommended) or **[ ] accept it.**
3. **OGA-BY 3.0 [OWNER decision].** The generator sprites and the Sharm/Redshrike base tiles are *also* offered under OGA-BY 3.0, which is attribution only, with no share-alike and no DRM clause. Choosing OGA-BY for those files would make redistribution easier, but OGA-BY is not on our preferred list. The [LPC] Monsters bat is effectively OGA-BY-only (section 4.3). Please approve: **[ ] stay on CC-BY-SA 3.0** (default in this doc) or **[ ] use OGA-BY 3.0 where offered.**
4. **CC-BY 3.0 for the wolf and the icons.** Attribution only, no share-alike. Low risk; listed so the owner knows credits must name Redshrike, William.Thompsonj, Lorc and Delapouite.
5. **Credits must be visible in the game.** All licenses above need attribution, and the generator README asks for an in-game Credits screen or a visible link. A later card should add a Credits screen that shows `assets/CREDITS.md` (or a copy of it).
6. **Look check.** The generator's orc is an orc head on a human body. Approve this look, or drop the orc for M2.

---

## 7. No network

- `tools/fetch_art.sh` (card S2) downloads exactly the pinned URLs above and checks each file against the sha256 in this doc (later moved into a data file). If the network is down, a host refuses the request (as `kenney.nl` did with HTTP 403), GitHub rate limits it, or any hash does not match, the script **exits non-zero with a clear message** (which URL failed and why) and writes nothing into `assets/`.
- The game does **not** need the downloaded art. It keeps using the procedural placeholders from `tools/gen_placeholder_sprites.py`, which already follow the LPC row layout in `data/sprites/layout_lpc.json` (64x64 frames; walk rows 8-11, slash rows 12-15, hurt row 20). Real art can therefore replace the placeholders later by changing data only (sheet paths in JSON), with no code change.
- Downloads are untrusted data. S2 must fetch into a temp folder outside the repo, verify the hash, and only then copy the single files it needs. It must never extract a whole archive into the repo and never run scripts from a pack. The `__MACOSX/` entries in `lpc-monsters.zip` must be skipped.

---

## 8. Proposed `assets/CREDITS.md` rows

These rows go into the "Third-party asset policy" table in the same change that adds the files (S2). The target paths are proposals. The in-game names are original ("Ash Stalker", "Crescent Sweep", …); no Sword Art Online names are used.

| File / Directory | Author / Creator | License | Source URL | Notes |
| --- | --- | --- | --- | --- |
| `assets/characters/lpc/body/male/` | bluecarrot16, JaidynReiman, Benjamin K. Smith (BenCreating), Evert, Eliza Wyatt (ElizaWy), TheraHedwig, MuffinElZangano, Durrani, Johannes Sjölund (wulax), Stephen Challener (Redshrike) | CC-BY-SA 3.0 (chosen from OGA-BY 3.0 / CC-BY-SA 3.0 / GPL 3.0) | https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator (commit 04140673ec02906f8233523639733c83690df750); https://opengameart.org/content/lpc-character-bases | Universal LPC generator, `spritesheets/body/bodies/male/` |
| `assets/characters/lpc/head/human_male/` | bluecarrot16, Benjamin K. Smith (BenCreating), Stephen Challener (Redshrike) | CC-BY-SA 3.0 | same repo and commit; https://opengameart.org/content/lpc-character-bases | `spritesheets/head/heads/human/male/` |
| `assets/characters/lpc/body/skeleton/` and `head/skeleton/` | bluecarrot16, Napsio, JaidynReiman, Johannes Sjölund (wulax), Stephen Challener (Redshrike) | CC-BY-SA 3.0 | same repo and commit; https://opengameart.org/content/lpc-skeleton | skeleton enemy body and head |
| `assets/characters/lpc/head/orc_male/` | bluecarrot16, Matthew Krohn (makrohn), Stephen Challener (Redshrike), Zi Ye | CC-BY-SA 3.0 | same repo and commit; https://opengameart.org/content/sinbad-the-ogre; https://opengameart.org/content/four-characters-my-lpc-entries | orc head on human body |
| `assets/tiles/lpc_base/` | Lanea "Sharm" Zimmerman, Daniel Armstrong (HughSpectrum) (tiles); see CREDITS.TXT | CC-BY-SA 3.0 | https://opengameart.org/content/liberated-pixel-cup-lpc-base-assets-sprites-map-tiles | from `lpc_base_assets.zip` (sha256 69efec8a…2465) |
| `assets/monsters/slime.png` | Charles Sanchez (CharlesGabriel), bluecarrot16 | CC-BY-SA 3.0 | https://opengameart.org/content/lpc-monsters; https://opengameart.org/content/liberated-pixel-cup-lpc-base-assets-sprites-map-tiles | from `lpc-monsters.zip` (sha256 2c591d0e…8f) |
| `assets/monsters/wolf.png` | Stephen "Redshrike" Challener (artist), William.Thompsonj (contributor) | CC-BY 3.0 | https://opengameart.org/content/lpc-wolf-animation | `wolfsheet1.png` (sha256 35037f84…4f) |
| `assets/ui/skills/` (fire-dash, quick-slash, run) | Lorc | CC-BY 3.0 | https://game-icons.net ; https://github.com/game-icons/icons (commit 82d948812bfe3f269ef8f731dcdb07b08160edc4) | SVG skill icons |
| `assets/ui/skills/healing-shield.svg` | Delapouite | CC-BY 3.0 | https://game-icons.net ; same repo and commit | SVG skill icon |

The full `CREDITS.csv` rows for every generator file actually used should also be copied into `assets/CREDITS.md` (or shipped as `assets/characters/lpc/CREDITS.csv`), as the generator README recommends.

---

## 9. Not found / unclear (plain list)

- No orc **body** in the generator; there is only an orc head (section 2).
- LPC Tile Atlas: per-author terms in `Attribution.txt` (LGPL 3, GPL-only, one author with no license) do not match the page's CC-BY-SA 3.0 / GPL 3.0 (section 3.2).
- [LPC] Monsters slime and bat: no hurt or death animations.
- Wolf sheet: not a uniform grid (32x64 and 64x32 frames mixed).
- Bat in [LPC] Monsters is OGA-BY 3.0 per the author text → [OWNER decision]. The bagzie source page was not checked.
- Kenney: no scriptable download URL; HTTP 403 for plain `curl`; no hash possible.
- `CREDITS.csv` file names differ from on-disk names for `combat_idle`, `backslash` and `halfslash`.
