# T1 · Git repo files + LFS (task JGT-2)

Project: "League of Swords", an original 2D RPG in Godot 4 (GDScript), Linux. The folder is empty except `.team/`.
`git init -b main` was already run by the Coordinator. git-lfs 3.7.1 is installed.

## Do
Create only these files in the repo root (main worktree; the owner agreed; there is no code yet):
- `.gitignore`: `.godot/`, `.tools/`, `.screenshots/`, `export/`, `*.tmp`, `.team/worktrees/`, `.team/runs/`.
- `.gitattributes`: LFS for `*.png *.wav *.ogg *.mp3 *.aseprite` (`filter=lfs diff=lfs merge=lfs -text`).
- `README.md`: 10-15 lines: name, one-line pitch, "Godot 4 + GDScript, Linux", note that setup commands arrive in tools/ (T2-T4).
- Run `git lfs install --local`.

## Must not
- No `git add`, no commit, no branch: the git-coder commits after the owner's OK.
- No SAO names/logos in any text. Do not touch `.team/`.

## Acceptance
- `git check-attr filter assets/x.png` prints `filter: lfs`.
- `git lfs track` lists the 5 patterns.
- `git status --short` shows exactly the 3 new files (plus `.team/` untracked).

Do not re-read: the plan (`.team/plans/jgt1-milestone1.md`); it is summarized above.
