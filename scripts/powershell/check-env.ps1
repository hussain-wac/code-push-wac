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

function Get-GitRemoteInfo {
  $remote = (& git remote get-url origin 2>$null)
  if (-not $remote) { return $null }
  $clean = $remote.Trim()
  if ($clean.EndsWith('.git')) { $clean = $clean.Substring(0, $clean.Length - 4) }

  if ($clean -match '^https://([^/]+)/(.+)$') {
    $remoteHost = "https://$($Matches[1])"
    $path = $Matches[2]
  } elseif ($clean -match '^git@([^:]+):(.+)$') {
    $remoteHost = "https://$($Matches[1])"
    $path = $Matches[2]
  } else {
    return $null
  }

  $provider = if ($remoteHost -like '*github.com*') { 'github' } else { 'gitlab' }
  [pscustomobject]@{
    Provider = $provider
    Host = $remoteHost
    ProjectPath = $path
  }
}

function Test-Tool([string]$Name) {
  return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

$allGood = $true
$remoteInfo = Get-GitRemoteInfo
$provider = Get-EnvValue 'GIT_PROVIDER'
if (-not $provider) { $provider = if ($remoteInfo) { $remoteInfo.Provider } else { 'gitlab' } }

Write-Host ''
Write-Info ' =================================================='
Write-Info '   devflow-cli -- Environment Check'
Write-Info ' =================================================='
Write-Host ''
Write-Info "[INFO] Provider: $provider"
$defaultAi = Get-EnvValue 'DEVFLOW_DEFAULT_AI_CLI'
if ($defaultAi) { Write-Info "[INFO] Default AI CLI: $defaultAi" }
Write-Host ''

function Check-RequiredVar([string]$Name, [string]$Hint, [string]$FallbackValue = '') {
  $value = Get-EnvValue $Name
  if (-not $value) { $value = $FallbackValue }
  if ($value) {
    if ($Name -like '*TOKEN*') {
      Write-Ok "[OK]   $Name is set"
    } else {
      Write-Ok "[OK]   $Name = $value"
    }
  } else {
    Write-Err "[FAIL] $Name is not set"
    if ($Hint) { Write-Warn "       $Hint" }
    $script:allGood = $false
  }
  Write-Host ''
}

if ($provider -eq 'github') {
  Check-RequiredVar 'GITHUB_TOKEN' 'Required scope: repo'
  Check-RequiredVar 'GITHUB_PROJECT_PATH' 'e.g. myorg/my-repo' $(if ($remoteInfo) { $remoteInfo.ProjectPath } else { '' })
} else {
  Check-RequiredVar 'GITLAB_TOKEN' 'Required scopes: api, write_repository'
  Check-RequiredVar 'GITLAB_PROJECT_PATH' 'e.g. myorg/my-repo' $(if ($remoteInfo) { $remoteInfo.ProjectPath } else { '' })
}

$useSonar = Get-EnvValue 'USE_SONAR'
if ($useSonar -eq '1') {
  Check-RequiredVar 'SONAR_TOKEN' ''
  Check-RequiredVar 'SONAR_HOST' 'e.g. https://sonarqube.example.com'
  Check-RequiredVar 'SONAR_PROJECT_KEY' 'Find in SonarQube project information'
}

Write-Info '[INFO] Optional config:'
if ($provider -eq 'github') {
  $githubHost = Get-EnvValue 'GITHUB_HOST'
  if (-not $githubHost) { $githubHost = if ($remoteInfo) { $remoteInfo.Host } else { 'https://github.com' } }
  $mainBranch = Get-EnvValue 'MAIN_BRANCH'
  if (-not $mainBranch) { $mainBranch = 'main' }
  Write-Host "  GITHUB_HOST  = $githubHost"
  Write-Host "  MAIN_BRANCH  = $mainBranch"
} else {
  $gitlabHost = Get-EnvValue 'GITLAB_HOST'
  if (-not $gitlabHost) { $gitlabHost = if ($remoteInfo) { $remoteInfo.Host } else { 'https://gitlab.com' } }
  $mainBranch = Get-EnvValue 'MAIN_BRANCH'
  if (-not $mainBranch) { $mainBranch = 'develop' }
  Write-Host "  GITLAB_HOST  = $gitlabHost"
  Write-Host "  MAIN_BRANCH  = $mainBranch"
}
Write-Host ''

if (Test-Tool 'git') { Write-Host '[OK]   Git found' } else { Write-Host '[FAIL] Git not found'; $allGood = $false }
if (Test-Tool 'git') { Write-Ok '[OK]   Git found' } else { Write-Err '[FAIL] Git not found'; $allGood = $false }
if (Test-Tool 'curl') { Write-Ok '[OK]   curl found' } else { Write-Err '[FAIL] curl not found'; $allGood = $false }
if ((Test-Tool 'python') -or (Test-Tool 'python3')) { Write-Ok '[OK]   Python found' } else { Write-Warn '[WARN] Python not found' }
Write-Host ''

if (Test-Tool 'claude') { Write-Ok '[OK]   Claude Code CLI found' } else { Write-Warn '[WARN] Claude Code CLI not found' }
if (Test-Tool 'codex') { Write-Ok '[OK]   Codex CLI found' } else { Write-Warn '[WARN] Codex CLI not found' }
if (Test-Tool 'gemini') { Write-Ok '[OK]   Gemini CLI found' } else { Write-Warn '[WARN] Gemini CLI not found' }
Write-Host ''

if (& git rev-parse --git-dir 2>$null) {
  $branch = (& git rev-parse --abbrev-ref HEAD).Trim()
  Write-Ok "[OK]   Git repository detected (branch: $branch)"
} else {
  Write-Err '[FAIL] Not in a Git repository'
  $allGood = $false
}

Write-Host ''
Write-Info ' =================================================='
Write-Host ''
if ($allGood) {
  Write-Ok '[OK]  All required dependencies are configured.'
  exit 0
}

Write-Err '[FAIL] Some required configuration is missing.'
exit 1
