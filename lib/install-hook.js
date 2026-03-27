'use strict';

const fs   = require('fs');
const path = require('path');
const os   = require('os');

const HOOK_SRC = path.join(__dirname, '..', 'scripts', 'bash', 'pre-push');

function run() {
  const gitDir = findGitDir(process.cwd());
  if (!gitDir) {
    console.error('✗ Not inside a git repository. Run this from your project root.');
    process.exit(1);
  }

  const hooksDir = path.join(gitDir, 'hooks');
  if (!fs.existsSync(hooksDir)) fs.mkdirSync(hooksDir, { recursive: true });

  const dest = path.join(hooksDir, 'pre-push');

  // Warn if a hook already exists
  if (fs.existsSync(dest)) {
    const existing = fs.readFileSync(dest, 'utf8');
    if (!existing.includes('SonarQube')) {
      console.warn('⚠  A pre-push hook already exists at ' + dest);
      console.warn('   Overwriting — back up your existing hook if needed.');
    }
  }

  fs.copyFileSync(HOOK_SRC, dest);
  if (os.platform() !== 'win32') fs.chmodSync(dest, '755');

  console.log('✓ Pre-push hook installed at: ' + dest);
  console.log('');
  console.log('The hook will check SonarQube for BLOCKER/CRITICAL issues before every push.');
  console.log('Skip it anytime with:  SKIP_SONAR=1 git push');
}

function findGitDir(dir) {
  const candidate = path.join(dir, '.git');
  if (fs.existsSync(candidate)) return candidate;
  const parent = path.dirname(dir);
  if (parent === dir) return null;
  return findGitDir(parent);
}

module.exports = { run };
