---
name: github-pr-media
description: Attach runtime screenshots or other visual proof to a GitHub PR using repo-hosted artifacts and a PR comment.
---

# GitHub PR Media

Use this skill when a change needs visual/runtime proof on the PR.

## Goal

Capture a small number of screenshots or artifacts, store them in the repo, and post a PR comment that links to them.

## Steps

1. Capture media into `artifacts/pr_media/<ticket-or-branch>/`.
2. Prefer PNG screenshots for UI proof and TXT/LOG files for CLI/runtime proof.
3. Keep filenames stable and descriptive, for example:
   - `dashboard-home.png`
   - `deploy-studio.png`
   - `docs-home.png`
4. Commit the media files with the code changes so GitHub can serve them from the branch.
5. Determine the current PR number:
   ```bash
   gh pr view --json number,headRefName
   ```
6. Build raw GitHub URLs for each file using the current branch name:
   ```text
   https://raw.githubusercontent.com/<owner>/<repo>/<branch>/artifacts/pr_media/<path>
   ```
7. Post a concise PR comment with a short checklist and embedded images:
   ```markdown
   ## Runtime validation media
   - Dashboard home
   - Deploy Studio state

   ![Dashboard home](RAW_URL_1)
   ![Deploy Studio](RAW_URL_2)
   ```
8. If the change is non-visual, post links to the committed log or text artifact instead of images.

## Notes

- Prefer 1-3 artifacts, not large dumps.
- Do not use external image hosts.
- If the branch is rebased or renamed, regenerate the raw URLs before posting.
