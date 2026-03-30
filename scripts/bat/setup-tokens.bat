@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

cls
echo.
echo   ╔════════════════════════════════════════════════════╗
echo   ║                                                    ║
echo   ║   🔐  wac-devflow -- First-Time Setup Wizard      ║
echo   ║                                                    ║
echo   ╚════════════════════════════════════════════════════╝
echo.
echo   All tokens are saved as permanent user environment variables.
echo   They are NEVER written to git.
echo.
echo   Project-specific settings (branch, SonarQube key, test runner)
echo   are configured per-project via: devflow project-setup
echo.

:: ── Current status ─────────────────────────────────────────────────────────────
echo   Current Configuration:
echo.
call :show_status GIT_PROVIDER
call :show_status GITLAB_TOKEN
call :show_status GITHUB_TOKEN
call :show_status GITLAB_HOST
call :show_status GITHUB_HOST
call :show_status USE_SONAR
call :show_status SONAR_TOKEN
call :show_status SONAR_HOST
echo.

set /p START_REPLY="  Start setup? (Y/n): "
if /i "%START_REPLY%"=="n" (echo   Setup cancelled. & exit /b 0)
echo.

:: ── Step 1: Git provider & host ───────────────────────────────────────────────
echo   ──── Step 1 - Git Provider ────────────────────────────────────
echo.

:: Auto-detect host from git remote
set AUTO_GITLAB_HOST=
for /f "tokens=*" %%r in ('git remote get-url origin 2^>nul') do set REMOTE_URL=%%r

if defined REMOTE_URL (
    echo %REMOTE_URL% | findstr /r "^https://" >nul 2>&1 && (
        set _tmp=%REMOTE_URL:https://=%
        for /f "tokens=1 delims=/" %%h in ("!_tmp!") do set AUTO_GITLAB_HOST=https://%%h
        echo   Detected host: !AUTO_GITLAB_HOST!
    )
    echo.
)

:: Git provider
if defined GIT_PROVIDER (
    echo   [SET] GIT_PROVIDER = %GIT_PROVIDER%
    set NEW_GIT_PROVIDER=%GIT_PROVIDER%
) else (
    set /p NEW_GIT_PROVIDER="  Git provider (gitlab/github) [gitlab]: "
    if "!NEW_GIT_PROVIDER!"=="" set NEW_GIT_PROVIDER=gitlab
)
echo.

:: ── Step 2: Host URL ──────────────────────────────────────────────────────────
if /i "!NEW_GIT_PROVIDER!"=="github" (
    echo   ──── Step 2 - GitHub Host ─────────────────────────────────────
    echo.
    if defined GITHUB_HOST (
        echo   [SET] GITHUB_HOST = %GITHUB_HOST%
        set NEW_GIT_HOST=%GITHUB_HOST%
    ) else (
        set /p NEW_GIT_HOST="  GitHub Host URL [https://github.com]: "
        if "!NEW_GIT_HOST!"=="" set NEW_GIT_HOST=https://github.com
    )
) else (
    echo   ──── Step 2 - GitLab Host ─────────────────────────────────────
    echo.
    if defined GITLAB_HOST (
        echo   [SET] GITLAB_HOST = %GITLAB_HOST%
        set NEW_GIT_HOST=%GITLAB_HOST%
    ) else (
        if defined AUTO_GITLAB_HOST (
            set /p NEW_GIT_HOST="  GitLab Host URL [!AUTO_GITLAB_HOST!]: "
            if "!NEW_GIT_HOST!"=="" set NEW_GIT_HOST=!AUTO_GITLAB_HOST!
        ) else (
            set /p NEW_GIT_HOST="  GitLab Host URL [https://gitlab.com]: "
            if "!NEW_GIT_HOST!"=="" set NEW_GIT_HOST=https://gitlab.com
        )
    )
)
echo.

:: ── Step 3: Token ─────────────────────────────────────────────────────────────
if /i "!NEW_GIT_PROVIDER!"=="github" (
    echo   ──── Step 3 - GitHub Personal Access Token ────────────────────
    echo.
    echo   Generate at: !NEW_GIT_HOST!/settings/tokens/new
    echo   Required scopes: repo (or workflow for Actions)
    echo.
    if defined GITHUB_TOKEN (
        echo   [SET] GITHUB_TOKEN already configured.
        set NEW_GIT_TOKEN=%GITHUB_TOKEN%
    ) else (
        set /p NEW_GIT_TOKEN="  Paste GitHub token: "
        if defined NEW_GIT_TOKEN (echo   [OK] Token accepted.) else (echo   [SKIP] Skipped.)
    )
) else (
    echo   ──── Step 3 - GitLab Personal Access Token ────────────────────
    echo.
    echo   Generate at: !NEW_GIT_HOST!/-/user_settings/personal_access_tokens
    echo   Required scopes: api, write_repository
    echo.
    if defined GITLAB_TOKEN (
        echo   [SET] GITLAB_TOKEN already configured.
        set NEW_GIT_TOKEN=%GITLAB_TOKEN%
    ) else (
        set /p NEW_GIT_TOKEN="  Paste GitLab token: "
        if defined NEW_GIT_TOKEN (echo   [OK] Token accepted.) else (echo   [SKIP] Skipped.)
    )
)
echo.

:: ── Step 4: SonarQube token & host (global only) ──────────────────────────────
echo   ──── Step 4 - SonarQube (optional) ────────────────────────────
echo.
echo   Skip this if your project doesn't use SonarQube.
echo   (SonarQube project key is set per-project via: devflow project-setup)
echo.

set /p SONAR_REPLY="  Does this machine use SonarQube? (y/N): "
if /i "!SONAR_REPLY!"=="y" (
    if defined SONAR_HOST (
        echo   [SET] SONAR_HOST = %SONAR_HOST%
        set NEW_SONAR_HOST=%SONAR_HOST%
    ) else (
        set /p NEW_SONAR_HOST="  SonarQube host URL (e.g. https://sonarqube.example.com): "
    )
    echo.

    if defined SONAR_TOKEN (
        echo   [SET] SONAR_TOKEN already configured.
        set NEW_SONAR_TOKEN=%SONAR_TOKEN%
    ) else (
        echo   Generate at: !NEW_SONAR_HOST!/account/security
        set /p NEW_SONAR_TOKEN="  Paste SonarQube token: "
        if defined NEW_SONAR_TOKEN (echo   [OK] Token accepted.) else (echo   [SKIP] Skipped.)
    )
    set NEW_USE_SONAR=1
) else (
    set NEW_USE_SONAR=0
    echo   SonarQube skipped.
)
echo.

:: ── Step 5: Save using setx ───────────────────────────────────────────────────
echo   ──── Step 5 - Saving permanent environment variables ──────────
echo.

call :save_var GIT_PROVIDER "!NEW_GIT_PROVIDER!"
call :save_var USE_SONAR    "!NEW_USE_SONAR!"

if /i "!NEW_GIT_PROVIDER!"=="github" (
    call :save_var GITHUB_HOST  "!NEW_GIT_HOST!"
    call :save_var GITHUB_TOKEN "!NEW_GIT_TOKEN!"
) else (
    call :save_var GITLAB_HOST  "!NEW_GIT_HOST!"
    call :save_var GITLAB_TOKEN "!NEW_GIT_TOKEN!"
)

if "!NEW_USE_SONAR!"=="1" (
    call :save_var SONAR_HOST  "!NEW_SONAR_HOST!"
    call :save_var SONAR_TOKEN "!NEW_SONAR_TOKEN!"
)

echo.
echo   ╔════════════════════════════════════════════════════╗
echo   ║   Setup complete!                                  ║
echo   ╚════════════════════════════════════════════════════╝
echo.
echo   Open a NEW terminal for changes to take effect, then run:
echo.
echo     devflow project-setup   -- configure this project (branch, key, tests)
echo     devflow check           -- verify everything is configured
echo     devflow push            -- run the full pipeline
echo     devflow init            -- install the git pre-push hook
echo.
endlocal
exit /b 0

:show_status
    set _VAR=%~1
    if defined %_VAR% (
        if "%_VAR:TOKEN=%"=="%_VAR%" (
            echo     [SET]   %_VAR% = !%_VAR%!
        ) else (
            echo     [SET]   %_VAR%  (configured)
        )
    ) else (
        echo     [UNSET] %_VAR%
    )
    exit /b

:save_var
    set _NAME=%~1
    set _VAL=%~2
    if "%_VAL%"=="" (exit /b)
    setx %_NAME% "%_VAL%" >nul 2>&1 && (
        echo   [OK] %_NAME% saved.
    ) || (
        echo   [FAIL] Could not save %_NAME% - try running as Administrator.
    )
    exit /b
