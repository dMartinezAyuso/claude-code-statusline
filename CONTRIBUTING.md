# Contributing

## Workflow
1. Fork or create a branch: `git switch -c fix/whatever` (`feat/…`, `docs/…`, `ci/…`).
2. Change and **test locally** (see below).
3. Add a line to `CHANGELOG.md` under `[Unreleased]` (mark it **[security]** if it applies). If you change what the bar shows, also update the legend (the `sections` of `lang/en.json`, shown at `/help`, and the same rows in every other language file) and the README. A new part of the bar is wrapped with `hl <row id> <text>` in `statusline.sh` so that Cmd+click opens its row.
4. Open a PR against `main`; the template guides you. CI must be green (lint, tests on Linux and macOS, CodeQL).
5. PRs are merged with *squash and merge*. The PR title becomes the commit message: make it clear.

Rules: no external dependencies (only the standard library and system utilities), messages and documentation in English, small and focused changes.

## Local tests
```bash
bash -n statusline.sh install.sh scripts/*.sh tests/*.sh
shellcheck -S warning statusline.sh install.sh scripts/*.sh tests/test_statusline.sh tests/test_install.sh   # pip install shellcheck-py
python3 -m unittest discover -s tests -v     # server: token, Host, escaping, limits…
bash tests/test_statusline.sh                # full bar with temporary state and port
bash tests/test_install.sh                   # installer: language detection, idempotent install, uninstall
./scripts/check-version.sh                   # VERSION consistent with CHANGELOG
```
If you touch the server, these behaviours **must not change**: no token → 403 and wrong token → 403 for everything except the fixed `/help` page, foreign `Host` → 403 even with a valid token (also for `/help`), an unregistered repository id → 400, file names escaped in the HTML.
Every fixed bug should come with a test that fails without the fix.

## Translations
All texts the user sees in the bar and in the help page live in `lang/<code>.json` (English is the reference). To add a language:
1. Copy `lang/en.json` to `lang/<two-letter-code>.json` and translate the values. Keep the keys, the order and the number of rows of every section (a row is `[symbol, text, id]`: the `id` is how the bar links to the row, so keep it exactly as in English), and keep the placeholders (`{tokens}`, `{cost}`, `{repo}`, `{count}`, `{kib}`) and the setting names (`STATUSLINE_*`) exactly as they are.
2. Keep the row symbols that mirror the bar (for example the `cache N%` row must use the same word as the `cache` label).
3. Run `python3 -m unittest tests.test_lang`: it checks that your file has the same shape as the English one. Add the code to `EXPECTED` in that test and to the list in the README.
4. A missing key falls back to English, but the test requires them all.

The messages of `install.sh` and `--doctor`, the documentation and the code stay in English.

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
