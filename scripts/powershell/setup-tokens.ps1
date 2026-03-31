$ErrorActionPreference = 'Stop'

function Write-Info([string]$Message) { Write-Host $Message -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host $Message -ForegroundColor Green }

function Get-EnvValue([string]$Name) {
  $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
  if (-not $value) { $value = [Environment]::GetEnvironmentVariable($Name, 'User') }
  if (-not $value) { $value = [Environment]::GetEnvironmentVariable($Name, 'Machine') }
  return $value
}

function Set-DevflowEnv([string]$Name, [string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return }
  [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
  [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
  Write-Ok "[OK]   $Name saved"
}

function Read-Answer([string]$Prompt, [string]$Default = '') {
  $answer = Read-Host $Prompt
  if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
  return $answer.Trim()
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
  [pscustomobject]@{ Provider = $provider; Host = $remoteHost; ProjectPath = $path }
}

Write-Host ''
Write-Info ' ===================================================='
Write-Info '   devflow-cli -- Setup Wizard'
Write-Info ' ===================================================='
Write-Host ''

$remoteInfo = Get-GitRemoteInfo
if ($remoteInfo) {
  Write-Info "Detected provider: $($remoteInfo.Provider)"
  Write-Info "Detected host: $($remoteInfo.Host)"
  Write-Info "Detected project path: $($remoteInfo.ProjectPath)"
  Write-Host ''
}

$providerOptions = @('gitlab', 'github')
$providerDefault = if ($remoteInfo -and $remoteInfo.Provider -eq 'github') { 1 } else { 0 }
$provider = Select-MenuOption -Title 'Use arrow keys and Enter to select the git provider' -Options $providerOptions -DefaultIndex $providerDefault
if ($provider -ne 'github') { $provider = 'gitlab' }

if ($provider -eq 'github') {
  $gitHost = Read-Answer 'GitHub Host URL' $(if (Get-EnvValue 'GITHUB_HOST') { Get-EnvValue 'GITHUB_HOST' } elseif ($remoteInfo) { $remoteInfo.Host } else { 'https://github.com' })
  $projectPath = Read-Answer 'GitHub project path (org/repo)' $(if (Get-EnvValue 'GITHUB_PROJECT_PATH') { Get-EnvValue 'GITHUB_PROJECT_PATH' } elseif ($remoteInfo) { $remoteInfo.ProjectPath } else { '' })
  $token = Read-Answer 'GitHub token'
  Set-DevflowEnv 'GIT_PROVIDER' 'github'
  Set-DevflowEnv 'GITHUB_HOST' $gitHost
  Set-DevflowEnv 'GITHUB_PROJECT_PATH' $projectPath
  Set-DevflowEnv 'GITHUB_TOKEN' $token
} else {
  $gitHost = Read-Answer 'GitLab Host URL' $(if (Get-EnvValue 'GITLAB_HOST') { Get-EnvValue 'GITLAB_HOST' } elseif ($remoteInfo) { $remoteInfo.Host } else { 'https://gitlab.com' })
  $projectPath = Read-Answer 'GitLab project path (group/project)' $(if (Get-EnvValue 'GITLAB_PROJECT_PATH') { Get-EnvValue 'GITLAB_PROJECT_PATH' } elseif ($remoteInfo) { $remoteInfo.ProjectPath } else { '' })
  $token = Read-Answer 'GitLab token'
  Set-DevflowEnv 'GIT_PROVIDER' 'gitlab'
  Set-DevflowEnv 'GITLAB_HOST' $gitHost
  Set-DevflowEnv 'GITLAB_PROJECT_PATH' $projectPath
  Set-DevflowEnv 'GITLAB_TOKEN' $token
}

$sonarSelection = Select-MenuOption -Title 'Use arrow keys and Enter to choose SonarQube usage' -Options @('No', 'Yes') -DefaultIndex 0
if ($sonarSelection -eq 'Yes') {
  Set-DevflowEnv 'USE_SONAR' '1'
  Set-DevflowEnv 'SONAR_HOST' (Read-Answer 'SonarQube host URL' (Get-EnvValue 'SONAR_HOST'))
  Set-DevflowEnv 'SONAR_TOKEN' (Read-Answer 'SonarQube token')
} else {
  Set-DevflowEnv 'USE_SONAR' '0'
}

$defaultAiOptions = @('claude', 'codex', 'gemini', 'skip')
$existingDefaultAi = Get-EnvValue 'DEVFLOW_DEFAULT_AI_CLI'
$defaultAiIndex = 3
for ($i = 0; $i -lt $defaultAiOptions.Count; $i++) {
  if ($defaultAiOptions[$i] -eq $existingDefaultAi) { $defaultAiIndex = $i }
}
$defaultAi = Select-MenuOption -Title 'Use arrow keys and Enter to choose the default AI CLI' -Options $defaultAiOptions -DefaultIndex $defaultAiIndex
if ($defaultAi -and $defaultAi -ne 'skip') { Set-DevflowEnv 'DEVFLOW_DEFAULT_AI_CLI' $defaultAi }

Write-Host ''
Write-Ok 'Setup complete.'
Write-Info 'Run: devflow check'
