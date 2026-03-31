$ErrorActionPreference = 'Stop'

function Write-Info([string]$Message) { Write-Host $Message -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host $Message -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host $Message -ForegroundColor Yellow }
function Write-Err([string]$Message) { Write-Host $Message -ForegroundColor Red }

function Get-EnvValue([string]$Name) {
  $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
  if (-not $value) { $value = [Environment]::GetEnvironmentVariable($Name, 'User') }
  if (-not $value) { $value = [Environment]::GetEnvironmentVariable($Name, 'Machine') }
  return $value
}

function Read-Answer([string]$Prompt, [string]$Default = '') {
  if ($Default) {
    $answer = Read-Host "$Prompt [$Default]"
  } else {
    $answer = Read-Host "$Prompt"
  }
  if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
  return $answer.Trim()
}

function Ask-YesNo([string]$Prompt, [string]$Default = 'n') {
  $suffix = if ($Default -eq 'y') { '(Y/n)' } else { '(y/N)' }
  $answer = Read-Host "  $Prompt $suffix"
  if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
  return $answer -match '^[Yy]$|yes'
}

function Select-MenuOption {
  param(
    [string]$Title,
    [string[]]$Options,
    [int]$DefaultIndex = 0
  )

  if (-not $Options -or $Options.Count -eq 0) { return $null }
  $index = [Math]::Max(0, [Math]::Min($DefaultIndex, $Options.Count - 1))

  while ($true) {
    Write-Host ''
    Write-Info $Title
    for ($i = 0; $i -lt $Options.Count; $i++) {
      if ($i -eq $index) {
        Write-Host "  > $($Options[$i])" -ForegroundColor Cyan
      } else {
        Write-Host "    $($Options[$i])"
      }
    }

    $key = [Console]::ReadKey($true)
    switch ($key.Key) {
      'UpArrow' {
        if ($index -gt 0) { $index-- } else { $index = $Options.Count - 1 }
      }
      'DownArrow' {
        if ($index -lt ($Options.Count - 1)) { $index++ } else { $index = 0 }
      }
      'Enter' {
        [Console]::Write("`r")
        return $Options[$index]
      }
    }

    [Console]::SetCursorPosition(0, [Math]::Max(0, [Console]::CursorTop - ($Options.Count + 1)))
  }
}

function Get-ProjectRoot {
  $root = (& git rev-parse --show-toplevel 2>$null)
  if ($root) { return $root.Trim() }
  return (Get-Location).Path
}

function Detect-TestRunner($ProjectRoot) {
    $pkg = Join-Path $ProjectRoot 'package.json'
    
    if (Test-Path (Join-Path $ProjectRoot 'vitest.config.js')) { return 'vitest' }
    if (Test-Path (Join-Path $ProjectRoot 'vitest.config.ts')) { return 'vitest' }
    if (Test-Path (Join-Path $ProjectRoot 'jest.config.js')) { return 'jest' }
    if (Test-Path (Join-Path $ProjectRoot 'jest.config.ts')) { return 'jest' }
    if (Test-Path (Join-Path $ProjectRoot 'playwright.config.ts')) { return 'playwright' }
    if (Test-Path (Join-Path $ProjectRoot 'cypress.config.ts')) { return 'cypress' }

    if (Test-Path $pkg) {
        $content = Get-Content $pkg -Raw
        if ($content -match 'vitest') { return 'vitest' }
        if ($content -match 'jest') { return 'jest' }
        if ($content -match 'mocha') { return 'mocha' }
    }
    return ''
}

function Detect-TestCommand($Runner, $ProjectRoot) {
    $pkg = Join-Path $ProjectRoot 'package.json'
    if (Test-Path $pkg) {
        $data = Get-Content $pkg -Raw | ConvertFrom-Json
        if ($data.scripts -and $data.scripts.test -and $data.scripts.test -notmatch 'no test specified') {
            return 'npm test'
        }
    }

    switch ($Runner) {
        'vitest' { return 'npx vitest run' }
        'jest' { return 'npx jest' }
        'playwright' { return 'npx playwright test' }
        'cypress' { return 'npx cypress run' }
        'mocha' { return 'npx mocha' }
        default { return 'npm test' }
    }
}

function Detect-Sonar($ProjectRoot) {
    if (Test-Path (Join-Path $ProjectRoot 'sonar-project.properties')) { return 'properties' }
    if (Test-Path (Join-Path $ProjectRoot '.sonarcloud.properties')) { return 'sonarcloud' }
    $pkg = Join-Path $ProjectRoot 'package.json'
    if (Test-Path $pkg) {
        $content = Get-Content $pkg -Raw
        if ($content -match 'sonar-scanner') { return 'script' }
    }
    return ''
}

Write-Host ''
Write-Info '  ╔════════════════════════════════════════════════════╗'
Write-Info '  ║                                                    ║'
Write-Info '  ║   🛠   devflow-cli — Project Setup              ║'
Write-Info '  ║                                                    ║'
Write-Info '  ╚════════════════════════════════════════════════════╝'
Write-Host ''
Write-Host "  Saves project config to .devflow\devflow-project-setting.json — safe to commit."
Write-Host "  For tokens & credentials, run: devflow setup" -ForegroundColor DarkGray
Write-Host ''

$projectRoot = Get-ProjectRoot
Write-Info "  Project root: $projectRoot"

$configDir = Join-Path $projectRoot '.devflow'
$configFile = Join-Path $configDir 'devflow-project-setting.json'
$legacyFile = Join-Path $projectRoot '.devflow.json'

$existingSettings = $null
if (Test-Path $configFile) {
    $existingSettings = Get-Content $configFile -Raw | ConvertFrom-Json
    Write-Ok "  ✓ Existing project settings found: .devflow\devflow-project-setting.json"
} elseif (Test-Path $legacyFile) {
    $existingSettings = Get-Content $legacyFile -Raw | ConvertFrom-Json
    Write-Ok "  ✓ Existing project settings found: .devflow.json"
    $configFile = $legacyFile
}

if ($existingSettings) {
    if ($existingSettings.mainBranch) { Write-Host "    mainBranch          = $($existingSettings.mainBranch)" -ForegroundColor Cyan }
    if ($existingSettings.sonar) { 
        Write-Host "    sonar.enabled       = $($existingSettings.sonar.enabled)" -ForegroundColor Cyan
        Write-Host "    sonar.projectKey    = $($existingSettings.sonar.projectKey)" -ForegroundColor Cyan
    }
    if ($existingSettings.tests) {
        Write-Host "    tests.runner        = $($existingSettings.tests.runner)" -ForegroundColor Cyan
        Write-Host "    tests.command       = $($existingSettings.tests.command)" -ForegroundColor Cyan
        Write-Host "    tests.runBeforePush = $($existingSettings.tests.runBeforePush)" -ForegroundColor Cyan
    }
    Write-Host ''
}

if (-not (Ask-YesNo 'Start project setup?' 'y')) {
    Write-Host '  Setup cancelled.'
    exit 0
}

# ── Step 1: Target Branch ─────────────────────────────────────────────────────
Write-Host ''
Write-Info '  ────────────────────────────────────────────────'
Write-Info '  Step 1 — Target Branch'
Write-Info '  ────────────────────────────────────────────────'
Write-Host ''

$detectedMain = (& git symbolic-ref refs/remotes/origin/HEAD 2>$null)
if ($detectedMain) { $detectedMain = $detectedMain.Split('/')[-1] }
if (-not $detectedMain) { $detectedMain = 'develop' }

$finalMainBranch = ''
if ($existingSettings -and $existingSettings.mainBranch) {
    Write-Host "  Current: $($existingSettings.mainBranch)" -ForegroundColor Cyan
    if (Ask-YesNo 'Change target branch?') {
        $branches = @('main', 'master', 'develop', 'stage', 'Other (enter manually)')
        $selection = Select-MenuOption -Title 'Use arrow keys and Enter to select the target branch' -Options $branches
        if ($selection -eq 'Other (enter manually)') {
            $finalMainBranch = Read-Answer '  Enter branch name'
        } else {
            $finalMainBranch = $selection
        }
    } else {
        $finalMainBranch = $existingSettings.mainBranch
    }
} else {
    $branches = @('main', 'master', 'develop', 'stage', 'Other (enter manually)')
    $selection = Select-MenuOption -Title 'Use arrow keys and Enter to select the target branch' -Options $branches
    if ($selection -eq 'Other (enter manually)') {
        $finalMainBranch = Read-Answer '  Enter branch name' $detectedMain
    } else {
        $finalMainBranch = $selection
    }
}
Write-Ok "  ✓ Target branch: $finalMainBranch"

# ── Step 2: SonarQube ─────────────────────────────────────────────────────────
Write-Host ''
Write-Info '  ────────────────────────────────────────────────'
Write-Info '  Step 2 — SonarQube'
Write-Info '  ────────────────────────────────────────────────'
Write-Host ''

$sonarSignal = Detect-Sonar $projectRoot
$sonarEnabled = $false

if ($sonarSignal) {
    Write-Ok "  ✓ Detected: SonarQube configuration found ($sonarSignal)"
    if (Ask-YesNo 'Enable SonarQube for this project?' 'y') { $sonarEnabled = $true }
} else {
    Write-Warn '  No SonarQube config detected in this project.'
    if (Ask-YesNo 'Enable SonarQube anyway?') { $sonarEnabled = $true }
}

$sonarProjectKey = ''
if ($sonarEnabled) {
    $suggestedKey = ''
    try {
        $remoteUrl = (& git remote get-url origin 2>$null)
        if ($remoteUrl -match '[:/]([^/:]+/[^/:]+)(\.git)?$') {
            $suggestedKey = $Matches[1].Replace('/', '_').Replace('-', '_').ToLower()
        }
    } catch {}

    $currentKey = if ($existingSettings -and $existingSettings.sonar) { $existingSettings.sonar.projectKey } else { Get-EnvValue 'SONAR_PROJECT_KEY' }
    if ($currentKey) {
        Write-Ok "  ✓ SonarQube project key: $currentKey"
        if (Ask-YesNo 'Change project key?') {
            $sonarProjectKey = Read-Answer '  SonarQube project key' $currentKey
        } else {
            $sonarProjectKey = $currentKey
        }
    } else {
        $sonarProjectKey = Read-Answer '  SonarQube project key' $suggestedKey
    }
}

# ── Step 3: Test Runner ───────────────────────────────────────────────────────
Write-Host ''
Write-Info '  ────────────────────────────────────────────────'
Write-Info '  Step 3 — Test Runner'
Write-Info '  ────────────────────────────────────────────────'
Write-Host ''

$detectedRunner = Detect-TestRunner $projectRoot
$finalRunner = ''
$finalCommand = ''
$runBeforePush = $false

if ($detectedRunner) {
    Write-Ok "  ✓ Auto-detected: $detectedRunner"
    $detectedCmd = Detect-TestCommand $detectedRunner $projectRoot
    Write-Host "    Command: $detectedCmd" -ForegroundColor Cyan
    if (Ask-YesNo 'Use detected runner?' 'y') {
        $finalRunner = $detectedRunner
        $finalCommand = $detectedCmd
    }
}

if (-not $finalRunner) {
    $runners = @('jest', 'vitest', 'mocha', 'jasmine', 'ava', 'karma', 'playwright', 'cypress', 'none')
    $finalRunner = Select-MenuOption -Title 'Use arrow keys and Enter to select the test runner' -Options $runners
    if ($finalRunner -eq 'none') {
        $finalRunner = ''
    } else {
        $detectedCmd = Detect-TestCommand $finalRunner $projectRoot
        $finalCommand = Read-Answer '  Test command' $detectedCmd
    }
}

if ($finalRunner) {
    $runBeforePush = Ask-YesNo 'Run tests automatically before every push?'
}

# ── Step 4: Saving ────────────────────────────────────────────────────────────
Write-Host ''
Write-Info '  ────────────────────────────────────────────────'
Write-Info '  Step 4 — Saving project settings'
Write-Info '  ────────────────────────────────────────────────'
Write-Host ''

if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir | Out-Null }
$configFile = Join-Path $configDir 'devflow-project-setting.json'

$settingsObj = @{
    mainBranch = $finalMainBranch
    sonar = @{
        enabled = $sonarEnabled
        projectKey = $sonarProjectKey
    }
    tests = @{
        runner = $finalRunner
        command = $finalCommand
        runBeforePush = $runBeforePush
    }
}

$settingsObj | ConvertTo-Json -Depth 5 | Set-Content $configFile
Write-Ok "  ✓ Written: $configFile"
Write-Host ''
Get-Content $configFile | ForEach-Object { Write-Host "    $_" }
Write-Host ''

Write-Ok '  ╔════════════════════════════════════════════════════╗'
Write-Ok '  ║   ✓  Project setup complete!                       ║'
Write-Ok '  ╚════════════════════════════════════════════════════╝'
Write-Host ''
Write-Info '  Next steps:'
Write-Info '    devflow push     — run the pipeline'
Write-Info '    devflow check    — verify environment'
Write-Host ''
