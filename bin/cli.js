#!/usr/bin/env node
'use strict';

const { execFileSync, execSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

const PKG_ROOT = path.join(__dirname, '..');
const BASH_DIR = path.join(PKG_ROOT, 'scripts', 'bash');
const BAT_DIR  = path.join(PKG_ROOT, 'scripts', 'bat');

const COMMANDS = {
  setup:      { bash: 'setup-tokens.sh',        bat: 'setup-tokens.bat'    },
  push:       { bash: 'code-push.sh',            bat: 'code-push.bat'       },
  check:      { bash: 'check-env.sh',            bat: 'check-env.bat'       },
  sonar:      { bash: 'sonar-fetch-issues.sh',   bat: null                  },
  'debug-mr': { bash: 'debug-mr-create.sh',      bat: null                  },
  'test-msg': { bash: 'test-commit-msg.sh',      bat: null                  },
  init:       null,
  help:       null,
};

const HELP = `
  wac-devflow — Automated GitLab pipeline with SonarQube AI fixes

  USAGE
    devflow [command]

  COMMANDS
    setup       First-time setup wizard (auto-detects from git remote)
    push        Run the full push pipeline (default)
    check       Verify environment is fully configured
    sonar       Fetch current SonarQube issues
    debug-mr    Debug GitLab MR creation
    test-msg    Preview AI-generated commit message
    init        Install the git pre-push hook in this project

  REQUIRED ENV VARS
    GITLAB_TOKEN          GitLab personal access token
    SONAR_TOKEN           SonarQube token
    GITLAB_HOST           GitLab instance URL   (e.g. https://gitlab.com)
    GITLAB_PROJECT_PATH   GitLab project path   (e.g. myorg/my-repo)
    SONAR_HOST            SonarQube URL         (e.g. https://sonarqube.example.com)
    SONAR_PROJECT_KEY     SonarQube project key (e.g. myorg_my-repo_abc123)

  OPTIONAL ENV VARS
    MAIN_BRANCH     Target branch for MRs  (default: develop)
    MAX_RETRIES     SonarQube fix attempts  (default: 3)
    SKIP_SONAR      Set to 1 to skip pre-push SonarQube check

  QUICK START
    npx devflow setup    ← run this first in any new project
    npx devflow push
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
  execFileSync('bash', [script], {
    stdio: 'inherit',
    env: { ...process.env, PROJECT_ROOT: process.env.PROJECT_ROOT || process.cwd() },
  });
}

// ── Windows ───────────────────────────────────────────────────────────────────

function runWindows(cmd) {
  const gitBash = findGitBash();
  if (gitBash) {
    const script = path.join(BASH_DIR, COMMANDS[cmd].bash);
    execFileSync(gitBash, [script], {
      stdio: 'inherit',
      env: { ...process.env, PROJECT_ROOT: process.env.PROJECT_ROOT || process.cwd() },
    });
    return;
  }

  if (COMMANDS[cmd].bat) {
    const script = path.join(BAT_DIR, COMMANDS[cmd].bat);
    execFileSync('cmd.exe', ['/c', script], { stdio: 'inherit', env: process.env });
    return;
  }

  console.error([
    'This command requires Git Bash on Windows.',
    'Install Git for Windows: https://git-scm.com/download/win',
  ].join('\n'));
  process.exit(1);
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
