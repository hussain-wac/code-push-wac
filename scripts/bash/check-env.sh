#!/bin/bash

# Environment Check — verifies all required tokens and tools are configured

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     wac-devflow — Environment Check             ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

ALL_GOOD=true

GIT_PROVIDER="${GIT_PROVIDER:-gitlab}"
USE_SONAR="${USE_SONAR:-}"

echo -e "${BLUE}Git Provider:${NC} ${CYAN}${GIT_PROVIDER}${NC}"
if [ -n "$USE_SONAR" ]; then
    if [ "$USE_SONAR" = "1" ]; then
        echo -e "${BLUE}SonarQube:${NC}    ${GREEN}enabled${NC}"
    else
        echo -e "${BLUE}SonarQube:${NC}    ${YELLOW}disabled${NC}"
    fi
else
    echo -e "${BLUE}SonarQube:${NC}    ${YELLOW}not configured (run: devflow setup)${NC}"
fi
echo ""

# ── Helpers ───────────────────────────────────────────────────────────────────
check_var() {
    local VAR_NAME="$1"
    local HINT="$2"
    local VALUE="${!VAR_NAME}"

    if [ -z "$VALUE" ]; then
        echo -e "${RED}✗ $VAR_NAME not set${NC}"
        [ -n "$HINT" ] && echo -e "  ${HINT}"
        echo ""
        ALL_GOOD=false
    else
        if [[ "$VAR_NAME" == *TOKEN* ]]; then
            echo -e "${GREEN}✓ $VAR_NAME is set${NC}"
        else
            echo -e "${GREEN}✓ $VAR_NAME = ${CYAN}${VALUE}${NC}"
        fi
        echo ""
    fi
}

check_tool() {
    local TOOL="$1"
    local LABEL="${2:-$1}"

    if ! command -v "$TOOL" &> /dev/null; then
        echo -e "${RED}✗ $LABEL not found${NC}"
        echo ""
        ALL_GOOD=false
    else
        echo -e "${GREEN}✓ $($TOOL --version 2>&1 | head -1)${NC}"
        echo ""
    fi
}

# ── Provider-specific required vars ───────────────────────────────────────────
echo -e "${BLUE}── Git provider config ──────────────────────────────────${NC}"
echo ""

if [ "$GIT_PROVIDER" = "github" ]; then
    check_var "GITHUB_TOKEN"        "Required scopes: repo (or workflow for Actions)"
    check_var "GITHUB_PROJECT_PATH" "e.g. myorg/my-repo"
    echo -e "${BLUE}Optional:${NC}"
    echo -e "  GITHUB_HOST  = ${GITHUB_HOST:-https://github.com (default)}"
    echo -e "  MAIN_BRANCH  = ${MAIN_BRANCH:-main (default)}"
else
    check_var "GITLAB_TOKEN"        "Required scopes: api, write_repository"
    check_var "GITLAB_PROJECT_PATH" "e.g. myorg/my-repo"
    echo -e "${BLUE}Optional:${NC}"
    echo -e "  GITLAB_HOST  = ${GITLAB_HOST:-https://gitlab.com (default)}"
    echo -e "  MAIN_BRANCH  = ${MAIN_BRANCH:-develop (default)}"
fi

echo ""

# ── SonarQube vars (only if enabled) ─────────────────────────────────────────
# Determine if sonar should be checked:
# - USE_SONAR=1: check
# - USE_SONAR=0: skip
# - USE_SONAR not set but SONAR vars exist: check (backward compat)
SONAR_CHECK=false
if [ "$USE_SONAR" = "1" ]; then
    SONAR_CHECK=true
elif [ "$USE_SONAR" = "0" ]; then
    SONAR_CHECK=false
elif [ -n "$SONAR_TOKEN" ] || [ -n "$SONAR_HOST" ] || [ -n "$SONAR_PROJECT_KEY" ]; then
    SONAR_CHECK=true
fi

if [ "$SONAR_CHECK" = "true" ]; then
    echo -e "${BLUE}── SonarQube config ─────────────────────────────────────${NC}"
    echo ""
    check_var "SONAR_TOKEN"       ""
    check_var "SONAR_HOST"        "e.g. https://sonarqube.example.com"
    check_var "SONAR_PROJECT_KEY" "Find in SonarQube → Project → Project Information"
    echo -e "${BLUE}Optional:${NC}"
    echo -e "  MAX_RETRIES  = ${MAX_RETRIES:-3 (default)}"
    echo ""
else
    echo -e "${YELLOW}  SonarQube is disabled for this project.${NC}"
    echo -e "  ${DIM}Run 'devflow setup' to enable it.${NC}"
    echo ""
fi

# ── Required tools ─────────────────────────────────────────────────────────────
echo -e "${BLUE}── Tools ────────────────────────────────────────────────${NC}"
echo ""
check_tool "git"  "Git"
check_tool "curl" "curl"

# Python (python3 or python)
if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
    echo -e "${RED}✗ Python not found (python3 or python required)${NC}"
    echo ""
    ALL_GOOD=false
else
    PYTHON_CMD=$(command -v python3 2>/dev/null || command -v python)
    echo -e "${GREEN}✓ $($PYTHON_CMD --version 2>&1)${NC}"
    echo ""
fi

# Claude (optional)
echo -e "${BLUE}Claude Code CLI${NC} ${DIM}(optional — required for AI features)${NC}"
if ! command -v claude &> /dev/null; then
    echo -e "${YELLOW}⚠  Claude Code CLI not found${NC}"
    echo "   Install from: https://claude.ai/claude-code"
    echo "   Needed for: AI commit messages and SonarQube auto-fix"
    echo ""
else
    echo -e "${GREEN}✓ Claude Code CLI is installed${NC}"
    echo ""
fi

# ── Git repository ─────────────────────────────────────────────────────────────
echo -e "${BLUE}── Git repository ───────────────────────────────────────${NC}"
echo ""
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}✗ Not in a Git repository${NC}"
    echo ""
    ALL_GOOD=false
else
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    echo -e "${GREEN}✓ Git repository detected${NC}"
    echo "  Current branch: $CURRENT_BRANCH"
    echo ""
fi

# ── Summary ────────────────────────────────────────────────────────────────────
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""

if [ "$ALL_GOOD" = true ]; then
    echo -e "${GREEN}✓ All required dependencies are configured!${NC}"
    echo ""
    echo "Run the pipeline with:"
    echo -e "  ${CYAN}devflow push${NC}"
    echo ""
else
    echo -e "${RED}✗ Some required configuration is missing${NC}"
    echo ""
    echo "Fix the issues above, then run:"
    echo -e "  ${CYAN}devflow setup${NC}  — interactive setup wizard"
    echo ""
    exit 1
fi
