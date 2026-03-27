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

:: ── Current status ─────────────────────────────────────────────────────────────
echo   Current Configuration:
echo.
call :show_status GITLAB_TOKEN
call :show_status SONAR_TOKEN
call :show_status GITLAB_HOST
call :show_status GITLAB_PROJECT_PATH
call :show_status SONAR_HOST
call :show_status SONAR_PROJECT_KEY
call :show_status MAIN_BRANCH
echo.

set /p START_REPLY="  Start setup? (Y/n): "
if /i "%START_REPLY%"=="n" (echo   Setup cancelled. & exit /b 0)
echo.

:: ── Step 1: Auto-detect from git remote ───────────────────────────────────────
echo   ──── Step 1 - GitLab (auto-detected from git remote) ─────────
echo.

set AUTO_GITLAB_HOST=
set AUTO_PROJECT_PATH=

for /f "tokens=*" %%r in ('git remote get-url origin 2^>nul') do set REMOTE_URL=%%r

if defined REMOTE_URL (
    :: Try to parse HTTPS URL: https://gitlab.example.com/org/repo.git
    echo %REMOTE_URL% | findstr /r "^https://" >nul 2>&1 && (
        :: Extract host: strip https:// and take first segment
        set _tmp=%REMOTE_URL:https://=%
        for /f "tokens=1 delims=/" %%h in ("!_tmp!") do set AUTO_GITLAB_HOST=https://%%h
        :: Extract path: everything after the host, strip .git
        set _path=!_tmp!
        for /f "tokens=1 delims=/" %%h in ("!_path!") do set _path=!_path:%%h/=!
        set AUTO_PROJECT_PATH=!_path:.git=!
        echo   Detected GitLab Host:   !AUTO_GITLAB_HOST!
        echo   Detected Project Path:  !AUTO_PROJECT_PATH!
    )
    echo.
)

:: GitLab Host
if defined GITLAB_HOST (
    echo   [SET] GITLAB_HOST = %GITLAB_HOST%
    set NEW_GITLAB_HOST=%GITLAB_HOST%
) else (
    if defined AUTO_GITLAB_HOST (
        set /p NEW_GITLAB_HOST="  GitLab Host URL [!AUTO_GITLAB_HOST!]: "
        if "!NEW_GITLAB_HOST!"=="" set NEW_GITLAB_HOST=!AUTO_GITLAB_HOST!
    ) else (
        set /p NEW_GITLAB_HOST="  GitLab Host URL [https://gitlab.com]: "
        if "!NEW_GITLAB_HOST!"=="" set NEW_GITLAB_HOST=https://gitlab.com
    )
)

:: Project path
if defined GITLAB_PROJECT_PATH (
    echo   [SET] GITLAB_PROJECT_PATH = %GITLAB_PROJECT_PATH%
    set NEW_PROJECT_PATH=%GITLAB_PROJECT_PATH%
) else (
    if defined AUTO_PROJECT_PATH (
        set /p NEW_PROJECT_PATH="  Project path (org/repo) [!AUTO_PROJECT_PATH!]: "
        if "!NEW_PROJECT_PATH!"=="" set NEW_PROJECT_PATH=!AUTO_PROJECT_PATH!
    ) else (
        set /p NEW_PROJECT_PATH="  Project path (e.g. myorg/my-app): "
    )
)

:: Main branch
if defined MAIN_BRANCH (
    echo   [SET] MAIN_BRANCH = %MAIN_BRANCH%
    set NEW_MAIN_BRANCH=%MAIN_BRANCH%
) else (
    set /p NEW_MAIN_BRANCH="  Main branch [develop]: "
    if "!NEW_MAIN_BRANCH!"=="" set NEW_MAIN_BRANCH=develop
)

echo.

:: ── Step 2: GitLab Token ───────────────────────────────────────────────────────
echo   ──── Step 2 - GitLab Personal Access Token ────────────────────
echo.
echo   Generate at: !NEW_GITLAB_HOST!/-/user_settings/personal_access_tokens
echo   Required scopes: api, write_repository
echo.
if defined GITLAB_TOKEN (
    echo   [SET] GITLAB_TOKEN already configured.
    set NEW_GITLAB_TOKEN=%GITLAB_TOKEN%
) else (
    set /p NEW_GITLAB_TOKEN="  Paste GitLab token: "
    if defined NEW_GITLAB_TOKEN (echo   [OK] Token accepted.) else (echo   [SKIP] Skipped.)
)
echo.

:: ── Step 3: SonarQube ─────────────────────────────────────────────────────────
echo   ──── Step 3 - SonarQube ────────────────────────────────────────
echo.
if defined SONAR_HOST (
    echo   [SET] SONAR_HOST = %SONAR_HOST%
    set NEW_SONAR_HOST=%SONAR_HOST%
) else (
    set /p NEW_SONAR_HOST="  SonarQube host URL (e.g. https://sonarqube.example.com): "
)
echo.

echo   Find your project key in SonarQube ^> Project ^> Project Information
echo.
if defined SONAR_PROJECT_KEY (
    echo   [SET] SONAR_PROJECT_KEY = %SONAR_PROJECT_KEY%
    set NEW_SONAR_KEY=%SONAR_PROJECT_KEY%
) else (
    set /p NEW_SONAR_KEY="  SonarQube project key: "
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
echo.

:: ── Step 4: Save using setx ───────────────────────────────────────────────────
echo   ──── Step 4 - Saving permanent environment variables ──────────
echo.

call :save_var GITLAB_HOST        "!NEW_GITLAB_HOST!"
call :save_var GITLAB_TOKEN       "!NEW_GITLAB_TOKEN!"
call :save_var GITLAB_PROJECT_PATH "!NEW_PROJECT_PATH!"
call :save_var MAIN_BRANCH        "!NEW_MAIN_BRANCH!"
call :save_var SONAR_HOST         "!NEW_SONAR_HOST!"
call :save_var SONAR_PROJECT_KEY  "!NEW_SONAR_KEY!"
call :save_var SONAR_TOKEN        "!NEW_SONAR_TOKEN!"

echo.
echo   ╔════════════════════════════════════════════════════╗
echo   ║   Setup complete!                                  ║
echo   ╚════════════════════════════════════════════════════╝
echo.
echo   Open a NEW terminal for changes to take effect, then run:
echo.
echo     devflow check    -- verify everything is configured
echo     devflow push     -- run the full pipeline
echo     devflow init     -- install the git pre-push hook
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
