@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

cls
echo.
echo   ====================================================
echo.
echo     devflow-cli -- First-Time Setup Wizard
echo.
echo   ====================================================
echo.
echo   All tokens are saved as permanent user environment variables.
echo   They are NEVER written to git.
echo.
echo   Project-specific settings (branch, SonarQube key, test runner)
echo   are configured per-project via: devflow project-setup
echo.

:: Current status
echo   Current Configuration:
echo.
call :show_status GIT_PROVIDER
call :show_status GITLAB_TOKEN
call :show_status GITHUB_TOKEN
call :show_status GITLAB_HOST
call :show_status GITHUB_HOST
call :show_status GITLAB_PROJECT_PATH
call :show_status GITHUB_PROJECT_PATH
call :show_status USE_SONAR
call :show_status SONAR_TOKEN
call :show_status SONAR_HOST
call :show_status DEVFLOW_DEFAULT_AI_CLI
echo.

set /p START_REPLY="  Start setup? (Y/n): "
if /i "%START_REPLY%"=="n" (echo   Setup cancelled. & exit /b 0)
echo.

:: Step 1: Git provider and host
echo   ---- Step 1 - Git Provider -----------------------------------
echo.

:: Auto-detect host and project path from git remote
set AUTO_GIT_HOST=
set AUTO_PROJECT_PATH=
set AUTO_PROVIDER=
for /f "tokens=*" %%r in ('git remote get-url origin 2^>nul') do set REMOTE_URL=%%r

if defined REMOTE_URL (
    set REMOTE_CLEAN=!REMOTE_URL:.git=!
    echo !REMOTE_CLEAN! | findstr /r "^https://" >nul 2>&1 && (
        set _tmp=!REMOTE_CLEAN:https://=!
        for /f "tokens=1* delims=/" %%h in ("!_tmp!") do (
            set AUTO_GIT_HOST=https://%%h
            set AUTO_PROJECT_PATH=%%i
        )
    )
    if not defined AUTO_GIT_HOST (
        for /f "tokens=1,2 delims=:" %%h in ("!REMOTE_CLEAN!") do (
            echo %%h | findstr /r "^git@" >nul 2>&1 && (
                set _host=%%h
                set AUTO_GIT_HOST=https://!_host:git@=!
                set AUTO_PROJECT_PATH=%%i
            )
        )
    )
    if defined AUTO_GIT_HOST (
        echo !AUTO_GIT_HOST! | findstr /i "github.com" >nul 2>&1 && (
            set AUTO_PROVIDER=github
        ) || (
            set AUTO_PROVIDER=gitlab
        )
        echo   Detected provider: !AUTO_PROVIDER!
        echo   Detected host: !AUTO_GIT_HOST!
        if defined AUTO_PROJECT_PATH echo   Detected project path: !AUTO_PROJECT_PATH!
    )
    echo.
)

:: Git provider
if defined GIT_PROVIDER (
    echo   [SET] GIT_PROVIDER = %GIT_PROVIDER%
    set NEW_GIT_PROVIDER=%GIT_PROVIDER%
) else (
    set /p NEW_GIT_PROVIDER="  Git provider (gitlab/github) [!AUTO_PROVIDER!]: "
    if "!NEW_GIT_PROVIDER!"=="" (
        if defined AUTO_PROVIDER (
            set NEW_GIT_PROVIDER=!AUTO_PROVIDER!
        ) else (
            set NEW_GIT_PROVIDER=gitlab
        )
    )
)
echo.

:: Step 2: Host URL
if /i "!NEW_GIT_PROVIDER!"=="github" (
    echo   ---- Step 2 - GitHub Host ------------------------------------
    echo.
    if defined GITHUB_HOST (
        echo   [SET] GITHUB_HOST = %GITHUB_HOST%
        set NEW_GIT_HOST=%GITHUB_HOST%
    ) else (
        set /p NEW_GIT_HOST="  GitHub Host URL [!AUTO_GIT_HOST!]: "
        if "!NEW_GIT_HOST!"=="" (
            if defined AUTO_GIT_HOST (
                set NEW_GIT_HOST=!AUTO_GIT_HOST!
            ) else (
                set NEW_GIT_HOST=https://github.com
            )
        )
    )
    if defined GITHUB_PROJECT_PATH (
        echo   [SET] GITHUB_PROJECT_PATH = %GITHUB_PROJECT_PATH%
        set NEW_PROJECT_PATH=%GITHUB_PROJECT_PATH%
    ) else (
        set /p NEW_PROJECT_PATH="  Project path (org/repo) [!AUTO_PROJECT_PATH!]: "
        if "!NEW_PROJECT_PATH!"=="" set NEW_PROJECT_PATH=!AUTO_PROJECT_PATH!
    )
) else (
    echo   ---- Step 2 - GitLab Host ------------------------------------
    echo.
    if defined GITLAB_HOST (
        echo   [SET] GITLAB_HOST = %GITLAB_HOST%
        set NEW_GIT_HOST=%GITLAB_HOST%
    ) else (
        if defined AUTO_GIT_HOST (
            set /p NEW_GIT_HOST="  GitLab Host URL [!AUTO_GIT_HOST!]: "
            if "!NEW_GIT_HOST!"=="" set NEW_GIT_HOST=!AUTO_GIT_HOST!
        ) else (
            set /p NEW_GIT_HOST="  GitLab Host URL [https://gitlab.com]: "
            if "!NEW_GIT_HOST!"=="" set NEW_GIT_HOST=https://gitlab.com
        )
    )
    if defined GITLAB_PROJECT_PATH (
        echo   [SET] GITLAB_PROJECT_PATH = %GITLAB_PROJECT_PATH%
        set NEW_PROJECT_PATH=%GITLAB_PROJECT_PATH%
    ) else (
        set /p NEW_PROJECT_PATH="  Project path (org/repo) [!AUTO_PROJECT_PATH!]: "
        if "!NEW_PROJECT_PATH!"=="" set NEW_PROJECT_PATH=!AUTO_PROJECT_PATH!
    )
)
echo.

:: Step 3: Token
if /i "!NEW_GIT_PROVIDER!"=="github" (
    echo   ---- Step 3 - GitHub Personal Access Token --------------------
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
    echo   ---- Step 3 - GitLab Personal Access Token --------------------
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

:: Step 4: SonarQube token and host (global only)
echo   ---- Step 4 - SonarQube (optional) -----------------------------
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

:: Step 5: AI CLI detection and install
echo   ---- Step 5 - AI Coding CLI ------------------------------------
echo.

call :detect_ai_clis

if "!AI_INSTALLED_COUNT!"=="0" (
    echo   [WARN] No supported AI coding CLI detected.
    echo          Supported: Claude Code, Codex, Gemini
    echo.
    set /p INSTALL_AI_REPLY="  Install one or more AI CLIs with npm now? (Y/n): "
    if /i not "!INSTALL_AI_REPLY!"=="n" call :install_ai_loop
) else (
    echo   Detected AI CLIs:
    if defined HAS_CLAUDE echo     [OK] Claude Code CLI
    if defined HAS_CODEX  echo     [OK] Codex CLI
    if defined HAS_GEMINI echo     [OK] Gemini CLI
    echo.
    set /p INSTALL_MORE_AI="  Install another AI CLI with npm? (y/N): "
    if /i "!INSTALL_MORE_AI!"=="y" call :install_ai_loop
)

call :detect_ai_clis
set NEW_DEFAULT_AI_CLI=

if not "!AI_INSTALLED_COUNT!"=="0" (
    call :select_default_ai_cli
    if defined NEW_DEFAULT_AI_CLI (
        echo.
        echo   [OK] Default AI CLI = !NEW_DEFAULT_AI_CLI!
    )
) else (
    echo   [INFO] No AI CLI selected yet.
    echo          Install later, then set DEVFLOW_DEFAULT_AI_CLI to claude, codex, or gemini.
)
echo.

:: Step 6: Save using setx
echo   ---- Step 6 - Saving permanent environment variables -----------
echo.

call :save_var GIT_PROVIDER "!NEW_GIT_PROVIDER!"
call :save_var USE_SONAR    "!NEW_USE_SONAR!"
call :save_var DEVFLOW_DEFAULT_AI_CLI "!NEW_DEFAULT_AI_CLI!"

if /i "!NEW_GIT_PROVIDER!"=="github" (
    call :save_var GITHUB_HOST  "!NEW_GIT_HOST!"
    call :save_var GITHUB_PROJECT_PATH "!NEW_PROJECT_PATH!"
    call :save_var GITHUB_TOKEN "!NEW_GIT_TOKEN!"
) else (
    call :save_var GITLAB_HOST  "!NEW_GIT_HOST!"
    call :save_var GITLAB_PROJECT_PATH "!NEW_PROJECT_PATH!"
    call :save_var GITLAB_TOKEN "!NEW_GIT_TOKEN!"
)

if "!NEW_USE_SONAR!"=="1" (
    call :save_var SONAR_HOST  "!NEW_SONAR_HOST!"
    call :save_var SONAR_TOKEN "!NEW_SONAR_TOKEN!"
)

echo.
echo   ====================================================
echo     Setup complete!
echo   ====================================================
echo.
echo   Open a NEW terminal for changes to take effect, then run:
echo.
echo     devflow project-setup   -- configure this project (branch, key, tests)
echo     devflow check           -- verify everything is configured
echo     devflow push            -- run the full pipeline
echo     devflow init            -- install the git pre-push hook
if defined NEW_DEFAULT_AI_CLI echo     !NEW_DEFAULT_AI_CLI!                -- open your default AI coding CLI
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
        set "%_NAME%=%_VAL%"
        echo   [OK] %_NAME% saved.
    ) || (
        echo   [FAIL] Could not save %_NAME% - try running as Administrator.
    )
    exit /b

:detect_ai_clis
    set HAS_CLAUDE=
    set HAS_CODEX=
    set HAS_GEMINI=
    set AI_INSTALLED_COUNT=0
    where claude >nul 2>&1 && (
        set HAS_CLAUDE=1
        set /a AI_INSTALLED_COUNT+=1
    )
    where codex >nul 2>&1 && (
        set HAS_CODEX=1
        set /a AI_INSTALLED_COUNT+=1
    )
    where gemini >nul 2>&1 && (
        set HAS_GEMINI=1
        set /a AI_INSTALLED_COUNT+=1
    )
    exit /b

:install_ai_loop
:: loop label for repeated installs
:install_ai_menu
    echo.
    echo     1) Claude Code CLI
    echo     2) Codex CLI
    echo     3) Gemini CLI
    echo     4) Done
    echo.
    set /p AI_MENU_CHOICE="  Install which CLI with npm? [1-4]: "

    if "!AI_MENU_CHOICE!"=="1" call :install_ai_cli claude
    if "!AI_MENU_CHOICE!"=="2" call :install_ai_cli codex
    if "!AI_MENU_CHOICE!"=="3" call :install_ai_cli gemini
    if "!AI_MENU_CHOICE!"=="4" exit /b
    if "!AI_MENU_CHOICE!"=="" exit /b

    if "!AI_MENU_CHOICE!" NEQ "1" if "!AI_MENU_CHOICE!" NEQ "2" if "!AI_MENU_CHOICE!" NEQ "3" if "!AI_MENU_CHOICE!" NEQ "4" (
        echo   [FAIL] Invalid choice. Enter 1, 2, 3, or 4.
    )
    goto :install_ai_menu

:install_ai_cli
    set AGENT=%~1
    set PACKAGE=
    set LABEL=
    if /i "%AGENT%"=="claude" (
        set PACKAGE=@anthropic-ai/claude-code
        set LABEL=Claude Code CLI
    )
    if /i "%AGENT%"=="codex" (
        set PACKAGE=@openai/codex
        set LABEL=Codex CLI
    )
    if /i "%AGENT%"=="gemini" (
        set PACKAGE=@google/gemini-cli
        set LABEL=Gemini CLI
    )

    where npm >nul 2>&1 || (
        echo   [FAIL] npm is not available on this machine.
        echo          Install Node.js, then run: npm install -g !PACKAGE!
        exit /b
    )

    echo   Installing !LABEL! with npm...
    call npm install -g !PACKAGE!
    if errorlevel 1 (
        echo   [WARN] Install failed for !LABEL!
        echo          Manual install: npm install -g !PACKAGE!
    ) else (
        echo   [OK] Installed !LABEL!
    )
    exit /b

:select_default_ai_cli
    echo   Select the default AI CLI for commit messages and auto-fix:
    set MENU_INDEX=0

    if defined HAS_CLAUDE (
        set /a MENU_INDEX+=1
        set AI_OPTION_!MENU_INDEX!=claude
        if /i "%DEVFLOW_DEFAULT_AI_CLI%"=="claude" (
            echo     !MENU_INDEX!^) Claude Code CLI ^(current default^)
        ) else (
            echo     !MENU_INDEX!^) Claude Code CLI
        )
    )

    if defined HAS_CODEX (
        set /a MENU_INDEX+=1
        set AI_OPTION_!MENU_INDEX!=codex
        if /i "%DEVFLOW_DEFAULT_AI_CLI%"=="codex" (
            echo     !MENU_INDEX!^) Codex CLI ^(current default^)
        ) else (
            echo     !MENU_INDEX!^) Codex CLI
        )
    )

    if defined HAS_GEMINI (
        set /a MENU_INDEX+=1
        set AI_OPTION_!MENU_INDEX!=gemini
        if /i "%DEVFLOW_DEFAULT_AI_CLI%"=="gemini" (
            echo     !MENU_INDEX!^) Gemini CLI ^(current default^)
        ) else (
            echo     !MENU_INDEX!^) Gemini CLI
        )
    )

    echo.
    set /p AI_DEFAULT_CHOICE="  Choice [1-!MENU_INDEX!]: "
    if "!AI_DEFAULT_CHOICE!"=="" (
        if defined DEVFLOW_DEFAULT_AI_CLI (
            set NEW_DEFAULT_AI_CLI=%DEVFLOW_DEFAULT_AI_CLI%
        )
        exit /b
    )

    call set NEW_DEFAULT_AI_CLI=%%AI_OPTION_!AI_DEFAULT_CHOICE!%%
    if not defined NEW_DEFAULT_AI_CLI (
        echo   [FAIL] Invalid choice.
        goto :select_default_ai_cli
    )
    exit /b
