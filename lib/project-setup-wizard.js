'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { 
  colorize, askValue, askYesNo, selectMenu, printBanner, printStep 
} = require('./wizard');

async function run(projectRoot) {
  printBanner('Project Setup');
  console.log(`  Saves project config to ${colorize('cyan', '.devflow/devflow-project-setting.json')} — safe to commit.`);
  console.log(`  ${colorize('dim', 'For tokens & credentials, run: devflow setup')}`);
  console.log('');

  const configDir = path.join(projectRoot, '.devflow');
  const configFile = path.join(configDir, 'devflow-project-setting.json');
  const legacyFile = path.join(projectRoot, '.devflow.json');

  let existingSettings = {};
  if (fs.existsSync(configFile)) {
    existingSettings = JSON.parse(fs.readFileSync(configFile, 'utf8'));
    console.log(`  ${colorize('green', '✓')} Existing project settings found: .devflow/devflow-project-setting.json`);
  } else if (fs.existsSync(legacyFile)) {
    existingSettings = JSON.parse(fs.readFileSync(legacyFile, 'utf8'));
    console.log(`  ${colorize('green', '✓')} Existing project settings found: .devflow.json`);
  }

  if (Object.keys(existingSettings).length > 0) {
    if (existingSettings.mainBranch) console.log(`    mainBranch          = ${colorize('cyan', existingSettings.mainBranch)}`);
    if (existingSettings.sonar) {
      console.log(`    sonar.enabled       = ${colorize('cyan', existingSettings.sonar.enabled)}`);
      console.log(`    sonar.projectKey    = ${colorize('cyan', existingSettings.sonar.projectKey)}`);
    }
    if (existingSettings.tests) {
      console.log(`    tests.runner        = ${colorize('cyan', existingSettings.tests.runner)}`);
      console.log(`    tests.command       = ${colorize('cyan', existingSettings.tests.command)}`);
      console.log(`    tests.runBeforePush = ${colorize('cyan', existingSettings.tests.runBeforePush)}`);
    }
    console.log('');
  }

  if (!(await askYesNo('Start project setup?', true))) {
    console.log('  Setup cancelled.');
    process.exit(0);
  }

  // ── Step 1: Target Branch ──────────────────────────────────────────────────
  printStep('Step 1 — Target Branch');

  let detectedMain = 'develop';
  try {
    const head = execSync('git symbolic-ref refs/remotes/origin/HEAD', { encoding: 'utf8' }).trim();
    detectedMain = head.split('/').pop();
  } catch (_) {}

  let finalMainBranch = existingSettings.mainBranch || detectedMain;
  if (existingSettings.mainBranch) {
    console.log(`  Current: ${colorize('cyan', existingSettings.mainBranch)}`);
    if (await askYesNo('Change target branch?', false)) {
      const branches = ['main', 'master', 'develop', 'stage', 'Other (enter manually)'];
      const selection = await selectMenu('Select the target branch', branches, branches.indexOf(finalMainBranch));
      if (selection === 'Other (enter manually)') {
        finalMainBranch = await askValue('Enter branch name');
      } else {
        finalMainBranch = selection;
      }
    }
  } else {
    const branches = ['main', 'master', 'develop', 'stage', 'Other (enter manually)'];
    const selection = await selectMenu('Select the target branch', branches, branches.indexOf(detectedMain) === -1 ? 2 : branches.indexOf(detectedMain));
    if (selection === 'Other (enter manually)') {
      finalMainBranch = await askValue('Enter branch name', detectedMain);
    } else {
      finalMainBranch = selection;
    }
  }
  console.log(`  ${colorize('green', '✓')} Target branch: ${colorize('cyan', finalMainBranch)}`);

  // ── Step 2: SonarQube ──────────────────────────────────────────────────────
  printStep('Step 2 — SonarQube');

  let sonarEnabled = existingSettings.sonar ? existingSettings.sonar.enabled : false;
  let sonarProjectKey = existingSettings.sonar ? existingSettings.sonar.projectKey : '';

  const hasSonarProps = fs.existsSync(path.join(projectRoot, 'sonar-project.properties')) || fs.existsSync(path.join(projectRoot, '.sonarcloud.properties'));
  if (hasSonarProps) {
    console.log(`  ${colorize('green', '✓')} Detected SonarQube configuration files.`);
    sonarEnabled = await askYesNo('Enable SonarQube for this project?', true);
  } else {
    console.log(`  ${colorize('yellow', '⚠')} No SonarQube config detected.`);
    sonarEnabled = await askYesNo('Enable SonarQube anyway?', false);
  }

  if (sonarEnabled) {
    let suggestedKey = '';
    try {
      const remoteUrl = execSync('git remote get-url origin', { encoding: 'utf8' }).trim();
      const match = remoteUrl.match(/[:/]([^/:]+)\/([^/:]+)(\.git)?$/);
      if (match) {
        suggestedKey = `${match[1]}_${match[2]}`.replace(/-/g, '_').toLowerCase();
      }
    } catch (_) {}

    if (sonarProjectKey) {
      console.log(`  Current key: ${colorize('cyan', sonarProjectKey)}`);
      if (await askYesNo('Change project key?', false)) {
        sonarProjectKey = await askValue('SonarQube project key', sonarProjectKey);
      }
    } else {
      sonarProjectKey = await askValue('SonarQube project key', suggestedKey);
    }
  }

  // ── Step 3: Test Runner ────────────────────────────────────────────────────
  printStep('Step 3 — Test Runner');

  let finalRunner = existingSettings.tests ? existingSettings.tests.runner : '';
  let finalCommand = existingSettings.tests ? existingSettings.tests.command : '';
  let runBeforePush = existingSettings.tests ? existingSettings.tests.runBeforePush : false;

  const pkgPath = path.join(projectRoot, 'package.json');
  let pkg = {};
  if (fs.existsSync(pkgPath)) pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));

  if (!finalRunner) {
    if (fs.existsSync(path.join(projectRoot, 'vitest.config.ts')) || fs.existsSync(path.join(projectRoot, 'vitest.config.js'))) {
      finalRunner = 'vitest';
      finalCommand = 'npx vitest run';
    } else if (fs.existsSync(path.join(projectRoot, 'jest.config.js')) || fs.existsSync(path.join(projectRoot, 'jest.config.ts'))) {
      finalRunner = 'jest';
      finalCommand = 'npx jest';
    }
  }

  if (finalRunner) {
    console.log(`  ${colorize('green', '✓')} Detected runner: ${colorize('cyan', finalRunner)}`);
    if (!(await askYesNo('Use detected runner?', true))) {
      finalRunner = '';
    }
  }

  if (!finalRunner) {
    const runners = ['jest', 'vitest', 'mocha', 'jasmine', 'ava', 'karma', 'playwright', 'cypress', 'none'];
    finalRunner = await selectMenu('Select the test runner', runners);
    if (finalRunner === 'none') {
      finalRunner = '';
      finalCommand = '';
    } else {
      finalCommand = await askValue('Test command', finalCommand || 'npm test');
    }
  }

  if (finalRunner) {
    runBeforePush = await askYesNo('Run tests automatically before every push?', runBeforePush);
  }

  // ── Step 4: Saving ─────────────────────────────────────────────────────────
  printStep('Step 4 — Saving project settings');

  if (!fs.existsSync(configDir)) fs.mkdirSync(configDir, { recursive: true });
  
  const settings = {
    mainBranch: finalMainBranch,
    sonar: {
      enabled: sonarEnabled,
      projectKey: sonarProjectKey
    },
    tests: {
      runner: finalRunner,
      command: finalCommand,
      runBeforePush: runBeforePush
    }
  };

  fs.writeFileSync(configFile, JSON.stringify(settings, null, 2) + '\n');
  console.log(`  ${colorize('green', '✓')} Written: ${colorize('cyan', configFile)}`);
  console.log('');
  console.log(JSON.stringify(settings, null, 2).split('\n').map(l => '    ' + l).join('\n'));
  console.log('');
  console.log(colorize('green', '  ╔════════════════════════════════════════════════════╗'));
  console.log(colorize('green', '  ║   ✓  Project setup complete!                       ║'));
  console.log(colorize('green', '  ╚════════════════════════════════════════════════════╝'));
  console.log('');
}

module.exports = { run };
