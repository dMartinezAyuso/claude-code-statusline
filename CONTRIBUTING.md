# Contributing

## Workflow
1. Fork or create a branch: `git switch -c fix/whatever` (`feat/…`, `docs/…`, `ci/…`).
2. Change and **test locally** (see below).
3. Add a line to `CHANGELOG.md` under `[Unreleased]` (mark it **[security]** if it applies). If you change what the bar shows, also update the legend (`HELP` in `diffserver.py`, shown at `/help`) and the README.
4. Open a PR against `main`; the template guides you. CI must be green (lint, tests on Linux and macOS, CodeQL).
5. PRs are merged with *squash and merge*. The PR title becomes the commit message: make it clear.

Rules: no external dependencies (only the standard library and system utilities), messages and documentation in English, small and focused changes.

## Local tests
```bash
bash -n statusline.sh install.sh scripts/*.sh
shellcheck -S warning statusline.sh install.sh scripts/*.sh tests/test_statusline.sh   # pip install shellcheck-py
python3 -m unittest discover -s tests -v     # server: token, Host, escaping, limits…
bash tests/test_statusline.sh                # full bar with temporary state and port
./scripts/check-version.sh                   # VERSION consistent with CHANGELOG
```
If you touch the server, these behaviours **must not change**: no token → 403, wrong token → 403, foreign `Host` → 403 even with a valid token, file names escaped in the HTML.
Every fixed bug should come with a test that fails without the fix.

## Versions (SemVer)
- **Patch** `0.1.1`: fixes and internal improvements.
- **Minor** `0.2.0`: new compatible features.
- **Major** `1.0.0`: changes the installation, the environment variables or the state format.

`VERSION` is the source of truth; `scripts/check-version.sh` requires it to be SemVer and `CHANGELOG.md` to have its `## [X.Y.Z] - YYYY-MM-DD` entry.

## Publishing a version (maintainer)
```bash
# 1. On a branch: bump VERSION and rename [Unreleased] → [X.Y.Z] - date in the CHANGELOG
echo X.Y.Z > VERSION
./scripts/check-version.sh                 # must say OK
# 2. PR → green CI → merge to main
# 3. Tag from an up-to-date main
git switch main && git pull --ff-only
git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z
```
When the tag is pushed, the **Release** workflow checks that the tag matches `VERSION` and the CHANGELOG, runs the tests, builds the tarball with `SHA256SUMS` and publishes the release with the CHANGELOG notes. It is never created by hand.

If a release goes wrong: do not rewrite the tag. Fix it with a new patch version.

## Before pushing: secrets check
```bash
git diff --cached | grep -niE "gho_|ghp_|sk-|password|/Users/"
```
The real token lives in `~/.local/state/claude-code-statusline/`, outside the repo: it must never appear in a commit. GitHub has secret scanning and push protection enabled.
