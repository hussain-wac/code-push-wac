# devflow-cli

`wac-devflow` is a global CLI for GitLab and GitHub workflows. It provides a **smooth, interactive, and cross-platform experience** for managing your development pipeline.

## Features

- **Interactive Setup Wizards**: Robust Node.js-based wizards for both global and project-level configuration.
- **Cross-Platform Support**: Works perfectly on Linux, macOS, and Windows (PowerShell/CMD/Git Bash).
- **Arrow Key Selection**: Navigate options easily using arrow keys.
- **Visual Feedback**: Nice loading animations (spinners) and color-coded status messages.
- **Smart Auto-Detection**: Automatically detects Git providers, hosts, project paths, test runners, and SonarQube configurations.
- **Global Installation**: Install once, use in any repository.

## Install

```bash
npm install -g wac-devflow
```

## Quick Start

```bash
# 1. Configure this machine (tokens, hosts, AI CLI)
devflow setup

# 2. Configure the current repository (branch, tests, SonarQube)
devflow project-setup

# 3. Verify everything
devflow check

# 4. Push with the workflow
devflow push
```

## Commands

| Command | Description |
|---|---|
| `devflow setup` | **Global Setup** — Configure tokens, hosts, and AI preferences with an interactive wizard. |
| `devflow project-setup` | **Project Setup** — Configure target branch, test runner, and SonarQube for the current repo. |
| `devflow check` | **Environment Check** — Verify that all tokens and project settings are correctly configured. |
| `devflow push` | **Pipeline Push** — Run the full pipeline: test, commit, push, and create/reuse MR/PR. |
| `devflow sonar` | **SonarQube Issues** — Fetch and display current SonarQube issues for the project. |
| `devflow test-msg` | **AI Commit Preview** — Preview the AI-generated commit message for your changes. |
| `devflow init` | **Git Hook** — Install the `pre-push` hook to automate the workflow. |
| `devflow help` | **Help** — Show usage information and available commands. |

## What It Can Do

- Run a machine-level setup wizard for Git provider tokens, host values, SonarQube values, and preferred AI CLI.
- Run a per-project setup wizard and save project settings under `.devflow/devflow-project-setting.json`.
- Auto-detect the Git provider, host, and project path from the current repository remote.
- Detect the target branch, test runner, and SonarQube signals from the project.
- Run tests before push when configured.
- Stage changes, commit, push, and create or reuse a merge request or pull request.
- Check whether the current machine and repository are configured correctly.
- Work across multiple repositories without reinstalling the package in each repository.

## What It Cannot Do

- It does not replace GitLab or GitHub permissions. Tokens must still have the required scopes.
- It does not create GitLab, GitHub, or SonarQube projects for you.
- It does not guarantee pipeline success, merge approval, or automatic issue resolution.
- It does not avoid Git Bash on Windows for commands that only have Bash implementations.
- It does not store secrets in the project settings file. Secrets remain machine-level environment variables.
- It does not fit every custom monorepo or CI setup without some manual adjustments.

## Advantages

- One global install instead of adding the tool as a dependency in every repository.
- Project settings stay with the repository, while credentials stay on the machine.
- Auto-detection of git remote host and project path reduces setup mistakes.
- Consistent push flow across GitLab and GitHub repositories.
- Optional SonarQube support without forcing it into every project.
- Supports multiple AI CLIs instead of tying the workflow to one provider.

## Quick Start

```bash
# 1. Install globally
npm install -g wac-devflow

# 2. Configure this machine
devflow setup

# 3. Configure the current repository
devflow project-setup

# 4. Verify everything
devflow check

# 5. Push with the workflow
devflow push
```

## Project Settings

Project-level settings are stored here:

```text
.devflow/devflow-project-setting.json
```

This file is intended to live at the root of the repository and is safe to commit.

Example:

```json
{
  "mainBranch": "develop",
  "sonar": {
    "enabled": true,
    "projectKey": "myorg_myrepo_123"
  },
  "tests": {
    "runner": "jest",
    "command": "npm test",
    "runBeforePush": false
  }
}
```

## How It Works

```text
devflow push
  -> detect repository root
  -> detect git provider, host, and project path from git remote
  -> load .devflow/devflow-project-setting.json
  -> run tests if configured
  -> stage and commit changes
  -> push the branch
  -> create or reuse MR/PR
  -> optionally check SonarQube flow
```

## Auto-Detection

- Git provider: inferred from the repository remote.
- Git host: inferred from HTTPS or SSH remote URLs.
- Project path: inferred from the repository remote.
- Main branch: inferred from the origin HEAD when possible.
- Test runner: inferred from config files or `package.json`.
- SonarQube usage: inferred from project files, scripts, or existing environment variables.

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `GITLAB_TOKEN` | GitLab | Scopes: `api`, `write_repository` |
| `GITHUB_TOKEN` | GitHub | Scope: `repo` |
| `GITLAB_PROJECT_PATH` | Sometimes | Fallback if remote auto-detection is unavailable |
| `GITHUB_PROJECT_PATH` | Sometimes | Fallback if remote auto-detection is unavailable |
| `GITLAB_HOST` | No | Default: `https://gitlab.com` |
| `GITHUB_HOST` | No | Default: `https://github.com` |
| `USE_SONAR` | No | `1` to enable, `0` to disable, project settings can override |
| `SONAR_TOKEN` | If Sonar | SonarQube token |
| `SONAR_HOST` | If Sonar | SonarQube URL |
| `SONAR_PROJECT_KEY` | If Sonar | SonarQube project key |
| `MAIN_BRANCH` | No | Overrides detected or saved main branch |
| `MAX_RETRIES` | No | Sonar fix retries |
| `DEVFLOW_DEFAULT_AI_CLI` | No | `claude`, `codex`, or `gemini` |

## Requirements

- Node.js 16+
- Git
- curl
- Python 3
- Git Bash on Windows for Bash-only commands
- Optional AI CLI: Claude Code, Codex CLI, or Gemini CLI

## Windows Notes

- `devflow setup` saves machine-level values as Windows environment variables.
- `devflow project-setup` saves repository-level values under `.devflow/devflow-project-setting.json`.
- If auto-detection cannot determine the project path from the remote, set `GITLAB_PROJECT_PATH` or `GITHUB_PROJECT_PATH`.

## Troubleshooting

**Config still looks missing on Windows**

```powershell
devflow setup
devflow check
```

Make sure the repository has a valid `origin` remote and that the required token and project-path values are set.

**Wrong project detected**

Check:

```bash
git remote get-url origin
```

**Tests fail before push**

Either fix the tests or disable automatic test execution in `.devflow/devflow-project-setting.json`.

## License

MIT
