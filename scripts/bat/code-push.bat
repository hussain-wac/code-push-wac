@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo.
echo  ╔═══════════════════════════════════════════════════╗
echo  ║   Automated Code Push ^& SonarQube Pipeline      ║
echo  ╚═══════════════════════════════════════════════════╝
echo.
echo  NOTE: For the full experience with animations and
echo        AI features, install Git Bash and re-run.
echo        https://git-scm.com/download/win
echo.

:: ── Validate required env vars ────────────────────────────────────────────────
if not defined GITLAB_TOKEN       (echo [ERROR] GITLAB_TOKEN not set        & echo         setx GITLAB_TOKEN "your-token"           & exit /b 1)
if not defined SONAR_TOKEN        (echo [ERROR] SONAR_TOKEN not set         & echo         setx SONAR_TOKEN "your-token"            & exit /b 1)
if not defined GITLAB_PROJECT_PATH(echo [ERROR] GITLAB_PROJECT_PATH not set & echo         setx GITLAB_PROJECT_PATH "myorg/my-repo" & exit /b 1)
if not defined SONAR_PROJECT_KEY  (echo [ERROR] SONAR_PROJECT_KEY not set   & echo         setx SONAR_PROJECT_KEY "myorg_my-repo_key" & exit /b 1)
if not defined SONAR_HOST         (echo [ERROR] SONAR_HOST not set          & echo         setx SONAR_HOST "https://sonarqube.example.com" & exit /b 1)

if not defined GITLAB_HOST  set GITLAB_HOST=https://gitlab.com
if not defined MAIN_BRANCH  set MAIN_BRANCH=develop
if not defined MAX_RETRIES  set MAX_RETRIES=3

:: ── Step 1: Git status ─────────────────────────────────────────────────────────
echo ━━ Step 1: Git Status ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
for /f "tokens=*" %%b in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set CURRENT_BRANCH=%%b
echo Current branch: %CURRENT_BRANCH%
echo.

if "%CURRENT_BRANCH%"=="%MAIN_BRANCH%" goto :warn_main_branch
if "%CURRENT_BRANCH%"=="main"          goto :warn_main_branch
if "%CURRENT_BRANCH%"=="master"        goto :warn_main_branch
goto :check_changes

:warn_main_branch
echo [WARN] You are on the main branch. Direct pushes are not recommended.
set /p BRANCH_CHOICE="Create a new branch? (y/N): "
if /i "%BRANCH_CHOICE%"=="y" (
    set /p NEW_BRANCH="Enter branch name (e.g. feat/my-feature): "
    git checkout -b "!NEW_BRANCH!" || exit /b 1
    set CURRENT_BRANCH=!NEW_BRANCH!
    echo [OK] Created and switched to: !NEW_BRANCH!
) else (
    echo Aborted.
    exit /b 0
)

:check_changes
git diff --quiet 2>nul && git diff --staged --quiet 2>nul
if %ERRORLEVEL%==0 (
    echo No changes detected. Nothing to commit.
    goto :push
)

echo [OK] Changes detected:
git status --short
echo.

:: ── Step 2: Commit ────────────────────────────────────────────────────────────
echo ━━ Step 2: Staging ^& Committing ━━━━━━━━━━━━━━━━━━━
git add -A

if exist "%LOCALAPPDATA%\Programs\Claude\claude.exe" (
    echo Generating commit message with Claude...
    echo NOTE: Commit message generation works better with Git Bash.
)

echo.
set /p COMMIT_MSG="Enter commit message (e.g. feat: add user auth): "
if "%COMMIT_MSG%"=="" set COMMIT_MSG=chore: update implementation

git commit -m "%COMMIT_MSG%"
echo [OK] Changes committed.
echo.

:: ── Step 3: Push ──────────────────────────────────────────────────────────────
:push
echo ━━ Step 3: Pushing to Remote ━━━━━━━━━━━━━━━━━━━━━━
set SKIP_SONAR=1
git push -u origin %CURRENT_BRANCH% 2>nul || git push 2>nul || (echo [ERROR] Push failed & exit /b 1)
echo [OK] Push successful.
echo.

:: ── Step 4: Create MR ─────────────────────────────────────────────────────────
echo ━━ Step 4: Merge Request ━━━━━━━━━━━━━━━━━━━━━━━━━━
set ENCODED_PROJECT=%GITLAB_PROJECT_PATH:/=%%2F%

for /f "tokens=*" %%r in ('curl -s --header "PRIVATE-TOKEN: %GITLAB_TOKEN%" "%GITLAB_HOST%/api/v4/projects/%ENCODED_PROJECT%/merge_requests?source_branch=%CURRENT_BRANCH%&state=opened" 2^>nul') do set MR_RESPONSE=%%r

echo %MR_RESPONSE% | find "iid" >nul 2>&1 && (
    echo [OK] Existing MR found.
    echo      %GITLAB_HOST%/%GITLAB_PROJECT_PATH%/-/merge_requests
) || (
    echo Creating new merge request...
    for /f "tokens=*" %%t in ('git log -1 --pretty=%%s 2^>nul') do set MR_TITLE=%%t

    powershell -NoProfile -Command ^
        "$body = @{ source_branch='%CURRENT_BRANCH%'; target_branch='%MAIN_BRANCH%'; title='%MR_TITLE%'; remove_source_branch=$true } | ConvertTo-Json -Compress; ^
         Invoke-RestMethod -Method POST -Uri '%GITLAB_HOST%/api/v4/projects/%ENCODED_PROJECT%/merge_requests' ^
           -Headers @{'PRIVATE-TOKEN'='%GITLAB_TOKEN%'} -ContentType 'application/json' -Body $body" >nul 2>&1 && (
        echo [OK] Merge request created.
    ) || (
        echo [WARN] Could not create MR automatically.
        echo        Create manually: %GITLAB_HOST%/%GITLAB_PROJECT_PATH%/-/merge_requests/new
    )
)
echo.

:: ── Step 5: SonarQube issues ──────────────────────────────────────────────────
echo ━━ Step 5: SonarQube Issues ━━━━━━━━━━━━━━━━━━━━━━━
echo Checking for open issues...

set SONAR_URL=%SONAR_HOST%/api/issues/search?componentKeys=%SONAR_PROJECT_KEY%^&statuses=OPEN,CONFIRMED^&ps=10^&s=SEVERITY^&asc=false
for /f "tokens=*" %%r in ('curl -s -u "%SONAR_TOKEN%:" "%SONAR_URL%" 2^>nul') do set SONAR_RESPONSE=%%r

echo %SONAR_RESPONSE% | find "\"total\":0" >nul 2>&1 && (
    echo [OK] No open SonarQube issues!
) || (
    echo [INFO] Open issues found. Run 'code-push sonar' for details.
    echo        Or install Git Bash for the full auto-fix pipeline.
)
echo.

echo ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo [OK] Pipeline complete!
echo.
echo For the full pipeline with SonarQube auto-fix,
echo install Git Bash: https://git-scm.com/download/win
echo.
endlocal
exit /b 0
