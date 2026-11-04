# Security policy

## Supported versions
Only the latest published version (latest tag / `main`). Security fixes ship as a **patch** version and are marked **[security]** in the [CHANGELOG](CHANGELOG.md).

## How to report a vulnerability
Use the **[GitHub private advisory](https://github.com/dMartinezAyuso/claude-code-statusline/security/advisories/new)** (Security → Report a vulnerability). Please do not open a public issue with the details until a fix exists.
This is a personal project with no guaranteed deadlines; I try to reply within a few days and coordinate disclosure with you.

## Threat model
It protects against **malicious web pages** trying to read your diffs through `127.0.0.1` (token + `Host` validation).
It does **not** protect against another user with access to your account or your machine: the token is in a file owned by your user and in the terminal URLs.

## Supply chain measures
- The only script the server ever sends is the diff page's folding script: it is allowed by a per-response random nonce in the `Content-Security-Policy`, contains no repository data and no `eval`, and the pages carry no inline event handlers.
- No external dependencies (only the Python standard library and system utilities).
- GitHub Actions pinned by SHA, updated by Dependabot.
- Workflows with minimal permissions (`contents: read`; only the release has `contents: write`).
- CodeQL weekly and on every PR; secret scanning and push protection enabled.
- Each release includes a `SHA256SUMS` of the tarball.
