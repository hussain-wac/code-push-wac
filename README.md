# wac-devflow

Automated Git push pipeline with AI commit messages and optional SonarQube auto-fix. Works with GitLab and GitHub.

## Install

```bash
npm install -D wac-devflow
```

Setup wizard launches automatically. If not:

```bash
npx devflow setup
```

## Commands

```bash
devflow setup      # configure tokens (auto-detects git remote)
devflow push       # run the full pipeline
devflow check      # verify configuration
devflow init       # install git pre-push hook
devflow sonar      # fetch SonarQube issues
devflow test-msg   # preview AI commit message
devflow debug-mr   # debug MR/PR creation
```

## How it works

```
devflow push
  ├─ changes? → stage → AI commit → push
  ├─ no changes? → find existing MR/PR
  ├─ create MR/PR if none exists
  ├─ wait for CI pipeline
  └─ SonarQube enabled?
       yes → fetch issues → AI auto-fix → commit → retry
       no  → report CI result and exit
```

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `GITLAB_TOKEN` | GitLab | Scopes: `api`, `write_repository` |
| `GITHUB_TOKEN` | GitHub | Scope: `repo` |
| `USE_SONAR` | No | `1` to enable, `0` to disable |
| `SONAR_TOKEN` | If Sonar | SonarQube user token |
| `SONAR_HOST` | If Sonar | SonarQube URL |
| `SONAR_PROJECT_KEY` | If Sonar | Project key from SonarQube |
| `MAIN_BRANCH` | No | Default: `develop` / `main` |
| `MAX_RETRIES` | No | Sonar fix retries (default: `3`) |

> **Project path and host are auto-detected from `git remote`** — no per-project config needed.

## Requirements

- Node.js ≥ 16, Git, curl, Python 3
- [Claude Code](https://claude.ai/claude-code) or Codex CLI _(optional, for AI features)_

## Troubleshooting

**Peer dependency conflict**
```bash
echo "legacy-peer-deps=true" >> .npmrc
npm install -D wac-devflow
```

**Wrong project detected** — always auto-detected from `git remote get-url origin`

**Pipeline not found** — run `devflow check` to verify token and host

## License

MIT
