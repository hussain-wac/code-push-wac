#!/usr/bin/env node
'use strict';

const { execFileSync, execSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

const PKG_ROOT = path.join(__dirname, '..');
const BASH_DIR = path.join(PKG_ROOT, 'scripts', 'bash');
const BAT_DIR  = path.join(PKG_ROOT, 'scripts', 'bat');
const PS_DIR   = path.join(PKG_ROOT, 'scripts', 'powershell');

const COMMANDS = {
  setup:           { bash: 'setup-tokens.sh',        bat: 'setup-tokens.bat', ps1: 'setup-tokens.ps1' },
  'project-setup': { bash: 'project-setup.sh',       bat: null, ps1: 'project-setup.ps1' },
  push:            { bash: 'code-push.sh',            bat: 'code-push.bat', ps1: 'code-push.ps1' },
  check:           { bash: 'check-env.sh',            bat: 'check-env.bat', ps1: 'check-env.ps1' },
  sonar:           { bash: 'sonar-fetch-issues.sh',   bat: null                  },
  'debug-mr':      { bash: 'debug-mr-create.sh',      bat: null                  },
  'test-msg':      { bash: 'test-commit-msg.sh',      bat: null                  },
  init:            null,
  help:            null,
};

const HELP = `
  devflow-cli — Automated GitLab pipeline with SonarQube AI fixes

  USAGE
    devflow [command]

  COMMANDS
    setup           Global setup wizard — configure tokens & credentials
    project-setup   Per-project setup — target branch, SonarQube, test runner
    push            Run the full push pipeline (default)
    check           Verify environment is fully configured
    sonar           Fetch current SonarQube issues
    debug-mr        Debug GitLab MR creation
    test-msg        Preview AI-generated commit message
    init            Install the git pre-push hook in this project

  REQUIRED ENV VARS
    GITLAB_TOKEN          GitLab personal access token
    GITHUB_TOKEN          GitHub personal access token
    SONAR_TOKEN           SonarQube token
    GITLAB_HOST           GitLab instance URL   (e.g. https://gitlab.com)
    GITLAB_PROJECT_PATH   GitLab project path   (e.g. myorg/my-repo)
    SONAR_HOST            SonarQube URL         (e.g. https://sonarqube.example.com)
    SONAR_PROJECT_KEY     SonarQube project key (e.g. myorg_my-repo_abc123)

  OPTIONAL ENV VARS
    MAIN_BRANCH     Target branch for MRs  (default: develop)
    MAX_RETRIES     SonarQube fix attempts  (default: 3)
    SKIP_SONAR      Set to 1 to skip pre-push SonarQube check

  PROJECT CONFIG (.devflow/devflow-project-setting.json)
    Run 'devflow project-setup' to create .devflow/devflow-project-setting.json with:
      mainBranch          Target branch for MRs/PRs
      sonar.enabled       Whether SonarQube is active for this project
      tests.runner        Detected test framework (jest, vitest, mocha, …)
      tests.command       Command to run tests
      tests.runBeforePush Run tests automatically before every push

  QUICK START
    npm install -g wac-devflow
    devflow setup
    devflow project-setup
    devflow push
`;

const cmd = process.argv[2] || 'push';

if (cmd === 'help' || cmd === '--help' || cmd === '-h') {
  console.log(HELP);
  process.exit(0);
}

if (cmd === 'init') {
  require('../lib/install-hook').run();
  process.exit(0);
}

if (cmd === 'setup') {
  require('../lib/setup-wizard').run(process.env.PROJECT_ROOT || process.cwd());
  return;
}

if (cmd === 'project-setup') {
  require('../lib/project-setup-wizard').run(process.env.PROJECT_ROOT || process.cwd());
  return;
}

if (!COMMANDS[cmd]) {
  console.error(`Unknown command: ${cmd}\n`);
  console.log(HELP);
  process.exit(1);
}

const isWindows = os.platform() === 'win32';
isWindows ? runWindows(cmd) : runUnix(cmd);

// ── Unix ──────────────────────────────────────────────────────────────────────

function runUnix(cmd) {
  const script = path.join(BASH_DIR, COMMANDS[cmd].bash);
  try { fs.chmodSync(script, '755'); } catch (_) {}
  try {
    execFileSync('bash', [script], {
      stdio: 'inherit',
      env: { ...process.env, PROJECT_ROOT: process.env.PROJECT_ROOT || process.cwd() },
    });
  } catch (err) {
    if (typeof err.status === 'number') process.exit(err.status);
    process.exit(1);
  }
}

// ── Windows ───────────────────────────────────────────────────────────────────

function runWindows(cmd) {
  const env = getWindowsRuntimeEnv();
  const runtimeEnv = { ...env, PROJECT_ROOT: env.PROJECT_ROOT || process.cwd() };

  if (COMMANDS[cmd].ps1) {
    const script = path.join(PS_DIR, COMMANDS[cmd].ps1);
    runOrExit('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script], runtimeEnv);
    return;
  }

  if (COMMANDS[cmd].bat) {
    const script = path.join(BAT_DIR, COMMANDS[cmd].bat);
    runOrExit('cmd.exe', ['/c', script], runtimeEnv);
    return;
  }

  const gitBash = findGitBash();
  if (gitBash) {
    const script = path.join(BASH_DIR, COMMANDS[cmd].bash);
    runOrExit(gitBash, [script], runtimeEnv);
    return;
  }

  console.error([
    'This command requires Git Bash on Windows.',
    'Install Git for Windows: https://git-scm.com/download/win',
  ].join('\n'));
  process.exit(1);
}

function runOrExit(command, args, env) {
  try {
    execFileSync(command, args, {
      stdio: 'inherit',
      env,
    });
  } catch (err) {
    if (typeof err.status === 'number') process.exit(err.status);
    throw err;
  }
}

function findGitBash() {
  const candidates = [
    'C:\\Program Files\\Git\\bin\\bash.exe',
    'C:\\Program Files (x86)\\Git\\bin\\bash.exe',
    path.join(process.env.LOCALAPPDATA || '', 'Programs\\Git\\bin\\bash.exe'),
    path.join(process.env.ProgramFiles  || '', 'Git\\bin\\bash.exe'),
  ];
  const found = candidates.find(p => fs.existsSync(p));
  if (found) return found;
  try {
    return execSync('where bash.exe', { encoding: 'utf8', stdio: ['pipe','pipe','pipe'] })
      .trim().split('\n')[0].trim();
  } catch (_) { return null; }
}

function getWindowsRuntimeEnv() {
  const env = { ...process.env };
  const keys = [
    'GIT_PROVIDER',
    'GITLAB_TOKEN',
    'GITHUB_TOKEN',
    'GITLAB_HOST',
    'GITHUB_HOST',
    'GITLAB_PROJECT_PATH',
    'GITHUB_PROJECT_PATH',
    'USE_SONAR',
    'SONAR_TOKEN',
    'SONAR_HOST',
    'SONAR_PROJECT_KEY',
    'DEVFLOW_DEFAULT_AI_CLI',
    'MAIN_BRANCH',
    'MAX_RETRIES',
    'SKIP_SONAR',
  ];

  for (const key of keys) {
    if (env[key]) continue;
    const value = readWindowsUserEnvVar(key) || readWindowsMachineEnvVar(key);
    if (value) env[key] = value;
  }

  return env;
}

function readWindowsUserEnvVar(name) {
  return readWindowsEnvVar(name, 'User');
}

function readWindowsMachineEnvVar(name) {
  return readWindowsEnvVar(name, 'Machine');
}

function readWindowsEnvVar(name, scope) {
  try {
    const ps = `[Environment]::GetEnvironmentVariable('${name}', '${scope}')`;
    const value = execSync(`powershell -NoProfile -Command "${ps}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
    }).trim();
    return value || '';
  } catch (_) {
    return '';
  }
}
