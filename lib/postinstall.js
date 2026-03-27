#!/usr/bin/env node
'use strict';

/**
 * Runs automatically after: npm install -D wac-devflow
 *
 * - In a real TTY (developer machine): launches the setup wizard
 * - In CI / non-interactive: prints a one-line hint and exits
 */

const { execFileSync, execSync } = require('child_process');
const path = require('path');
const fs   = require('fs');
const os   = require('os');

// npm sets INIT_CWD to the directory where `npm install` was run
const PROJECT_ROOT = process.env.INIT_CWD || process.cwd();

const PKG_ROOT  = path.join(__dirname, '..');
const BASH_DIR  = path.join(PKG_ROOT, 'scripts', 'bash');
const BAT_DIR   = path.join(PKG_ROOT, 'scripts', 'bat');
const isWindows = os.platform() === 'win32';

// ── Skip in non-interactive / CI environments ─────────────────────────────────
const isCI          = !!(process.env.CI || process.env.CONTINUOUS_INTEGRATION);
const isInteractive = process.stdout.isTTY && process.stdin.isTTY;
const isSkipped     = process.env.SKIP_DEVFLOW_SETUP === '1';

if (!isInteractive || isCI || isSkipped) {
  console.log('\n  wac-devflow installed. Run "npx devflow setup" to configure.\n');
  process.exit(0);
}

// ── Already fully configured? ─────────────────────────────────────────────────
// Minimum required: at least one git provider token and project path
const provider = process.env.GIT_PROVIDER || 'gitlab';
const REQUIRED = provider === 'github'
  ? ['GITHUB_TOKEN', 'GITHUB_PROJECT_PATH']
  : ['GITLAB_TOKEN', 'GITLAB_PROJECT_PATH'];
const allSet   = REQUIRED.every(k => !!process.env[k]);

if (allSet) {
  console.log('\n  wac-devflow: already configured. Run "npx devflow check" to verify.\n');
  process.exit(0);
}

// ── Launch setup wizard ────────────────────────────────────────────────────────
console.log('\n  wac-devflow: launching setup wizard...\n');

try {
  if (isWindows) {
    runWindows();
  } else {
    runUnix();
  }
} catch (err) {
  // Setup can be cancelled — don't fail npm install
  process.exit(0);
}

function runUnix() {
  const script = path.join(BASH_DIR, 'setup-tokens.sh');
  fs.chmodSync(script, '755');
  execFileSync('bash', [script], {
    stdio: 'inherit',
    env: { ...process.env, PROJECT_ROOT },
  });
}

function runWindows() {
  const gitBash = findGitBash();
  if (gitBash) {
    const script = path.join(BASH_DIR, 'setup-tokens.sh');
    execFileSync(gitBash, [script], {
      stdio: 'inherit',
      env: { ...process.env, PROJECT_ROOT },
    });
  } else {
    const script = path.join(BAT_DIR, 'setup-tokens.bat');
    execFileSync('cmd.exe', ['/c', script], {
      stdio: 'inherit',
      env: { ...process.env, PROJECT_ROOT },
    });
  }
}

function findGitBash() {
  const candidates = [
    'C:\\Program Files\\Git\\bin\\bash.exe',
    'C:\\Program Files (x86)\\Git\\bin\\bash.exe',
    path.join(process.env.LOCALAPPDATA || '', 'Programs\\Git\\bin\\bash.exe'),
  ];
  const found = candidates.find(p => fs.existsSync(p));
  if (found) return found;
  try {
    return execSync('where bash.exe', { encoding: 'utf8', stdio: ['pipe','pipe','pipe'] })
      .trim().split('\n')[0].trim();
  } catch (_) { return null; }
}
