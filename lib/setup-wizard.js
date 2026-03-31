'use strict';

const { execSync, spawnSync } = require('child_process');
const os = require('os');
const { 
  colorize, askValue, askYesNo, selectMenu, printBanner, printStep 
} = require('./wizard');
const Spinner = require('./spinner');

async function run(projectRoot) {
  printBanner('First-Time Setup', '🔐');
  console.log(`  All tokens are saved to your system environment — ${colorize('yellow', 'never')} to git.`);
  console.log('');

  const isWindows = os.platform() === 'win32';

  const existingVars = {
    GIT_PROVIDER: process.env.GIT_PROVIDER || '',
    GITLAB_TOKEN: process.env.GITLAB_TOKEN || '',
    GITHUB_TOKEN: process.env.GITHUB_TOKEN || '',
    GITLAB_HOST: process.env.GITLAB_HOST || '',
    GITHUB_HOST: process.env.GITHUB_HOST || '',
    USE_SONAR: process.env.USE_SONAR || '',
    SONAR_TOKEN: process.env.SONAR_TOKEN || '',
    SONAR_HOST: process.env.SONAR_HOST || '',
    DEVFLOW_DEFAULT_AI_CLI: process.env.DEVFLOW_DEFAULT_AI_CLI || ''
  };

  console.log(`  ${colorize('blue', 'Current configuration status:')}`);
  const showVar = (name, val) => {
    if (val) {
      const display = name.includes('TOKEN') ? '(already set)' : val;
      console.log(`    ${colorize('green', '✓')} ${name.padEnd(22)} = ${colorize('cyan', display)}`);
    } else {
      console.log(`    ${colorize('red', '✗')} ${name.padEnd(22)} ${colorize('dim', '(not set)')}`);
    }
  };

  Object.entries(existingVars).forEach(([k, v]) => showVar(k, v));
  console.log('');

  if (!(await askYesNo('Start global setup?', true))) {
    console.log('  Setup cancelled.');
    process.exit(0);
  }

  // ── Step 1: Git Provider ───────────────────────────────────────────────────
  printStep('Step 1 — Git Provider');
  
  const spinner = new Spinner('Auto-detecting from git remote...');
  spinner.start();
  let autoHost = '', autoProjectPath = '', autoProvider = '';
  try {
    const remoteUrl = execSync('git remote get-url origin', { encoding: 'utf8' }).trim();
    if (remoteUrl) {
      const cleanUrl = remoteUrl.replace(/\.git$/, '');
      if (cleanUrl.startsWith('https://')) {
        const parts = cleanUrl.replace('https://', '').split('/');
        autoHost = `https://${parts[0]}`;
        autoProjectPath = parts.slice(1).join('/');
      } else if (cleanUrl.includes('@')) {
        const parts = cleanUrl.split('@')[1].split(':');
        autoHost = `https://${parts[0]}`;
        autoProjectPath = parts[1];
      }
      
      if (autoHost.includes('github.com')) autoProvider = 'github';
      else if (autoHost) autoProvider = 'gitlab';
    }
  } catch (_) {}
  spinner.stop(true, 'Detection complete');

  if (autoHost) {
    console.log(`    ${colorize('green', '✓')} Detected: ${colorize('cyan', autoProvider)} (${autoHost})`);
    console.log('');
  }

  const providers = ['gitlab', 'github'];
  const provider = await selectMenu('Select your git provider', providers, providers.indexOf(autoProvider) || 0);
  console.log(`  ${colorize('green', '✓')} Provider: ${colorize('cyan', provider)}`);

  // ── Step 2: Provider Config ────────────────────────────────────────────────
  printStep(`Step 2 — ${provider === 'github' ? 'GitHub' : 'GitLab'} Configuration`);
  
  let gitHost = '', gitToken = '';
  if (provider === 'github') {
    gitHost = await askValue('GitHub Host URL', existingVars.GITHUB_HOST || autoHost || 'https://github.com');
    console.log(`  ${colorize('blue', 'Generate token at:')} ${gitHost}/settings/tokens/new`);
    gitToken = await askValue('Paste GitHub token (hidden)', '', true);
  } else {
    gitHost = await askValue('GitLab Host URL', existingVars.GITLAB_HOST || autoHost || 'https://gitlab.com');
    console.log(`  ${colorize('blue', 'Generate token at:')} ${gitHost}/-/user_settings/personal_access_tokens`);
    gitToken = await askValue('Paste GitLab token (hidden)', '', true);
  }

  // ── Step 3: SonarQube ──────────────────────────────────────────────────────
  printStep('Step 3 — SonarQube (optional)');
  
  let useSonar = await askYesNo('Does this project use SonarQube?', existingVars.USE_SONAR === '1');
  let sonarHost = '', sonarToken = '';

  if (useSonar) {
    sonarHost = await askValue('SonarQube host URL', existingVars.SONAR_HOST || 'https://sonarqube.example.com');
    sonarToken = await askValue('Paste SonarQube token (hidden)', '', true);
  }

  // ── Step 4: AI CLI ─────────────────────────────────────────────────────────
  printStep('Step 4 — AI Coding CLI');
  
  const aiChoices = ['claude', 'codex', 'gemini', 'skip'];
  const defaultAi = await selectMenu('Choose your default AI coding CLI', aiChoices, aiChoices.indexOf(existingVars.DEVFLOW_DEFAULT_AI_CLI) || 0);

  // ── Step 5: Save ───────────────────────────────────────────────────────────
  printStep('Step 5 — Saving Environment Variables');

  const varsToSave = {
    GIT_PROVIDER: provider,
    USE_SONAR: useSonar ? '1' : '0',
    DEVFLOW_DEFAULT_AI_CLI: defaultAi !== 'skip' ? defaultAi : existingVars.DEVFLOW_DEFAULT_AI_CLI
  };

  if (provider === 'github') {
    varsToSave.GITHUB_HOST = gitHost;
    if (gitToken) varsToSave.GITHUB_TOKEN = gitToken;
  } else {
    varsToSave.GITLAB_HOST = gitHost;
    if (gitToken) varsToSave.GITLAB_TOKEN = gitToken;
  }

  if (useSonar) {
    varsToSave.SONAR_HOST = sonarHost;
    if (sonarToken) varsToSave.SONAR_TOKEN = sonarToken;
  }

  const saveSpinner = new Spinner('Persisting to system environment...');
  saveSpinner.start();

  try {
    for (const [key, value] of Object.entries(varsToSave)) {
      if (isWindows) {
        // Set environment variable in Windows (User scope)
        execSync(`powershell.exe -Command "[Environment]::SetEnvironmentVariable('${key}', '${value}', 'User')"`);
      } else {
        // Unix: Update ~/.bashrc or ~/.zshrc
        const shell = process.env.SHELL || '/bin/bash';
        const profile = shell.includes('zsh') ? '.zshrc' : '.bashrc';
        const profilePath = require('path').join(require('os').homedir(), profile);
        
        let content = '';
        if (require('fs').existsSync(profilePath)) {
          content = require('fs').readFileSync(profilePath, 'utf8');
        }

        // Remove old block if exists
        const regex = /# devflow-cli[\s\S]*?# \/devflow-cli/g;
        content = content.replace(regex, '');

        const newBlock = `# devflow-cli\n${Object.entries(varsToSave).map(([k, v]) => `export ${k}='${v}'`).join('\n')}\n# /devflow-cli`;
        require('fs').writeFileSync(profilePath, content.trim() + '\n\n' + newBlock + '\n');
      }
    }
    saveSpinner.stop(true, 'Environment updated');
  } catch (err) {
    saveSpinner.stop(false, 'Failed to save environment');
    console.error(err);
  }

  console.log('');
  console.log(colorize('green', '  ╔════════════════════════════════════════════════════╗'));
  console.log(colorize('green', '  ║   ✓  Setup complete!                               ║'));
  console.log(colorize('green', '  ╚════════════════════════════════════════════════════╝'));
  console.log('');
  console.log(`  Run ${colorize('cyan', 'devflow project-setup')} in your repository to finish.`);
}

module.exports = { run };
