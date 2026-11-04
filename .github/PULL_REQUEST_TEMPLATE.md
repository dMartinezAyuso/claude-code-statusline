## What changes and why
<!-- One or two sentences. Link the issue if there is one: Closes #123 -->

## Type of change
- [ ] Fix (patch)
- [ ] New compatible feature (minor)
- [ ] Breaking change (major)
- [ ] Security
- [ ] Documentation / CI

## Checklist
- [ ] `python3 -m unittest discover -s tests` and `bash tests/test_statusline.sh` pass locally
- [ ] I added or adjusted tests if I touch the server or the installer
- [ ] I added a line to `CHANGELOG.md` under `[Unreleased]` (with **[security]** if it applies)
- [ ] If I change what the bar shows: I updated the legend (`HELP` in `diffserver.py`) and the README
- [ ] I add no external dependencies
- [ ] There are no secrets, tokens or personal paths in the diff
- [ ] If I touch `diffserver.py`: requests without a token or with a foreign `Host` still get 403

## How you tested it
<!-- Operating system, terminal, Claude Code version -->
