@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo.
echo  ==================================================
echo    Code Push Automation -- Environment Check
echo  ==================================================
echo.

set ALL_GOOD=1
set GIT_PROVIDER=%GIT_PROVIDER%
if not defined GIT_PROVIDER set GIT_PROVIDER=gitlab
set SONAR_CHECK=0

echo [INFO] Provider: %GIT_PROVIDER%
if defined DEVFLOW_DEFAULT_AI_CLI echo [INFO] Default AI CLI: %DEVFLOW_DEFAULT_AI_CLI%
echo.

:: Required env vars
if /i "%GIT_PROVIDER%"=="github" (
    call :check_var GITHUB_TOKEN         "Required scopes: repo"
    call :check_var GITHUB_PROJECT_PATH  "e.g. myorg/my-repo"
) else (
    call :check_var GITLAB_TOKEN         "Required scopes: api, write_repository"
    call :check_var GITLAB_PROJECT_PATH  "e.g. myorg/my-repo"
)

if "%USE_SONAR%"=="1" set SONAR_CHECK=1
if not defined USE_SONAR if defined SONAR_TOKEN set SONAR_CHECK=1
if not defined USE_SONAR if defined SONAR_HOST set SONAR_CHECK=1
if not defined USE_SONAR if defined SONAR_PROJECT_KEY set SONAR_CHECK=1

if "%SONAR_CHECK%"=="1" (
    call :check_var SONAR_TOKEN       ""
    call :check_var SONAR_PROJECT_KEY "Find in SonarQube > Project > Project Information"
    call :check_var SONAR_HOST        "e.g. https://sonarqube.example.com"
)

:: Optional vars
echo [INFO] Optional config:
if /i "%GIT_PROVIDER%"=="github" (
    if defined GITHUB_HOST (echo   GITHUB_HOST  = %GITHUB_HOST%) else (echo   GITHUB_HOST  = https://github.com ^(default^))
    if defined MAIN_BRANCH (echo   MAIN_BRANCH  = %MAIN_BRANCH%) else (echo   MAIN_BRANCH  = main ^(default^))
) else (
    if defined GITLAB_HOST (echo   GITLAB_HOST  = %GITLAB_HOST%) else (echo   GITLAB_HOST  = https://gitlab.com ^(default^))
    if defined MAIN_BRANCH (echo   MAIN_BRANCH  = %MAIN_BRANCH%) else (echo   MAIN_BRANCH  = develop ^(default^))
)
if defined MAX_RETRIES     (echo   MAX_RETRIES  = %MAX_RETRIES%)   else (echo   MAX_RETRIES  = 3 ^(default^))
echo.

:: Required tools
call :check_tool git   "Git"
call :check_tool curl  "curl"

where python  >nul 2>&1 && set PYTHON_OK=1
where python3 >nul 2>&1 && set PYTHON_OK=1
if defined PYTHON_OK (
    echo [OK]   Python found
) else (
    echo [FAIL] Python not found  ^(python or python3 required^)
    set ALL_GOOD=0
)
echo.

:: Optional tools
call :check_optional_tool claude "Claude Code CLI" "npm install -g @anthropic-ai/claude-code"
call :check_optional_tool codex  "Codex CLI" "npm install -g @openai/codex"
call :check_optional_tool gemini "Gemini CLI" "npm install -g @google/gemini-cli"
echo.

:: Git repository
git rev-parse --git-dir >nul 2>&1 && (
    for /f "tokens=*" %%b in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set BRANCH=%%b
    echo [OK]   Git repository detected  ^(branch: !BRANCH!^)
) || (
    echo [FAIL] Not in a Git repository
    set ALL_GOOD=0
)
echo.

:: Summary
echo ==================================================
echo.
if %ALL_GOOD%==1 (
    echo [OK]  All required dependencies are configured!
    echo.
    echo Run the pipeline with:  code-push push
) else (
    echo [FAIL] Some required configuration is missing.
    echo        Run:  code-push setup
    exit /b 1
)
echo.
endlocal
exit /b 0

:check_var
    set _VAR=%~1
    set _HINT=%~2
    if defined %_VAR% (
        echo [OK]   %_VAR% is set
    ) else (
        echo [FAIL] %_VAR% is not set
        if not "%_HINT%"=="" echo        %_HINT%
        echo        setx %_VAR% "your-value"
        set ALL_GOOD=0
    )
    echo.
    exit /b

:check_tool
    set _TOOL=%~1
    set _LABEL=%~2
    where %_TOOL% >nul 2>&1 && (
        echo [OK]   %_LABEL% found
    ) || (
        echo [FAIL] %_LABEL% not found
        set ALL_GOOD=0
    )
    echo.
    exit /b

:check_optional_tool
    set _TOOL=%~1
    set _LABEL=%~2
    set _INSTALL=%~3
    where %_TOOL% >nul 2>&1 && (
        echo [OK]   %_LABEL% found
    ) || (
        echo [WARN] %_LABEL% not found
        echo        Install with: %_INSTALL%
    )
    exit /b
