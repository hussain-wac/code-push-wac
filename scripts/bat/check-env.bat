@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo.
echo  ╔══════════════════════════════════════════════════╗
echo  ║     Code Push Automation -- Environment Check   ║
echo  ╚══════════════════════════════════════════════════╝
echo.

set ALL_GOOD=1

:: ── Required env vars ────────────────────────────────────────────────────────
call :check_var GITLAB_TOKEN         "Required scopes: api, write_repository"
call :check_var SONAR_TOKEN          ""
call :check_var GITLAB_PROJECT_PATH  "e.g. myorg/my-repo"
call :check_var SONAR_PROJECT_KEY    "Find in SonarQube > Project > Project Information"
call :check_var SONAR_HOST           "e.g. https://sonarqube.example.com"

:: ── Optional vars ─────────────────────────────────────────────────────────────
echo [INFO] Optional config:
if defined GITLAB_HOST     (echo   GITLAB_HOST  = %GITLAB_HOST%) else (echo   GITLAB_HOST  = https://gitlab.com ^(default^))
if defined MAIN_BRANCH     (echo   MAIN_BRANCH  = %MAIN_BRANCH%)  else (echo   MAIN_BRANCH  = develop ^(default^))
if defined MAX_RETRIES     (echo   MAX_RETRIES  = %MAX_RETRIES%)   else (echo   MAX_RETRIES  = 3 ^(default^))
echo.

:: ── Required tools ─────────────────────────────────────────────────────────────
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

:: ── Optional tools ─────────────────────────────────────────────────────────────
where claude >nul 2>&1 && (
    echo [OK]   Claude Code CLI found
) || (
    echo [WARN] Claude Code CLI not found
    echo        Install from: https://claude.ai/claude-code
)
echo.

:: ── Git repository ─────────────────────────────────────────────────────────────
git rev-parse --git-dir >nul 2>&1 && (
    for /f "tokens=*" %%b in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set BRANCH=%%b
    echo [OK]   Git repository detected  ^(branch: !BRANCH!^)
) || (
    echo [FAIL] Not in a Git repository
    set ALL_GOOD=0
)
echo.

:: ── Summary ────────────────────────────────────────────────────────────────────
echo ════════════════════════════════════════════════════
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
