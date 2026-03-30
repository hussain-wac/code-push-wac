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

:: ── Load .devflow.json if present ─────────────────────────────────────────────
set DEVFLOW_MAIN_BRANCH=
set DEVFLOW_SONAR_KEY=
set DEVFLOW_RUN_TESTS=0
set DEVFLOW_TEST_CMD=

for /f "tokens=*" %%p in ('git rev-parse --show-toplevel 2^>nul') do set PROJECT_ROOT=%%p
if exist "%PROJECT_ROOT%\.devflow.json" (
    echo  Loading .devflow.json...
    for /f "tokens=*" %%v in ('powershell -NoProfile -Command "try { $d = Get-Content ''%PROJECT_ROOT%\.devflow.json'' | ConvertFrom-Json; Write-Output $d.mainBranch } catch { Write-Output '' }" 2^>nul') do set DEVFLOW_MAIN_BRANCH=%%v
    for /f "tokens=*" %%v in ('powershell -NoProfile -Command "try { $d = Get-Content ''%PROJECT_ROOT%\.devflow.json'' | ConvertFrom-Json; Write-Output $d.sonar.projectKey } catch { Write-Output '' }" 2^>nul') do set DEVFLOW_SONAR_KEY=%%v
    for /f "tokens=*" %%v in ('powershell -NoProfile -Command "try { $d = Get-Content ''%PROJECT_ROOT%\.devflow.json'' | ConvertFrom-Json; if ($d.tests.runBeforePush) { Write-Output 1 } else { Write-Output 0 } } catch { Write-Output 0 }" 2^>nul') do set DEVFLOW_RUN_TESTS=%%v
    for /f "tokens=*" %%v in ('powershell -NoProfile -Command "try { $d = Get-Content ''%PROJECT_ROOT%\.devflow.json'' | ConvertFrom-Json; Write-Output $d.tests.command } catch { Write-Output '' }" 2^>nul') do set DEVFLOW_TEST_CMD=%%v
)

:: ── Auto-detect project path from git remote ──────────────────────────────────
set AUTO_PROJECT_PATH=
for /f "tokens=*" %%r in ('git remote get-url origin 2^>nul') do set REMOTE_URL=%%r

if defined REMOTE_URL (
    echo %REMOTE_URL% | findstr /r "^https://" >nul 2>&1 && (
        set _tmp=%REMOTE_URL:https://=%
        for /f "tokens=1 delims=/" %%h in ("!_tmp!") do set _host=%%h
        set _path=!_tmp!
        for /f "tokens=1 delims=/" %%h in ("!_path!") do set _path=!_path:%%h/=!
        set AUTO_PROJECT_PATH=!_path:.git=!
    )
)

:: ── Resolve config — env vars take priority over .devflow.json ────────────────
if not defined GITLAB_HOST  set GITLAB_HOST=https://gitlab.com
if not defined MAIN_BRANCH  (
    if defined DEVFLOW_MAIN_BRANCH (set MAIN_BRANCH=!DEVFLOW_MAIN_BRANCH!) else (set MAIN_BRANCH=develop)
)
if not defined MAX_RETRIES  set MAX_RETRIES=3

:: Resolve project path: env var > auto-detected
if defined GITLAB_PROJECT_PATH (
    set RESOLVED_PROJECT_PATH=%GITLAB_PROJECT_PATH%
) else if defined AUTO_PROJECT_PATH (
    set RESOLVED_PROJECT_PATH=!AUTO_PROJECT_PATH!
) else (
    echo [ERROR] Could not detect project path from git remote.
    echo         Set GITLAB_PROJECT_PATH or ensure git remote is configured.
    exit /b 1
)

:: Resolve SonarQube project key: env var > .devflow.json
if defined SONAR_PROJECT_KEY (
    set RESOLVED_SONAR_KEY=%SONAR_PROJECT_KEY%
) else if defined DEVFLOW_SONAR_KEY (
    set RESOLVED_SONAR_KEY=!DEVFLOW_SONAR_KEY!
) else (
    set RESOLVED_SONAR_KEY=
)

:: ── Validate required env vars ────────────────────────────────────────────────
if not defined GITLAB_TOKEN (
    echo [ERROR] GITLAB_TOKEN not set
    echo         Run: devflow setup
    exit /b 1
)

echo  Provider:  gitlab
echo  Project:   %RESOLVED_PROJECT_PATH%
echo  Target:    %MAIN_BRANCH%
echo.

:: ── Run tests before push (if configured) ─────────────────────────────────────
if "!DEVFLOW_RUN_TESTS!"=="1" (
    if defined DEVFLOW_TEST_CMD (
        echo ━━ Tests ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        echo Running: !DEVFLOW_TEST_CMD!
        cmd /c "!DEVFLOW_TEST_CMD!"
        if !ERRORLEVEL! neq 0 (
            echo [ERROR] Tests failed. Push aborted.
            echo         Fix failing tests or set runBeforePush to false in .devflow.json
            exit /b 1
        )
        echo [OK] Tests passed.
        echo.
    )
)

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
set ENCODED_PROJECT=%RESOLVED_PROJECT_PATH:/=%%2F%

for /f "tokens=*" %%r in ('curl -s --header "PRIVATE-TOKEN: %GITLAB_TOKEN%" "%GITLAB_HOST%/api/v4/projects/%ENCODED_PROJECT%/merge_requests?source_branch=%CURRENT_BRANCH%&state=opened" 2^>nul') do set MR_RESPONSE=%%r

echo %MR_RESPONSE% | find "iid" >nul 2>&1 && (
    echo [OK] Existing MR found.
    echo      %GITLAB_HOST%/%RESOLVED_PROJECT_PATH%/-/merge_requests
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
        echo        Create manually: %GITLAB_HOST%/%RESOLVED_PROJECT_PATH%/-/merge_requests/new
    )
)
echo.

:: ── Step 5: Pipeline check (10s wait) ─────────────────────────────────────────
echo ━━ Step 5: Pipeline ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo Waiting 10 seconds for pipeline to initialise...
timeout /t 10 /nobreak >nul

for /f "tokens=*" %%b in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set _BRANCH=%%b
for /f "tokens=*" %%r in ('curl -s --header "PRIVATE-TOKEN: %GITLAB_TOKEN%" "%GITLAB_HOST%/api/v4/projects/%ENCODED_PROJECT%/pipelines?ref=%_BRANCH%^&per_page=1" 2^>nul') do set PIPELINE_RESPONSE=%%r

echo %PIPELINE_RESPONSE% | find "\"id\"" >nul 2>&1 && (
    echo [OK] Pipeline found. Check status at:
    echo      %GITLAB_HOST%/%RESOLVED_PROJECT_PATH%/-/pipelines
) || (
    echo [WARN] No pipeline found after waiting 10 seconds. Exiting.
)
echo.

:: ── Step 6: SonarQube issues (optional) ───────────────────────────────────────
if defined SONAR_TOKEN (
    if defined RESOLVED_SONAR_KEY (
        echo ━━ Step 6: SonarQube Issues ━━━━━━━━━━━━━━━━━━━━━━━
        echo Checking for open issues...

        set SONAR_URL=%SONAR_HOST%/api/issues/search?componentKeys=%RESOLVED_SONAR_KEY%^&statuses=OPEN,CONFIRMED^&ps=10^&s=SEVERITY^&asc=false
        for /f "tokens=*" %%r in ('curl -s -u "%SONAR_TOKEN%:" "!SONAR_URL!" 2^>nul') do set SONAR_RESPONSE=%%r

        echo %SONAR_RESPONSE% | find "\"total\":0" >nul 2>&1 && (
            echo [OK] No open SonarQube issues!
        ) || (
            echo [INFO] Open issues found. Run 'devflow sonar' for details.
            echo        Or install Git Bash for the full auto-fix pipeline.
        )
        echo.
    )
)

echo ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo [OK] Pipeline complete!
echo.
echo For the full pipeline with SonarQube auto-fix,
echo install Git Bash: https://git-scm.com/download/win
echo.
endlocal
exit /b 0
