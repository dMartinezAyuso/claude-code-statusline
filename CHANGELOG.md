# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versioned with [SemVer](https://semver.org/).
Security changes are marked **[security]**.

## [Unreleased]
### Changed
- The in-bar help page (`/help`) is now complete: vim mode, `exp HH:MM`, the warning line in its own section, settings and troubleshooting tips.
- README documents the prompt cache indicator, the configuration variables, troubleshooting and platform support.
- The re-cache cost estimate now uses the 5-minute cache-write prices of the official pricing table for each model (Fable/Mythos, Opus 5.5, Sonnet 5.x, Haiku 5.5 with its 100k-token tier, and the older families) instead of rough defaults.
- The `$N/h` colour thresholds are configurable with `STATUSLINE_BURN_WARN` and `STATUSLINE_BURN_HIGH` (defaults 15 and 30 USD/h).
- Contribution checklist asks to keep the legend and the README in sync with the bar.

## [0.2.0] - 2026-11-04
### Added
- Prompt cache expiry time (`↺HH:MM`, 5 min after the last activity) next to the cache indicator.
- Warning line when the cache expires with a context of 50k tokens or more: estimated cost of re-caching and a `/compact` hint. Price adjustable with `STATUSLINE_RECACHE_USD_PER_MTOK`.
- Spend rate in `$/h` next to the cost, after 5 min of session.
### Changed
- All code, messages, documentation and templates are now in English: the bar labels `caché`, `✔ limpio` and `ⓘ ayuda` became `cache`, `✔ clean` and `ⓘ help`, and the help page moved from `/ayuda` to `/help`.
- CI job names are now in English (`Lint and version`, `Tests (...)`).

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
