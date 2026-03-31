$ErrorActionPreference = 'Stop'

function Write-Info([string]$Message) { Write-Host $Message -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host $Message -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host $Message -ForegroundColor Yellow }
function Write-Err([string]$Message) { Write-Host $Message -ForegroundColor Red }
function Write-LiveStatus([string]$Message, [string]$Color = 'Cyan') { Write-Host "`r$Message" -NoNewline -ForegroundColor $Color }
function Clear-LiveStatus() { Write-Host "`r$(' ' * 100)`r" -NoNewline }

function Get-EnvValue([string]$Name) {
  $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
  if (-not $value) { $value = [Environment]::GetEnvironmentVariable($Name, 'User') }
  if (-not $value) { $value = [Environment]::GetEnvironmentVariable($Name, 'Machine') }
  return $value
}

function Get-ProjectRoot {
  $root = (& git rev-parse --show-toplevel 2>$null)
  if ($root) { return $root.Trim() }
  return (Get-Location).Path
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

function Get-ProjectSettings([string]$ProjectRoot) {
  $config = Join-Path $ProjectRoot '.devflow\devflow-project-setting.json'
  $legacy = Join-Path $ProjectRoot '.devflow.json'
  if (Test-Path $config) { return Get-Content $config -Raw | ConvertFrom-Json }
  if (Test-Path $legacy) { return Get-Content $legacy -Raw | ConvertFrom-Json }
  return $null
}

function Invoke-Git {
  param(
    [string[]]$GitArgs,
    [string]$ErrorMessage
  )
  & git @GitArgs
  if ($LASTEXITCODE -ne 0) {
    Write-Err $ErrorMessage
    exit 1
  }
}

$projectRoot = Get-ProjectRoot
Set-Location $projectRoot
$remoteInfo = Get-GitRemoteInfo
$settings = Get-ProjectSettings $projectRoot

$provider = Get-EnvValue 'GIT_PROVIDER'
if (-not $provider) { $provider = if ($remoteInfo) { $remoteInfo.Provider } else { 'gitlab' } }

if ($provider -eq 'github') {
  $token = Get-EnvValue 'GITHUB_TOKEN'
  $gitHost = if (Get-EnvValue 'GITHUB_HOST') { Get-EnvValue 'GITHUB_HOST' } elseif ($remoteInfo) { $remoteInfo.Host } else { 'https://github.com' }
  $projectPath = if ($remoteInfo) { $remoteInfo.ProjectPath } else { Get-EnvValue 'GITHUB_PROJECT_PATH' }
  $mainBranch = if (Get-EnvValue 'MAIN_BRANCH') { Get-EnvValue 'MAIN_BRANCH' } elseif ($settings -and $settings.mainBranch) { $settings.mainBranch } else { 'main' }
} else {
  $token = Get-EnvValue 'GITLAB_TOKEN'
  $gitHost = if (Get-EnvValue 'GITLAB_HOST') { Get-EnvValue 'GITLAB_HOST' } elseif ($remoteInfo) { $remoteInfo.Host } else { 'https://gitlab.com' }
  $projectPath = if ($remoteInfo) { $remoteInfo.ProjectPath } else { Get-EnvValue 'GITLAB_PROJECT_PATH' }
  $mainBranch = if (Get-EnvValue 'MAIN_BRANCH') { Get-EnvValue 'MAIN_BRANCH' } elseif ($settings -and $settings.mainBranch) { $settings.mainBranch } else { 'develop' }
}

$runTests = if ($settings -and $settings.tests -and $settings.tests.runBeforePush) { $true } else { $false }
$testCommand = if ($settings -and $settings.tests) { $settings.tests.command } else { $null }
$sonarEnabled = if ($settings -and $settings.sonar) { [bool]$settings.sonar.enabled } else { $false }
$sonarKey = if ($settings -and $settings.sonar) { $settings.sonar.projectKey } else { $null }

Write-Host ''
Write-Info ' ==================================================='
Write-Info '   Automated Code Push & SonarQube Pipeline'
Write-Info ' ==================================================='
Write-Host ''
if ($settings) { Write-Info ' Loading project settings...' }
Write-Info " Provider:  $provider"
Write-Info " Project:   $projectPath"
Write-Info " Target:    $mainBranch"
Write-Host ''

if (-not $token) { Write-Err '[ERROR] Git token not set. Run: devflow setup'; exit 1 }
if (-not $projectPath) { Write-Err '[ERROR] Project path not set and could not be auto-detected from git remote.'; exit 1 }

if ($runTests -and $testCommand) {
  Write-Info '---- Tests ---------------------------------------'
  Write-Info "Running: $testCommand"
  powershell -NoProfile -Command $testCommand
  if ($LASTEXITCODE -ne 0) { Write-Err '[ERROR] Tests failed. Push aborted.'; exit 1 }
  Write-Ok '[OK] Tests passed.'
  Write-Host ''
}

$currentBranch = (& git rev-parse --abbrev-ref HEAD).Trim()
Write-Info '---- Step 1: Git Status --------------------------------'
Write-Info "Current branch: $currentBranch"
Write-Host ''
if ($currentBranch -eq $mainBranch -or $currentBranch -eq 'main' -or $currentBranch -eq 'master') {
  Write-Warn '[WARN] You are on the main branch. Direct pushes are not recommended.'
  exit 1
}

& git diff --quiet
$diffExit = $LASTEXITCODE
& git diff --staged --quiet
$stagedExit = $LASTEXITCODE
if ($diffExit -eq 0 -and $stagedExit -eq 0) {
  Write-Warn 'No changes detected. Nothing to commit.'
} else {
  Write-Ok '[OK] Changes detected:'
  & git status --short
  Write-Host ''
  Write-Info '---- Step 2: Staging & Committing --------------------'
  Invoke-Git -GitArgs @('add', '-A') -ErrorMessage '[ERROR] Failed to stage changes.'
  $commitMsg = Read-Host 'Enter commit message'
  if ([string]::IsNullOrWhiteSpace($commitMsg)) { $commitMsg = 'chore: update implementation' }
  & git commit -m $commitMsg
  if ($LASTEXITCODE -ne 0) { Write-Err '[ERROR] Commit failed.'; exit 1 }
  Write-Ok '[OK] Changes committed.'
  Write-Host ''
}

Write-Info '---- Step 3: Syncing with Target Branch ----------------'
Invoke-Git -GitArgs @('fetch', 'origin', $mainBranch) -ErrorMessage "[ERROR] Failed to fetch origin/$mainBranch"
& git merge --no-edit "origin/$mainBranch"
if ($LASTEXITCODE -ne 0) {
  Write-Err "[ERROR] Merge conflict detected while syncing with origin/$mainBranch."
  Write-Warn '        Resolve the conflicts manually, then run devflow push again.'
  exit 1
}
Write-Ok "[OK] Branch synced with origin/$mainBranch."
Write-Host ''

Write-Info '---- Step 4: Pushing to Remote -------------------------'
& git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  Invoke-Git -GitArgs @('push', '-u', 'origin', $currentBranch) -ErrorMessage '[ERROR] Push failed.'
} else {
  Invoke-Git -GitArgs @('push') -ErrorMessage '[ERROR] Push failed.'
}
Write-Ok '[OK] Push successful.'
Write-Host ''

if ($provider -eq 'gitlab') {
  Write-Info '---- Step 5: Merge Request -----------------------------'
  $encodedProject = [uri]::EscapeDataString($projectPath)
  try {
    $mrs = Invoke-RestMethod -Headers @{ 'PRIVATE-TOKEN' = $token } -Uri "$gitHost/api/v4/projects/$encodedProject/merge_requests?source_branch=$currentBranch&state=opened" -Method Get
    if ($mrs -and $mrs.Count -gt 0) {
      Write-Ok '[OK] Existing MR found.'
      Write-Host "      $gitHost/$projectPath/-/merge_requests"
    } else {
      Write-Info 'Creating new merge request...'
      $title = (& git log -1 --pretty=%s).Trim()
      $body = @{
        source_branch = $currentBranch
        target_branch = $mainBranch
        title = $title
        remove_source_branch = $true
      } | ConvertTo-Json -Compress
      try {
        Invoke-RestMethod -Headers @{ 'PRIVATE-TOKEN' = $token } -ContentType 'application/json' -Uri "$gitHost/api/v4/projects/$encodedProject/merge_requests" -Method Post -Body $body | Out-Null
        Write-Ok '[OK] Merge request created.'
      } catch {
        Write-Warn '[WARN] Could not create MR automatically.'
        Write-Warn "       Create manually: $gitHost/$projectPath/-/merge_requests/new"
      }
    }
  } catch {
    if ($_.Exception.Message -match "invalid_token" -or ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 401)) {
      Write-Err "[ERROR] GitLab authentication failed."
      Write-Warn "        Your token may be expired or revoked. Run 'devflow setup' to update it."
      exit 1
    }
    Write-Warn "[WARN] Could not connect to GitLab to check/create Merge Request."
    Write-Warn "       Error: $($_.Exception.Message)"
  }
  Write-Host ''
} else {
  Write-Info '---- Step 5: Pull Request ------------------------------'
  try {
    $title = (& git log -1 --pretty=%s).Trim()
    $parts = $projectPath.Split('/')
    $owner = $parts[0]
    $repo = $parts[1]
    $headers = @{ Authorization = "token $token"; 'User-Agent' = 'wac-devflow'; Accept = 'application/vnd.github+json' }
    $existing = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$owner/$repo/pulls?head=$owner`:$currentBranch&state=open" -Method Get
    if ($existing -and $existing.Count -gt 0) {
      Write-Ok '[OK] Existing PR found.'
      Write-Host "      $gitHost/$projectPath/pulls"
    } else {
      $body = @{ title = $title; head = $currentBranch; base = $mainBranch } | ConvertTo-Json -Compress
      Invoke-RestMethod -Headers $headers -ContentType 'application/json' -Uri "https://api.github.com/repos/$owner/$repo/pulls" -Method Post -Body $body | Out-Null
      Write-Ok '[OK] Pull request created.'
    }
  } catch {
    Write-Warn '[WARN] Could not create PR automatically.'
    Write-Warn "       Create manually: $gitHost/$projectPath/compare/$mainBranch...$currentBranch"
  }
  Write-Host ''
}

Write-Info '---- Step 6: Pipeline ----------------------------------'
Write-Info 'Waiting 10 seconds for pipeline to initialise...'
Start-Sleep -Seconds 10
if ($provider -eq 'gitlab') {
  try {
    $encodedProject = [uri]::EscapeDataString($projectPath)
    $pipelines = Invoke-RestMethod -Headers @{ 'PRIVATE-TOKEN' = $token } -Uri "$gitHost/api/v4/projects/$encodedProject/pipelines?ref=$currentBranch&per_page=1" -Method Get
    if (-not $pipelines -or $pipelines.Count -eq 0) {
      Write-Warn '[WARN] No pipeline found after waiting 10 seconds. Exiting.'
    } else {
      $pipeline = $pipelines[0]
      $pipelineId = $pipeline.id
      $pipelineStatus = $pipeline.status
      $waited = 0
      $pollInterval = 5
      $maxWait = 1800

      Write-Ok "[OK] Pipeline found: #$pipelineId"
      Write-Host ''
      while ($pipelineStatus -in @('running', 'pending', 'created', 'preparing', 'waiting_for_resource')) {
        Write-LiveStatus "Pipeline: $pipelineStatus | ${waited}s elapsed" 'Cyan'
        Start-Sleep -Seconds $pollInterval
        $waited += $pollInterval
        if ($waited -ge $maxWait) {
          Clear-LiveStatus
          Write-Err '[ERROR] Timeout waiting for pipeline.'
          exit 1
        }
        $pipeline = Invoke-RestMethod -Headers @{ 'PRIVATE-TOKEN' = $token } -Uri "$gitHost/api/v4/projects/$encodedProject/pipelines/$pipelineId" -Method Get
        $pipelineStatus = $pipeline.status
      }
      Clear-LiveStatus
      if ($pipelineStatus -eq 'success') {
        Write-Ok "[OK] Pipeline finished: $pipelineStatus"
      } else {
        Write-Warn "[WARN] Pipeline finished: $pipelineStatus"
      }
      Write-Host "      $gitHost/$projectPath/-/pipelines"
    }
  } catch {
    Write-Warn '[WARN] Could not query pipeline status.'
  }
} else {
  Write-Warn '[INFO] Pipeline check is not implemented for GitHub in the Windows PowerShell flow yet.'
}
Write-Host ''

if ($sonarEnabled -and (Get-EnvValue 'SONAR_TOKEN') -and $sonarKey -and (Get-EnvValue 'SONAR_HOST')) {
  Write-Info '---- Step 7: SonarQube Issues --------------------------'
  try {
    $sonarHost = Get-EnvValue 'SONAR_HOST'
    $sonarToken = Get-EnvValue 'SONAR_TOKEN'
    $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${sonarToken}:"))
    $headers = @{ Authorization = "Basic $auth" }
    $url = "$sonarHost/api/issues/search?componentKeys=$sonarKey&statuses=OPEN,CONFIRMED&ps=10&s=SEVERITY&asc=false"
    $response = Invoke-RestMethod -Headers $headers -Uri $url -Method Get
    if ($response.total -eq 0) {
      Write-Ok '[OK] No open SonarQube issues.'
    } else {
      Write-Warn '[INFO] Open issues found. Run devflow sonar for details.'
    }
  } catch {
    Write-Warn '[WARN] Could not query SonarQube issues.'
  }
  Write-Host ''
}

Write-Info '--------------------------------------------------'
Write-Ok '[OK] Pipeline complete!'
