# claude-code-statusline

[![CI](https://github.com/dMartinezAyuso/claude-code-statusline/actions/workflows/ci.yml/badge.svg)](https://github.com/dMartinezAyuso/claude-code-statusline/actions/workflows/ci.yml)
[![CodeQL](https://github.com/dMartinezAyuso/claude-code-statusline/actions/workflows/codeql.yml/badge.svg)](https://github.com/dMartinezAyuso/claude-code-statusline/actions/workflows/codeql.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A custom 3-line status bar for [Claude Code](https://claude.com/claude-code):

1. Model and effort · project · git branch (↑ahead ↓behind) · git state · PR
2. Context · 5h/7d usage limits with countdown · cost (and $/h rate with an API account, see [Subscription or API](#subscription-or-api)) · prompt cache with expiry time · tokens · duration · lines
3. The files changed against `HEAD`: the first 10, then a `+N more` link when there are more (see [Changed files](#changed-files)). **Cmd+click** on a file opens its diff in the browser.

**Cmd+click on any part of the bar** (context, limits, cost, cache, tokens, the file counters…) opens the help page right at the explanation of that part, highlighted. The `ⓘ help` link opens the whole legend, with every symbol, color and setting. The parts are plain links, so terminals may underline them; set `STATUSLINE_LINKS=off` to keep only `ⓘ help`.

### Prompt cache indicator

Claude Code keeps your conversation in the prompt cache, which makes each turn cheaper, but the cache expires after a few minutes without activity. The bar shows:

- `cache N%`: how much of the last prompt was served from the cache.
- `↺HH:MM`: when the cache expires (green, then yellow in the last minute). Once expired it turns into a red `exp HH:MM`.
- A **warning line** between lines 2 and 3, only when the cache has expired and the context is large (50k tokens or more): the next prompt has to re-cache all of it, so the bar shows the estimated cost and suggests `/compact`.

The expiry time and the size of the warning come from Claude Code itself (`prompt_cache.expires_at` and `prompt_cache.recache_tokens_if_cold`), so they are **exact**, including when the 1-hour cache option is used. Older versions of Claude Code do not report them; then the bar estimates the expiry as 5 minutes (Anthropic's [default cache lifetime](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)) after the last write to the conversation transcript, using the context size, and a 1-hour cache will really expire later than shown. If Claude Code reports that no prompt caching is used, the indicator and the warning are not shown.

The re-cache cost uses the 5-minute cache-write price of the active model from the [official pricing table](https://platform.claude.com/docs/en/about-claude/pricing), per million tokens: Fable and Mythos $12.50, Opus 5.5 $5, other Opus $6.25, Sonnet 5 and 5.5 $2.50, other Sonnet $3.75, Haiku 5.5 $0.125 (prompts up to 100k tokens) or $0.625 (longer), other Haiku $1.25. An unknown model uses $6.25. Prices change, so set `STATUSLINE_RECACHE_USD_PER_MTOK` to override them.

`$N/h` next to the cost is the average spend rate of the session; it appears after 5 minutes so early numbers do not mislead. It is grey below `STATUSLINE_BURN_WARN` (default 15 USD/h), yellow from there and red from `STATUSLINE_BURN_HIGH` (default 30 USD/h). The defaults are arbitrary, not an official figure: set them to what is a lot for your budget. Fields that Claude Code does not report (for example the 5h/7d limits without a subscription) are not drawn.

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

`install.sh` also picks the [language](#languages) of the bar from your system locale (you can change it later). It checks the dependencies (`./statusline.sh --doctor`), makes a **backup** of `settings.json`, does not overwrite a foreign `statusLine` unless you pass `--force`, and is undone with `./install.sh --uninstall`. If you use a different configuration folder, set `CLAUDE_CONFIG_DIR`.

Manual installation: in `settings.json`

```json
{
  "statusLine": { "type": "command", "command": "~/.claude/statusline/statusline.sh", "refreshInterval": 10 }
}
```

Tested against the Claude Code statusline JSON of November 2026. Fields that do not exist are simply not drawn.

## Subscription or API

The cost that Claude Code reports is always in US dollars and means two different things:

- **API account** (pay per use): it is real money. The bar shows it in green/yellow/red by how much it is, shows the `$/h` rate, and the cache warning gives the cost of re-caching in dollars.
- **Subscription** (Pro or Max): you pay a flat fee, so the number is only the API-equivalent value. The bar shows it dimmed with a `≈` (`≈$12.40`), without colors and without the `$/h` rate, and the cache warning says it uses more of your **usage limit** instead of giving a price. The `5h` and `7d` limit bars are what matter here.

The mode is detected automatically: Claude Code reports the usage limits (`rate_limits`) only with a subscription. Claude Code does not report which plan you have, so Pro and Max look the same. Set `STATUSLINE_BILLING=api` or `STATUSLINE_BILLING=subscription` to force one. All amounts stay in US dollars.

## Changed files

With many changed files the third line would fill the screen, so by default it lists the first 10 and ends with a **`+N more`** link that opens the page with all of them. Choose how it looks with two variables:

| `STATUSLINE_FILES` | What line 3 shows |
|---|---|
| `compact` (default) | The first `STATUSLINE_MAX_FILES` files (10 by default) and `+N more`. With 10 files or fewer it looks exactly like `full`. |
| `full` | Every changed file, wrapped over as many lines as needed. |
| `count` | One line with the total and the number of files per status, for example `Δ 23 · M12 A3 D1 ?7`. All of it is a link to the page. |
| `off` | Nothing. |

The page that opens (**Cmd+click** on a file or on `+N more`) lets you fold what you do not need:

- Every file is a collapsible block whose title shows the status and the lines added and removed (`+12 −3`), so a folded file still tells you how big the change is.
- **Collapse all** and **Expand all** buttons, and a filter box that narrows both the list and the files.
- With more than 20 changed files the page starts folded; opening a file from the bar (or from the list at the top) unfolds just that one.
- What you folded is remembered per repository in your browser.

The page has a single small script, allowed by a one-time token, and it contains none of your repository data (see [Security](#security)).

## Languages

The bar's labels and the help page (`ⓘ help`) are available in **English, Spanish, French, Portuguese and German**.

- `./install.sh` detects your language the first time (from `LC_ALL`, `LC_MESSAGES` or `LANG`, or the macOS system language if none is set), saves it and tells you which one it chose. Anything it does not support falls back to English.
- Change it at any time with `./install.sh --lang es` (or `en`, `fr`, `pt`, `de`). Codes like `pt_BR` or `es_ES` are accepted. The bar picks it up on the next refresh and the help page follows it.
- `STATUSLINE_LANG=fr` in the environment overrides the saved language, for example to try another one.

Symbols, units (`5h`, `7d`, `h`, `m`) and setting names are the same in every language. The messages of `install.sh` and `--doctor` stay in English. The translations are a good-faith effort and some were not reviewed by native speakers: corrections are very welcome (see [CONTRIBUTING.md](CONTRIBUTING.md#translations)).

## Configuration

All settings are optional environment variables:

| Variable | Default | What it does |
|---|---|---|
| `STATUSLINE_PORT` | `8765` | Port of the local diff server (always bound to `127.0.0.1`). |
| `STATUSLINE_LINKS` | `on` | `on` or `off`: whether each part of the bar links to its row in the help page. |
| `STATUSLINE_BILLING` | `auto` | `auto`, `api` or `subscription`: how the cost is presented (see [Subscription or API](#subscription-or-api)). |
| `STATUSLINE_FILES` | `compact` | How the changed-file list is shown: `full`, `compact`, `count` or `off`. |
| `STATUSLINE_MAX_FILES` | `10` | How many files `compact` lists before `+N more`. |
| `STATUSLINE_LANG` | saved by `install.sh` | Language of the bar and the help page: `en`, `es`, `fr`, `pt` or `de`. Overrides the saved language. |
| `STATUSLINE_BURN_WARN` | `15` | Spend rate (USD/hour) from which `$N/h` turns yellow. |
| `STATUSLINE_BURN_HIGH` | `30` | Spend rate (USD/hour) from which `$N/h` turns red. |
| `STATUSLINE_RECACHE_USD_PER_MTOK` | by model | Price per million tokens used to estimate the re-cache cost in the warning line. |
| `CLAUDE_CONFIG_DIR` | `~/.claude` | Folder whose `settings.json` `install.sh` edits. |
| `XDG_STATE_HOME` | `~/.local/state` | Where the token and server state are kept (`claude-code-statusline/`). |

## Troubleshooting

- Run `./statusline.sh --doctor`: it checks the dependencies and prints the version and the state folder.
- A link answers `400` ("open the link from the bar"): the repository is not registered, which happens if you deleted the `repos` file or typed the address by hand. Click a link from the bar; the repository registers itself when the bar runs in it.
- A link answers `403`: the token changed or the link is stale. Click a fresh link from the bar.
- The server does not start: another program may be using port `8765`; set `STATUSLINE_PORT` to a free one.
- Nothing appears after installing: restart Claude Code, and check that `statusLine` in `settings.json` points to `statusline.sh`.
- The parts of the bar are underlined or I do not want them to be clickable: set `STATUSLINE_LINKS=off` (the `ⓘ help` link stays).
- I only see some of my changed files: that is the default `compact` mode (10 files and a `+N more` link). Set `STATUSLINE_FILES=full` to list them all, or `STATUSLINE_MAX_FILES=25` to list more.
- The bar or the help page is not in the language I expected: run `./install.sh --lang <code>` (`en`, `es`, `fr`, `pt` or `de`). The language is chosen once, so changing your system language later does not change it.

## Updating

```bash
cd ~/.claude/statusline
git pull --ff-only          # latest version
# or, to pin a specific stable version:
git fetch --tags && git checkout vX.Y.Z   # see the latest under Releases
```

Nothing needs restarting: on the next refresh (≤10 s) `statusline.sh` notices that `diffserver.py` has changed and restarts the server with the new code. The token and your language choice are kept.

Before updating, read the [CHANGELOG](CHANGELOG.md): security changes are marked **[security]**. To hear about new versions use *Watch → Custom → Releases* on GitHub.

## Good practices

- **Pin a version** (`git checkout vX.Y.Z`) if you prefer stability; follow `main` if you want the latest.
- **Read the diff before updating** (`git diff HEAD..origin/main`): this script runs every few seconds with your permissions and starts a server. It is little code; review it as you would any third-party script.
- **Do not bind the port to an IP other than `127.0.0.1`** and do not expose the server through tunnels or proxies: it would serve your uncommitted code to whoever reaches it.
- **Do not share screenshots or copy links from the bar** (they carry the token in the URL). If you do, rotate the token (below). Some terminals (VS Code, WezTerm, Kitty…) show a link's address when you hover over it: do not hover over the bar while sharing your screen, or set `STATUSLINE_LINKS=off` and keep only the `ⓘ help` link.
- **Rotate the token** if you suspect it leaked: `rm ~/.local/state/claude-code-statusline/token`; a new one is generated on the next refresh and the server reads it on every request.
- **To stop the server**: `pkill -f diffserver.py`; it restarts by itself when the bar is used again. To disable it completely, remove the statusline from `settings.json`.
- **Customize in a fork or your own branch**, not on a cloned `main`, so `git pull` does not clash with your changes.

## What it runs on your machine

Worth knowing before installing:

- The first time there is a git repo, `statusline.sh` **starts in the background** `diffserver.py`, an HTTP server on `127.0.0.1:8765` (configurable with `STATUSLINE_PORT`).
- That server is **read-only**: it runs `git status` / `git diff` and renders HTML. It writes nothing to your repos.
- State is stored in `~/.local/state/claude-code-statusline/` (`XDG_STATE_HOME`): the token, the language, the list of repositories the bar has run in, and the server's pid.

## Security

The server exposes the uncommitted code of your repos, so it is protected:

- It only listens on `127.0.0.1`.
- A random 128-bit **secret token** (file with `600` permissions, folder `700`), required on every request and compared in constant time. A random website cannot read your diffs even if it guesses the port.
- **`Host` validation**: any request whose `Host` is not `127.0.0.1:<port>` or `localhost:<port>` is rejected (defence against DNS rebinding).
- `Content-Security-Policy`, `X-Content-Type-Options` and `Referrer-Policy` headers; content is escaped with `html.escape`. The help page has no script. The diff page has one script, allowed only by a random nonce generated for each response (`script-src 'nonce-…'`), and it holds no repository data: it only folds, unfolds and filters the blocks the server already rendered.
- **Only repositories you use the bar in are served.** `statusline.sh` registers the top level of each repository it runs in (file `repos` in the state folder, permissions `600`) and the server refuses any other `d=` with 400. So even if a link leaks, it cannot be used to read the changes of other repositories on your disk. Delete the `repos` file to forget them; they register again the next time the bar runs in them.

The token is in the URL of the links, so anyone with access to your terminal session could see it: this is a local threat model meant to prevent access from the browser, not against another user with access to your account. To rotate it, delete `~/.local/state/claude-code-statusline/token` and restart the server (`pkill -f diffserver.py`).

Found a vulnerability? Use the [private advisory](https://github.com/dMartinezAyuso/claude-code-statusline/security/advisories/new) (see [SECURITY.md](SECURITY.md)), not a public issue.

## Contributing

PRs are welcome: read [CONTRIBUTING.md](CONTRIBUTING.md). CI runs shellcheck, the tests and CodeQL on every PR.

## License

MIT
