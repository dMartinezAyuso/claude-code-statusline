# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versioned with [SemVer](https://semver.org/).
Security changes are marked **[security]**.

## [Unreleased]
### Changed
- All code, messages, documentation and templates are now in English (the bar labels `caché`, `✔ limpio` and `ⓘ ayuda` became `cache`, `✔ clean` and `ⓘ help`; the help page moved from `/ayuda` to `/help`).

### Added
- Prompt cache expiry time (`↺HH:MM`, 5 min after the last activity) next to the cache indicator.
- Warning line when the cache expires with a context of 50k tokens or more: estimated cost of re-caching and a `/compact` hint. Price adjustable with `STATUSLINE_RECACHE_USD_PER_MTOK`.
- Spend rate in `$/h` next to the cost, after 5 min of session.

## [0.1.0] - 2026-11-02
### Added
- 3-line status bar (model, git, usage, 5h/7d limits, changed files).
- Local diff server (`diffserver.py`) with clickable links and a help page (shows the version).
- Automatic server restart when its code changes after an update.
- `install.sh` (installs/uninstalls in `settings.json` with a backup) and `statusline.sh --doctor` / `--version`.
- Automated tests (server and bar) and CI on Linux and macOS (Python 3.9–3.13).
- Automated release when a `vX.Y.Z` tag is pushed (notes from this file, tarball and SHA256SUMS).
- CodeQL, Dependabot, PR and issue templates and a security policy.
### Fixed
- `AA` and `DD` merge conflicts were drawn as added/deleted instead of as a conflict.
- The bar hung when creating the token if the launcher ran processes with `SIGPIPE` ignored (`tr -dc` on `/dev/urandom` spun forever); it is now generated with `od`.
- The server was slow to start in environments with slow DNS because of an unnecessary reverse lookup (`getfqdn`); it was removed.
### Security
- **[security]** Mandatory random token on every request (permissions 600, constant-time comparison).
- **[security]** `Host` header validation against DNS rebinding.
- **[security]** `CSP`, `nosniff` and `no-referrer` headers.
- **[security]** Timeout per `git` call (10 s) and a 512 KiB cap per diff to avoid hangs and memory use.
- **[security]** GitHub Actions pinned by SHA and minimal permissions in the workflows.
