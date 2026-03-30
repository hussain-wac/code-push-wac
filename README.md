# wac-devflow

Automated Git push pipeline with AI commit messages and optional SonarQube auto-fix. Works with GitLab and GitHub.

## Install

```bash
npm install -D wac-devflow
```

Setup wizards launch automatically on install. To run them manually:

```bash
npx devflow setup           # configure tokens (run once globally)
npx devflow project-setup   # configure project settings (run per project)
```

## Commands

```bash
devflow setup           # global wizard — tokens & credentials
devflow project-setup   # per-project wizard — branch, SonarQube, test runner
devflow push            # run the full pipeline (default)
devflow check           # verify configuration
devflow init            # install git pre-push hook
devflow sonar           # fetch SonarQube issues
devflow test-msg        # preview AI commit message
devflow debug-mr        # debug MR/PR creation
```

## Quick Start

```bash
# 1. Install
npm install -D wac-devflow

# 2. Configure tokens (once per machine)
npx devflow setup

# 3. Configure this project (once per repo)
npx devflow project-setup

# 4. Push
npx devflow push
```

## How it works

```
devflow push
  ├─ load .devflow.json (project config)
  ├─ run tests? (if tests.runBeforePush = true)
  ├─ changes? → stage → AI commit → push
  ├─ no changes? → find existing MR/PR
  ├─ create MR/PR if none exists
  ├─ wait for CI pipeline (10s timeout if no pipeline found)
  └─ SonarQube enabled?
       yes → fetch issues → AI auto-fix → commit → retry
       no  → report CI result and exit
```

## Project Config — `.devflow.json`

Run `devflow project-setup` to generate this file automatically. It is safe to commit to git (contains no secrets).

```json
{
  "mainBranch": "develop",
  "sonar": {
    "enabled": true
  },
  "tests": {
    "runner": "jest",
    "command": "npm test",
    "runBeforePush": false
  }
}
```

### What gets auto-detected

| Setting | How it's detected |
|---|---|
| `mainBranch` | `git symbolic-ref refs/remotes/origin/HEAD` |
| `sonar.enabled` | `sonar-project.properties`, `.sonarcloud.properties`, `sonar-scanner` in `package.json` scripts, or existing env vars |
| `tests.runner` | Config files (`jest.config.*`, `vitest.config.*`, `playwright.config.*`, `cypress.config.*`, `.mocharc.*`, `karma.conf.js`) then `package.json` dependencies |
| `tests.command` | `npm test` if a test script exists in `package.json`, otherwise runner-specific default |

### Supported test runners

`jest` · `vitest` · `mocha` · `jasmine` · `ava` · `karma` · `playwright` · `cypress`

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `GITLAB_TOKEN` | GitLab | Scopes: `api`, `write_repository` |
| `GITHUB_TOKEN` | GitHub | Scope: `repo` |
| `USE_SONAR` | No | `1` to enable, `0` to disable (overridden by `.devflow.json`) |
| `SONAR_TOKEN` | If Sonar | SonarQube user token |
| `SONAR_HOST` | If Sonar | SonarQube URL |
| `SONAR_PROJECT_KEY` | If Sonar | Project key from SonarQube |
| `MAIN_BRANCH` | No | Default: `develop` / `main` (overridden by `.devflow.json`) |
| `MAX_RETRIES` | No | Sonar fix retries (default: `3`) |
| `SKIP_SONAR` | No | Set to `1` to skip pre-push SonarQube check |

> **Project path and host are auto-detected from `git remote`** — no manual config needed.

### Priority order

CLI flag `--branch` > env var `MAIN_BRANCH` > `.devflow.json` > provider default

## Changing the target branch

**Interactively (recommended):**
```bash
npx devflow project-setup   # select from menu: main / master / develop / stage / other
```

**One-off override:**
```bash
devflow push --branch main
devflow push -b stage
```

**Permanently via env:**
```bash
export MAIN_BRANCH=main
```

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

**Pipeline not found** — run `devflow check` to verify token and host; script exits after 10 seconds if no pipeline appears

**Tests failing before push** — fix the tests or temporarily skip with:
```bash
RUN_TESTS_BEFORE_PUSH=0 devflow push
```

## License

MIT
