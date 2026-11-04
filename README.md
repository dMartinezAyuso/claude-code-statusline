# claude-code-statusline

[![CI](https://github.com/dMartinezAyuso/claude-code-statusline/actions/workflows/ci.yml/badge.svg)](https://github.com/dMartinezAyuso/claude-code-statusline/actions/workflows/ci.yml)
[![CodeQL](https://github.com/dMartinezAyuso/claude-code-statusline/actions/workflows/codeql.yml/badge.svg)](https://github.com/dMartinezAyuso/claude-code-statusline/actions/workflows/codeql.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A custom 3-line status bar for [Claude Code](https://claude.com/claude-code):

1. Model and effort · project · git branch (↑ahead ↓behind) · git state · PR
2. Context · 5h/7d usage limits with countdown · cost and $/h rate · prompt cache with expiry time · tokens · duration · lines
3. Every file changed against `HEAD`. **Cmd+click** on one opens its diff in the browser.

The `ⓘ help` link opens a legend explaining every symbol, color and setting.

### Prompt cache indicator

Claude Code keeps your conversation in the prompt cache, which makes each turn cheaper, but the cache expires after a few minutes without activity. The bar shows:

- `cache N%`: how much of the last prompt was served from the cache.
- `↺HH:MM`: when the cache expires (green, then yellow in the last minute). Once expired it turns into a red `exp HH:MM`.
- A **warning line** between lines 2 and 3, only when the cache has expired and the context is large (50k tokens or more): the next prompt has to re-cache all of it, so the bar shows the estimated cost and suggests `/compact`.

The expiry time is an estimate: Anthropic's [default cache lifetime is 5 minutes](https://platform.claude.com/docs/en/build-with-claude/prompt-caching), renewed every time the cache is used, and the bar counts it from the last write to the conversation transcript. If you use the 1-hour cache option the real expiry is later than shown.

The re-cache cost uses the 5-minute cache-write price of the active model from the [official pricing table](https://platform.claude.com/docs/en/about-claude/pricing), per million tokens: Fable and Mythos $12.50, Opus 5.5 $5, other Opus $6.25, Sonnet 5 and 5.5 $2.50, other Sonnet $3.75, Haiku 5.5 $0.125 (prompts up to 100k tokens) or $0.625 (longer), other Haiku $1.25. An unknown model uses $6.25. Prices change, so set `STATUSLINE_RECACHE_USD_PER_MTOK` to override them.

`$N/h` next to the cost is the average spend rate of the session; it appears after 5 minutes so early numbers do not mislead. Fields that Claude Code does not report (for example the 5h/7d limits without a subscription) are not drawn.

## Requirements

- macOS or Linux. It is developed on macOS and the CI also runs the tests on Linux. To size the file list it reads `$COLUMNS`, then `/dev/tty`, then the terminal of a parent process (this last step uses `stty -f`, macOS only); if none works it wraps at 110 columns
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

## Configuration

All settings are optional environment variables:

| Variable | Default | What it does |
|---|---|---|
| `STATUSLINE_PORT` | `8765` | Port of the local diff server (always bound to `127.0.0.1`). |
| `STATUSLINE_RECACHE_USD_PER_MTOK` | by model | Price per million tokens used to estimate the re-cache cost in the warning line. |
| `CLAUDE_CONFIG_DIR` | `~/.claude` | Folder whose `settings.json` `install.sh` edits. |
| `XDG_STATE_HOME` | `~/.local/state` | Where the token and server state are kept (`claude-code-statusline/`). |

## Troubleshooting

- Run `./statusline.sh --doctor`: it checks the dependencies and prints the version and the state folder.
- A link answers `403`: the token changed or the link is stale. Click a fresh link from the bar.
- The server does not start: another program may be using port `8765`; set `STATUSLINE_PORT` to a free one.
- Nothing appears after installing: restart Claude Code, and check that `statusLine` in `settings.json` points to `statusline.sh`.

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
