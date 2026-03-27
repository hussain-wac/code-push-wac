#!/bin/bash

# wac-devflow — Interactive Setup Wizard
# Auto-detects git provider & project path from git remote.
# Saves all config to the shell profile as environment variables.

# ── OS compatibility ───────────────────────────────────────────────────────────
sed_inplace() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
DIM='\033[2m'
NC='\033[0m'

# ── Helpers ────────────────────────────────────────────────────────────────────
print_step() {
    echo ""
    echo -e "${MAGENTA}  ────────────────────────────────────────────────${NC}"
    echo -e "${MAGENTA}  $1${NC}"
    echo -e "${MAGENTA}  ────────────────────────────────────────────────${NC}"
    echo ""
}

# Prompt with an optional pre-filled default.
# Usage: ask_value OUTPUT_VAR "Label" "default" secret
ask_value() {
    local -r out_var="$1"
    local -r label="$2"
    local -r default="$3"
    local -r secret="${4:-false}"
    local value=""

    if [ "$secret" = "true" ]; then
        printf "  %s: " "$label"
        read -r -s value
        echo ""
    elif [ -n "$default" ]; then
        printf "  %s [%b%s%b]: " "$label" "$DIM" "$default" "$NC"
        read -r value
        [ -z "$value" ] && value="$default"
    else
        printf "  %s: " "$label"
        read -r value
    fi

    export "$out_var"="$value"
}

# y/N question — returns 0 for yes, 1 for no
ask_yes_no() {
    local label="$1"
    local default="${2:-n}"  # default: no
    local reply
    printf "  %s " "$label"
    read -r -n 1 reply
    echo ""
    if [ -z "$reply" ]; then reply="$default"; fi
    [[ "$reply" =~ ^[Yy]$ ]]
}

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo ""
echo -e "${CYAN}  ╔════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}  ║                                                    ║${NC}"
echo -e "${CYAN}  ║   🔐  wac-devflow — First-Time Setup Wizard       ║${NC}"
echo -e "${CYAN}  ║                                                    ║${NC}"
echo -e "${CYAN}  ╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  All tokens are saved to your shell profile — ${YELLOW}never${NC} to git."
echo ""

# ── Detect shell profile ──────────────────────────────────────────────────────
SHELL_TYPE=$(basename "$SHELL")
case "$SHELL_TYPE" in
    zsh)  PROFILE_FILE="$HOME/.zshrc"  ;;
    bash) PROFILE_FILE="$HOME/.bashrc" ;;
    *)    PROFILE_FILE="$HOME/.profile" ;;
esac

echo -e "  Shell:   ${CYAN}$SHELL_TYPE${NC}"
echo -e "  Profile: ${CYAN}$PROFILE_FILE${NC}"
echo ""

# ── Current configuration status ─────────────────────────────────────────────
echo -e "  ${BLUE}Current configuration:${NC}"

show_var() {
    local VAR="$1"
    if [ -n "${!VAR}" ]; then
        if [[ "$VAR" == *TOKEN* ]]; then
            echo -e "    ${GREEN}✓${NC} $VAR  ${DIM}(already set)${NC}"
        else
            echo -e "    ${GREEN}✓${NC} $VAR = ${CYAN}${!VAR}${NC}"
        fi
    else
        echo -e "    ${RED}✗${NC} $VAR  ${DIM}(not set)${NC}"
    fi
}

show_var GIT_PROVIDER
show_var GITLAB_TOKEN
show_var GITHUB_TOKEN
show_var GITLAB_HOST
show_var GITLAB_PROJECT_PATH
show_var GITHUB_HOST
show_var GITHUB_PROJECT_PATH
show_var USE_SONAR
show_var SONAR_TOKEN
show_var SONAR_HOST
show_var SONAR_PROJECT_KEY
show_var MAIN_BRANCH
echo ""

read -r -p "  Start setup? (Y/n): " -n 1 REPLY
echo ""
[[ "$REPLY" =~ ^[Nn]$ ]] && echo "  Setup cancelled." && exit 0
echo ""

# ── Step 1: Auto-detect from git remote ───────────────────────────────────────
print_step "Step 1 — Git Provider"

PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$PROJECT_ROOT" 2>/dev/null || true

REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")

AUTO_HOST=""
AUTO_PROJECT_PATH=""
AUTO_PROVIDER=""

if [ -n "$REMOTE_URL" ]; then
    REMOTE_CLEAN="${REMOTE_URL%.git}"

    # HTTPS URL: https://host/org/repo
    if [[ "$REMOTE_CLEAN" =~ ^https://([^/]+)/(.+)$ ]]; then
        AUTO_HOST="https://${BASH_REMATCH[1]}"
        AUTO_PROJECT_PATH="${BASH_REMATCH[2]}"
    # SSH URL: git@host:org/repo
    elif [[ "$REMOTE_CLEAN" =~ ^git@([^:]+):(.+)$ ]]; then
        AUTO_HOST="https://${BASH_REMATCH[1]}"
        AUTO_PROJECT_PATH="${BASH_REMATCH[2]}"
    fi

    # Detect provider from host
    if [[ "$AUTO_HOST" == *"github.com"* ]]; then
        AUTO_PROVIDER="github"
    elif [ -n "$AUTO_HOST" ]; then
        AUTO_PROVIDER="gitlab"
    fi

    if [ -n "$AUTO_HOST" ]; then
        echo -e "  ${GREEN}✓ Detected from git remote:${NC}"
        echo -e "    Provider:      ${CYAN}$AUTO_PROVIDER${NC}"
        echo -e "    Host:          ${CYAN}$AUTO_HOST${NC}"
        echo -e "    Project Path:  ${CYAN}$AUTO_PROJECT_PATH${NC}"
        echo ""
    fi
fi

# Git provider
NEW_GIT_PROVIDER="${GIT_PROVIDER:-}"
if [ -n "$NEW_GIT_PROVIDER" ]; then
    echo -e "  ${GREEN}✓ GIT_PROVIDER already set: $NEW_GIT_PROVIDER${NC}"
else
    ask_value NEW_GIT_PROVIDER "Git provider (gitlab/github)" "${AUTO_PROVIDER:-gitlab}"
fi

# Normalize
NEW_GIT_PROVIDER=$(echo "$NEW_GIT_PROVIDER" | tr '[:upper:]' '[:lower:]')

# ── Step 2: Provider-specific config ─────────────────────────────────────────
if [ "$NEW_GIT_PROVIDER" = "github" ]; then
    print_step "Step 2 — GitHub Configuration"

    NEW_GITHUB_HOST="${GITHUB_HOST:-}"
    if [ -n "$NEW_GITHUB_HOST" ]; then
        echo -e "  ${GREEN}✓ GITHUB_HOST already set: $NEW_GITHUB_HOST${NC}"
    else
        ask_value NEW_GITHUB_HOST "GitHub Host URL" "${AUTO_HOST:-https://github.com}"
    fi

    NEW_PROJECT_PATH="${GITHUB_PROJECT_PATH:-}"
    if [ -n "$NEW_PROJECT_PATH" ]; then
        echo -e "  ${GREEN}✓ GITHUB_PROJECT_PATH already set: $NEW_PROJECT_PATH${NC}"
    else
        ask_value NEW_PROJECT_PATH "Project path (org/repo)" "$AUTO_PROJECT_PATH"
    fi

    DETECTED_MAIN=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|.*/||' || echo "")
    NEW_MAIN_BRANCH="${MAIN_BRANCH:-}"
    if [ -n "$NEW_MAIN_BRANCH" ]; then
        echo -e "  ${GREEN}✓ MAIN_BRANCH already set: $NEW_MAIN_BRANCH${NC}"
    else
        ask_value NEW_MAIN_BRANCH "Main branch" "${DETECTED_MAIN:-main}"
    fi

    print_step "Step 3 — GitHub Personal Access Token"
    echo -e "  ${BLUE}Generate at:${NC} ${NEW_GITHUB_HOST}/settings/tokens/new"
    echo -e "  ${BLUE}Required scopes:${NC} ${CYAN}repo${NC} (or ${CYAN}workflow${NC} for Actions)"
    echo ""

    NEW_GIT_TOKEN="${GITHUB_TOKEN:-}"
    if [ -n "$NEW_GIT_TOKEN" ]; then
        echo -e "  ${GREEN}✓ GITHUB_TOKEN already set${NC}"
    else
        ask_value NEW_GIT_TOKEN "Paste GitHub token (hidden)" "" "true"
        if [ -z "$NEW_GIT_TOKEN" ]; then
            echo -e "  ${YELLOW}⚠  Skipped — you can re-run setup later${NC}"
        else
            echo -e "  ${GREEN}✓ Token accepted${NC}"
        fi
    fi

else
    # GitLab (default)
    print_step "Step 2 — GitLab Configuration"

    NEW_GITLAB_HOST="${GITLAB_HOST:-}"
    if [ -n "$NEW_GITLAB_HOST" ]; then
        echo -e "  ${GREEN}✓ GITLAB_HOST already set: $NEW_GITLAB_HOST${NC}"
    else
        ask_value NEW_GITLAB_HOST "GitLab Host URL" "${AUTO_HOST:-https://gitlab.com}"
    fi

    NEW_PROJECT_PATH="${GITLAB_PROJECT_PATH:-}"
    if [ -n "$NEW_PROJECT_PATH" ]; then
        echo -e "  ${GREEN}✓ GITLAB_PROJECT_PATH already set: $NEW_PROJECT_PATH${NC}"
    else
        ask_value NEW_PROJECT_PATH "Project path (org/repo)" "$AUTO_PROJECT_PATH"
    fi

    DETECTED_MAIN=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|.*/||' || echo "")
    NEW_MAIN_BRANCH="${MAIN_BRANCH:-}"
    if [ -n "$NEW_MAIN_BRANCH" ]; then
        echo -e "  ${GREEN}✓ MAIN_BRANCH already set: $NEW_MAIN_BRANCH${NC}"
    else
        ask_value NEW_MAIN_BRANCH "Main branch" "${DETECTED_MAIN:-develop}"
    fi

    print_step "Step 3 — GitLab Personal Access Token"
    echo -e "  ${BLUE}Generate at:${NC} ${NEW_GITLAB_HOST}/-/user_settings/personal_access_tokens"
    echo -e "  ${BLUE}Required scopes:${NC} ${CYAN}api${NC}, ${CYAN}write_repository${NC}"
    echo ""

    NEW_GIT_TOKEN="${GITLAB_TOKEN:-}"
    if [ -n "$NEW_GIT_TOKEN" ]; then
        echo -e "  ${GREEN}✓ GITLAB_TOKEN already set${NC}"
    else
        ask_value NEW_GIT_TOKEN "Paste GitLab token (hidden)" "" "true"
        if [ -z "$NEW_GIT_TOKEN" ]; then
            echo -e "  ${YELLOW}⚠  Skipped — you can re-run setup later${NC}"
        else
            echo -e "  ${GREEN}✓ Token accepted${NC}"
        fi
    fi
fi

# ── Step 4: SonarQube (optional) ─────────────────────────────────────────────
SONAR_STEP_NUM=4
print_step "Step $SONAR_STEP_NUM — SonarQube (optional)"

echo -e "  SonarQube provides code quality analysis and AI auto-fix for issues."
echo -e "  ${DIM}Skip this if your project doesn't use SonarQube.${NC}"
echo ""

NEW_USE_SONAR="0"
NEW_SONAR_HOST=""
NEW_SONAR_PROJECT_KEY=""
NEW_SONAR_TOKEN=""

# If already configured, skip the question
if [ -n "$SONAR_TOKEN" ] && [ -n "$SONAR_PROJECT_KEY" ] && [ -n "$SONAR_HOST" ]; then
    echo -e "  ${GREEN}✓ SonarQube already configured${NC}"
    echo -e "    SONAR_HOST = ${CYAN}$SONAR_HOST${NC}"
    echo -e "    SONAR_PROJECT_KEY = ${CYAN}$SONAR_PROJECT_KEY${NC}"
    echo -e "    SONAR_TOKEN  ${DIM}(set)${NC}"
    NEW_USE_SONAR="1"
    NEW_SONAR_HOST="$SONAR_HOST"
    NEW_SONAR_PROJECT_KEY="$SONAR_PROJECT_KEY"
    NEW_SONAR_TOKEN="$SONAR_TOKEN"
elif [ "${USE_SONAR:-}" = "0" ]; then
    echo -e "  ${YELLOW}SonarQube is disabled for this project (USE_SONAR=0)${NC}"
    echo ""
    if ask_yes_no "Enable SonarQube now? (y/N):"; then
        NEW_USE_SONAR="1"
    else
        NEW_USE_SONAR="0"
    fi
else
    if ask_yes_no "Does this project use SonarQube? (y/N):"; then
        NEW_USE_SONAR="1"
    else
        NEW_USE_SONAR="0"
        echo -e "  ${DIM}SonarQube skipped — run setup again to enable later${NC}"
    fi
fi

if [ "$NEW_USE_SONAR" = "1" ] && [ -z "$NEW_SONAR_HOST" ]; then
    echo ""
    if [ -n "$SONAR_HOST" ]; then
        echo -e "  ${GREEN}✓ SONAR_HOST already set: $SONAR_HOST${NC}"
        NEW_SONAR_HOST="$SONAR_HOST"
    else
        ask_value NEW_SONAR_HOST "SonarQube host URL" "https://sonarqube.example.com"
    fi
    echo ""

    # Suggest project key from project path
    if [ -n "$NEW_PROJECT_PATH" ]; then
        SUGGESTED_KEY=$(echo "$NEW_PROJECT_PATH" | sed 's/\//_/g; s/-/_/g' | tr '[:upper:]' '[:lower:]')
        echo -e "  ${BLUE}Suggested key prefix:${NC} ${CYAN}${SUGGESTED_KEY}_<uniqueId>${NC}"
    fi
    echo -e "  ${BLUE}Find your full key at:${NC} ${NEW_SONAR_HOST}/dashboard"
    echo -e "  ${DIM}  Project → Project Information → Project Key${NC}"
    echo ""

    if [ -n "$SONAR_PROJECT_KEY" ]; then
        echo -e "  ${GREEN}✓ SONAR_PROJECT_KEY already set: $SONAR_PROJECT_KEY${NC}"
        NEW_SONAR_PROJECT_KEY="$SONAR_PROJECT_KEY"
    else
        ask_value NEW_SONAR_PROJECT_KEY "SonarQube project key" "${SUGGESTED_KEY:-}"
    fi
    echo ""

    if [ -n "$SONAR_TOKEN" ]; then
        echo -e "  ${GREEN}✓ SONAR_TOKEN already set${NC}"
        NEW_SONAR_TOKEN="$SONAR_TOKEN"
    else
        echo -e "  ${BLUE}Generate at:${NC} ${NEW_SONAR_HOST}/account/security"
        ask_value NEW_SONAR_TOKEN "Paste SonarQube token (hidden)" "" "true"
        if [ -z "$NEW_SONAR_TOKEN" ]; then
            echo -e "  ${YELLOW}⚠  Skipped — you can re-run setup later${NC}"
        else
            echo -e "  ${GREEN}✓ Token accepted${NC}"
        fi
    fi
fi

# ── Step 5: Save to profile ───────────────────────────────────────────────────
print_step "Step 5 — Saving to $PROFILE_FILE"

# Build list of vars to save based on provider
VALUES_TO_WRITE=()
declare -A WRITE_MAP

add_if_new() {
    local VAR_NAME="$1"
    local VAR_VAL="$2"
    local EXISTING="${!VAR_NAME}"
    if [ -n "$VAR_VAL" ] && [ "$VAR_VAL" != "$EXISTING" ]; then
        VALUES_TO_WRITE+=("$VAR_NAME")
        WRITE_MAP["$VAR_NAME"]="$VAR_VAL"
    fi
}

add_if_new "GIT_PROVIDER"   "$NEW_GIT_PROVIDER"
add_if_new "MAIN_BRANCH"    "$NEW_MAIN_BRANCH"
add_if_new "USE_SONAR"      "$NEW_USE_SONAR"

if [ "$NEW_GIT_PROVIDER" = "github" ]; then
    add_if_new "GITHUB_HOST"         "${NEW_GITHUB_HOST:-}"
    add_if_new "GITHUB_PROJECT_PATH" "$NEW_PROJECT_PATH"
    add_if_new "GITHUB_TOKEN"        "$NEW_GIT_TOKEN"
else
    add_if_new "GITLAB_HOST"         "${NEW_GITLAB_HOST:-}"
    add_if_new "GITLAB_PROJECT_PATH" "$NEW_PROJECT_PATH"
    add_if_new "GITLAB_TOKEN"        "$NEW_GIT_TOKEN"
fi

if [ "$NEW_USE_SONAR" = "1" ]; then
    add_if_new "SONAR_HOST"        "$NEW_SONAR_HOST"
    add_if_new "SONAR_PROJECT_KEY" "$NEW_SONAR_PROJECT_KEY"
    add_if_new "SONAR_TOKEN"       "$NEW_SONAR_TOKEN"
fi

if [ ${#VALUES_TO_WRITE[@]} -eq 0 ]; then
    echo -e "  ${YELLOW}Nothing new to save (all values already configured).${NC}"
    echo ""
else
    touch "$PROFILE_FILE"
    cp "$PROFILE_FILE" "$PROFILE_FILE.backup.$(date +%s)"
    echo -e "  ${GREEN}✓ Created backup${NC}"

    # Remove existing block
    if grep -q "# wac-devflow" "$PROFILE_FILE" 2>/dev/null; then
        sed_inplace '/# wac-devflow/,/# \/wac-devflow/d' "$PROFILE_FILE"
    fi

    # Write new block
    {
        printf "\n"
        printf "# wac-devflow\n"
        printf "# Updated: %s\n" "$(date)"
        for VAR_NAME in "${VALUES_TO_WRITE[@]}"; do
            printf "export %s='%s'\n" "$VAR_NAME" "${WRITE_MAP[$VAR_NAME]}"
        done
        printf "# /wac-devflow\n"
        printf "\n"
    } >> "$PROFILE_FILE"

    chmod 600 "$PROFILE_FILE"
    echo ""

    for VAR_NAME in "${VALUES_TO_WRITE[@]}"; do
        if [[ "$VAR_NAME" == *TOKEN* ]]; then
            echo -e "  ${GREEN}✓${NC} $VAR_NAME  ${DIM}(saved)${NC}"
        else
            echo -e "  ${GREEN}✓${NC} $VAR_NAME = ${CYAN}${WRITE_MAP[$VAR_NAME]}${NC}"
        fi
    done

    echo ""
    # shellcheck disable=SC1090
    source "$PROFILE_FILE" 2>/dev/null || true
    echo -e "  ${GREEN}✓ Profile reloaded${NC}"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}  ╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}  ║   ✓  Setup complete!                               ║${NC}"
echo -e "${GREEN}  ╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Open a ${YELLOW}new terminal${NC} (or run ${CYAN}source $PROFILE_FILE${NC}) then:"
echo ""
echo -e "    ${CYAN}devflow check${NC}    — verify everything is configured"
echo -e "    ${CYAN}devflow push${NC}     — run the full pipeline"
echo -e "    ${CYAN}devflow init${NC}     — install the git pre-push hook"
echo ""
echo -e "  ${DIM}Security: never commit $PROFILE_FILE • rotate tokens every 6–12 months${NC}"
echo ""
