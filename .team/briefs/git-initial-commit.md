# Brief: initial commit on main (git-coder)

User approved (chat): apply 3 small fixes, track .team/plans and .team/briefs, make the initial commit on `main`. No push (no remote), no branches, no worktrees.

## Edits (do these first, then commit)
1. `.gitignore`: change line `export/` to `/export/`. Keep every other line.
2. `README.md`: the Setup section (last lines) mentions `tools/` and task IDs T2-T4. Replace those lines with a neutral sentence: "Setup instructions are coming soon." Change nothing else.
3. `.gitattributes`: add `* text=auto eol=lf` as the FIRST line. Keep the LFS lines.
4. `.git/info/exclude`: it holds a single line `.team/`. Remove that line (keep the comment header). Then make sure these stay ignored via `.gitignore` (already there): `.team/worktrees/`, `.team/runs/`. Also add `.team/agents.json` to `.gitignore` (local agent config, not for the repo).

## Commit
- Stage ONLY: `.gitignore`, `.gitattributes`, `README.md`, `.team/plans/`, `.team/briefs/`. Verify with `git status --short` that nothing else is staged (no runs, no worktrees, no agents.json).
- Check `git lfs install --local` is already in place (`git lfs env` ok); do not reinstall.
- Commit message: "Initial commit: repo setup, Git LFS rules, team plan and briefs", body one line, then the trailer:
  Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
- Do not push, branch, merge or amend.

## Report
`git log --oneline`, `git show --stat HEAD`, `git status --short` (must be clean), and `git check-ignore -v .team/runs .team/agents.json`.
