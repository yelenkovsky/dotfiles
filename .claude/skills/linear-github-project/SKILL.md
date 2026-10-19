---
name: linear-github-project
description: >-
  Run a repo's project management across Linear and GitHub without Linear's
  GitHub Issues sync: one Linear project per repo, every issue created in both
  places and cross-linked, branches/commits/PRs that reference both, a GitHub
  Actions CI gate, and releases. Use when the user asks to add, start, close or
  cancel an issue for a repo, to open a PR for an issue, to cut a release, to
  set up CI, or to onboard another repo the same way dotfiles is managed.
---

# Linear + GitHub project management (no sync)

Linear plans the work; GitHub holds the code, the CI and a mirror of each issue.
The two are joined by plain links that I create, never by Linear's GitHub
Issues sync.

**Why no sync:** the Linear team `Data Engineer` (key `DE`) holds many unrelated
projects (courses, 10xDevs, dotfiles), and the sync works per team, not per
project. With it on, issues leaked into the wrong repo, deleting a GitHub issue
archived its Linear issue, and new GitHub issues came back into Linear as
duplicates. Never turn the sync on, and never suggest it as a fix.

## Project registry

| GitHub repo | Linear project | Default branch |
|---|---|---|
| `yelenkovsky/dotfiles` | Dotfiles & secure-install (`P-DE-28`) | `main` |
| `yelenkovsky/dotfiles-private` | Dotfiles (private) (`P-DE-29`) | `main` |

Add a row when a repo is onboarded. A repo with no row is not onboarded: run
**Onboard a repo** first, or ask which Linear project it belongs to.

## Issue lifecycle

### Create

1. Linear: `save_issue` with `team: DE`, `project` from the registry,
   `assignee: me`, a label, and a Markdown description (context, what done
   looks like).
2. GitHub: `gh issue create -R <repo> --title <same title> --label <label>
   --body <same description + "\n\nTracked in Linear: [DE-N](https://linear.app/xbloc/issue/DE-N)">`.
3. Linear: append `GitHub: <issue url>` to the description (`save_issue` with a
   `patch` append).
4. Check for an auto-imported copy: `list_issues` on team DE created in the last
   few minutes. If a copy exists, the sync is back on: delete the copy's GitHub
   attachment first (`delete_attachment`), then tell the user and point them to
   Linear → Settings → Integrations → GitHub.

Label mapping:

| Linear | GitHub |
|---|---|
| feature, foundation, improvement | enhancement |
| bug | bug |
| docs work | documentation |

### Work on it

- Branch: Linear's `gitBranchName` for the issue (e.g.
  `xbloc/de-192-publish-public-dotfiles-repo`), cut from the default branch.
- Move the Linear issue to In Progress.
- Commits follow the repo's own message style. The commit that finishes the
  issue carries trailers:
  ```
  Fixes #<github number>
  Linear: DE-<n>
  ```

### Pull request

- Open with `gh pr create`, title like the main commit, body = summary,
  how it was tested, `Closes #<n>`, `Linear: [DE-n](…)`.
- Merge only when CI is green and the user says so. Use the repo's merge style
  (dotfiles uses merge commits).
- `Closes #n` closes the GitHub issue on merge to the default branch. That is
  GitHub's own feature, not the Linear sync.

### Close

| Outcome | Linear state | GitHub |
|---|---|---|
| Done | Done | closed, reason completed (automatic via `Closes #n`, otherwise `gh issue close --reason completed`) |
| Dropped or removed | Canceled | `gh issue close --reason "not planned"` |
| Duplicate | Duplicate (`duplicateOf`) | `gh issue close --reason "not planned"` + comment naming the original |

After a merge, always set the Linear issue to Done myself and confirm the GitHub
issue is closed. Nothing does it automatically.

### Never

- Delete a GitHub or Linear issue. Close or cancel instead (deleting is
  permanent and is the user's call).
- Edit an issue on one side and assume the other changed.
- Push, merge, tag, or publish a release without the user's go-ahead.

## CI (GitHub Actions)

Every onboarded repo has `.github/workflows/ci.yml` that runs on `pull_request`
and on `push` to the default branch. It is the merge gate: no merge on red.

Keep it to checks the repo can already pass; fix existing failures in their own
PR before making a check required. Pin each action to an exact release tag.
Pick jobs by repo type:

| Repo type | Jobs |
|---|---|
| Shell / dotfiles | `shellcheck` on all `*.sh`, `bash -n` syntax check |
| Node / TypeScript | `npm ci`, lint, typecheck, test, build |
| Python | `uv sync`, `ruff check`, `pytest` |

Shell example:

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]
jobs:
  shell:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4.2.2
      - name: Syntax
        run: find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 -n1 bash -n
      - name: ShellCheck
        run: find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 shellcheck -S warning
```

After adding CI, suggest branch protection on the default branch (require the
CI job, require a PR). It changes repo settings, so the user decides and I only
run `gh api` for it on their yes.

## CD / releases

Only for repos that ship something (an app, a package, a site). Dotfiles has no
release step.

1. Release when the user asks, from a green default branch.
2. Version with SemVer tags `vX.Y.Z` (`fix` → patch, `feature` → minor,
   breaking → major).
3. `gh release create vX.Y.Z --generate-notes` (notes list the closed issues
   and merged PRs).
4. Post a Linear project update (`save_status_update`) with the version and
   the issues it shipped.
5. Deploy workflows run on tag push (`on: push: tags: ['v*']`), never on every
   commit to `main`. Secrets come from GitHub Actions secrets, never the repo.

## Onboard a repo

1. Confirm the GitHub repo and pick or create the Linear project (`save_project`
   with team DE, lead me, a summary, and the repo link).
2. Add the row to the registry above.
3. Make sure the labels in the mapping exist on GitHub (`gh label list`).
4. Add `.github/workflows/ci.yml` for the repo type, in its own branch and PR.
5. Add a short section to the repo's `CLAUDE.md`: its Linear project and that
   issues follow this skill.
6. To record past work (as was done for dotfiles), group commits by topic
   into issues, create them as Done in Linear and closed on GitHub, each
   listing its commit hashes.
