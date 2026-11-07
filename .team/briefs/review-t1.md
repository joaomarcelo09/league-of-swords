# Review: T1 git repo files + LFS (JGT-2)

Coder result: .team/runs/20261107-0103-jgt-2-t1-git-repo-lfs-gitignore/worker-results/coder-6216f88e.md
The repo has no commit yet; the 3 changes are untracked files in the main worktree (use `git status --short`, not `git diff`).
Files to open: `.gitignore`, `.gitattributes`, `README.md`.

Scope was: git repo files for "League of Swords" (Godot 4, GDScript, Linux): `.gitignore` (.godot/, .tools/, .screenshots/, export/, *.tmp, .team/worktrees/, .team/runs/),
`.gitattributes` (LFS for *.png *.wav *.ogg *.mp3 *.aseprite), a 10-15 line README, `git lfs install --local`. No commit, no SAO names/logos.

Check: patterns correct and complete for a Godot 4 project (is `*.import` or `.import/` handling right? Godot 4 keeps `.godot/` only; `*.import` files must stay tracked), the LFS lines are valid, README has no false claims, no secrets, nothing outside scope.
Critical/high only for real problems; the rest "other".

Do not re-read: the plan (.team/plans/jgt1-milestone1.md).
