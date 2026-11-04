# claude-code-statusline

[![CI](https://github.com/dMartinezAyuso/claude-code-statusline/actions/workflows/ci.yml/badge.svg)](https://github.com/dMartinezAyuso/claude-code-statusline/actions/workflows/ci.yml)
[![CodeQL](https://github.com/dMartinezAyuso/claude-code-statusline/actions/workflows/codeql.yml/badge.svg)](https://github.com/dMartinezAyuso/claude-code-statusline/actions/workflows/codeql.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A custom 3-line status bar for [Claude Code](https://claude.com/claude-code):

1. Model and effort · project · git branch (↑ahead ↓behind) · git state · PR
2. Context · 5h/7d usage limits with countdown · cost and $/h rate · prompt cache with expiry time · tokens · duration · lines
3. Every file changed against `HEAD`. **Cmd+click** on one opens its diff in the browser.

If the prompt cache expires while the context is large, a warning line shows the estimated cost of re-caching it (the price can be adjusted with `STATUSLINE_RECACHE_USD_PER_MTOK`).

The `ⓘ help` link opens a legend explaining every symbol.

## Requirements

- macOS (it uses `stty -f` and `ps`; on Linux `term_width` would need adapting)
- `bash`, `jq`, `git`, `nc` (netcat) and `python3`
- A terminal with OSC 8 links (iTerm2, Ghostty, WezTerm, Kitty, VS Code…)

## Installation

```bash
git clone https://github.com/dMartinezAyuso/claude-code-statusline.git ~/.claude/statusline
cd ~/.claude/statusline
git checkout "$(git describe --tags --abbrev=0)"   # optional: latest stable version instead of main
./install.sh                                       # sets statusLine in ~/.claude/settings.json
```

`install.sh` checks the dependencies (`./statusline.sh --doctor`), makes a **backup** of `settings.json`, does not overwrite a foreign `statusLine` unless you pass `--force`, and is undone with `./install.sh --uninstall`. If you use a different configuration folder, set `CLAUDE_CONFIG_DIR`.

Manual installation: in `settings.json`

```json
{
  "statusLine": { "type": "command", "command": "~/.claude/statusline/statusline.sh", "refreshInterval": 10 }
}
```

Tested against the Claude Code statusline JSON of November 2026. Fields that do not exist are simply not drawn.

## Updating

```bash
cd ~/.claude/statusline
git pull --ff-only          # latest version
# or, to pin a specific stable version:
git fetch --tags && git checkout vX.Y.Z   # see the latest under Releases
```

Nothing needs restarting: on the next refresh (≤10 s) `statusline.sh` notices that `diffserver.py` has changed and restarts the server with the new code. The token is kept.

Before updating, read the [CHANGELOG](CHANGELOG.md): security changes are marked **[security]**. To hear about new versions use *Watch → Custom → Releases* on GitHub.

## Good practices

- **Pin a version** (`git checkout vX.Y.Z`) if you prefer stability; follow `main` if you want the latest.
- **Read the diff before updating** (`git diff HEAD..origin/main`): this script runs every few seconds with your permissions and starts a server. It is little code; review it as you would any third-party script.
- **Do not bind the port to an IP other than `127.0.0.1`** and do not expose the server through tunnels or proxies: it would serve your uncommitted code to whoever reaches it.
- **Do not share screenshots or copy links from the bar** (they carry the token in the URL). If you do, rotate the token (below).
- **Rotate the token** if you suspect it leaked: `rm ~/.local/state/claude-code-statusline/token`; a new one is generated on the next refresh and the server reads it on every request.
- **To stop the server**: `pkill -f diffserver.py`; it restarts by itself when the bar is used again. To disable it completely, remove the statusline from `settings.json`.
- **Customize in a fork or your own branch**, not on a cloned `main`, so `git pull` does not clash with your changes.

## What it runs on your machine

Worth knowing before installing:

- The first time there is a git repo, `statusline.sh` **starts in the background** `diffserver.py`, an HTTP server on `127.0.0.1:8765` (configurable with `STATUSLINE_PORT`).
- That server is **read-only**: it runs `git status` / `git diff` and renders HTML. It writes nothing to your repos.
- State and token are stored in `~/.local/state/claude-code-statusline/` (`XDG_STATE_HOME`).

## Security

The server exposes the uncommitted code of your repos, so it is protected:

- It only listens on `127.0.0.1`.
- A random 128-bit **secret token** (file with `600` permissions, folder `700`), required on every request and compared in constant time. A random website cannot read your diffs even if it guesses the port.
- **`Host` validation**: any request whose `Host` is not `127.0.0.1:<port>` or `localhost:<port>` is rejected (defence against DNS rebinding).
- `Content-Security-Policy`, `X-Content-Type-Options` and `Referrer-Policy` headers; content is escaped with `html.escape`.
- The `d=` parameter must be a git repo; otherwise 400.

The token is in the URL of the links, so anyone with access to your terminal session could see it: this is a local threat model meant to prevent access from the browser, not against another user with access to your account. To rotate it, delete `~/.local/state/claude-code-statusline/token` and restart the server (`pkill -f diffserver.py`).

Found a vulnerability? Use the [private advisory](https://github.com/dMartinezAyuso/claude-code-statusline/security/advisories/new) (see [SECURITY.md](SECURITY.md)), not a public issue.

## Contributing

PRs are welcome: read [CONTRIBUTING.md](CONTRIBUTING.md). CI runs shellcheck, the tests and CodeQL on every PR.

## License

MIT
