#!/bin/bash

# devflow-cli — Interactive Setup Wizard
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

arrow_select() {
    local -n _options_ref=$1
    local current_index=${2:-0}
    local prompt="${3:-Select an option}"
    local selected=""
    local count=${#_options_ref[@]}
    local i key

    [ "$count" -eq 0 ] && return 1

    while true; do
        echo -ne "\033[?25l"
        echo -e "  ${BLUE}${prompt}${NC}"
        for i in "${!_options_ref[@]}"; do
            if [ "$i" -eq "$current_index" ]; then
                echo -e "  ${CYAN}❯ ${_options_ref[$i]}${NC}"
            else
                echo -e "    ${_options_ref[$i]}"
            fi
        done

        IFS= read -rsn1 key
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 key
            case "$key" in
                '[A') current_index=$(( (current_index - 1 + count) % count )) ;;
                '[B') current_index=$(( (current_index + 1) % count )) ;;
            esac
        elif [[ "$key" == "" || "$key" == $'\n' ]]; then
            selected="${_options_ref[$current_index]}"
            printf '\033[%sA' "$((count + 1))"
            printf '\033[J'
            echo -ne "\033[?25h"
            printf '%s\n' "$selected"
            return 0
        fi

        printf '\033[%sA' "$((count + 1))"
        printf '\033[J'
    done
}

# Branch selection menu
# Usage: ask_branch OUTPUT_VAR "default_branch"
ask_branch() {
    local -r out_var="$1"
    local -r default="$2"
    local branches=("main" "master" "develop" "stage" "Other (enter manually)")
    local value default_index=0 selection i

    for i in "${!branches[@]}"; do
        [ "${branches[$i]}" = "$default" ] && default_index=$i
    done

    selection=$(arrow_select branches "$default_index" "Use arrow keys and Enter to select the target branch")
    if [ "$selection" = "Other (enter manually)" ]; then
        while true; do
            printf "  Enter branch name: "
            read -r value
            [ -n "$value" ] && break
            echo -e "  ${RED}Branch name cannot be empty.${NC}"
        done
    else
        value="$selection"
    fi

    export "$out_var"="$value"
    echo -e "  ${GREEN}✓ Target branch: ${CYAN}$value${NC}"
    echo ""
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

AI_CLI_CHOICES=("claude" "codex" "gemini")

get_agent_package() {
    case "$1" in
        claude) echo "@anthropic-ai/claude-code" ;;
        codex)  echo "@openai/codex" ;;
        gemini) echo "@google/gemini-cli" ;;
        *)      echo "" ;;
    esac
}

get_agent_label() {
    case "$1" in
        claude) echo "Claude Code CLI" ;;
        codex)  echo "Codex CLI" ;;
        gemini) echo "Gemini CLI" ;;
        *)      echo "$1" ;;
    esac
}

get_agent_command() {
    case "$1" in
        claude) echo "claude" ;;
        codex)  echo "codex" ;;
        gemini) echo "gemini" ;;
        *)      echo "" ;;
    esac
}

get_agent_install_url() {
    case "$1" in
        claude) echo "https://docs.anthropic.com/en/docs/claude-code/getting-started" ;;
        codex)  echo "https://help.openai.com/en/articles/11096431-openai-codex-ci-getting-started" ;;
        gemini) echo "https://github.com/google-gemini/gemini-cli" ;;
        *)      echo "" ;;
    esac
}

is_agent_installed() {
    local cmd
    cmd=$(get_agent_command "$1")
    [ -n "$cmd" ] && command -v "$cmd" >/dev/null 2>&1
}

collect_installed_agents() {
    local installed=()
    local agent
    for agent in "${AI_CLI_CHOICES[@]}"; do
        if is_agent_installed "$agent"; then
            installed+=("$agent")
        fi
    done
    printf '%s\n' "${installed[@]}"
}

install_agent_with_npm() {
    local agent="$1"
    local package_name
    package_name=$(get_agent_package "$agent")
    local agent_label
    agent_label=$(get_agent_label "$agent")

    if ! command -v npm >/dev/null 2>&1; then
        echo -e "  ${YELLOW}npm is not available on this machine.${NC}"
        echo -e "  Install Node.js, then run: ${CYAN}npm install -g ${package_name}${NC}"
        return 1
    fi

    echo -e "  Installing ${CYAN}${agent_label}${NC} with npm..."
    if npm install -g "$package_name"; then
        echo -e "  ${GREEN}✓ Installed ${agent_label}${NC}"
        return 0
    fi

    echo -e "  ${YELLOW}⚠  npm install failed for ${agent_label}.${NC}"
    echo -e "  Manual install: ${CYAN}npm install -g ${package_name}${NC}"
    return 1
}

prompt_install_agents() {
    while true; do
        local install_options=(
            "Claude Code CLI (claude)"
            "Codex CLI (codex)"
            "Gemini CLI (gemini)"
            "Done"
        )
        local selection selected_agent
        selection=$(arrow_select install_options 0 "Use arrow keys and Enter to choose an AI CLI to install")

        case "$selection" in
            "Claude Code CLI (claude)") selected_agent="claude" ;;
            "Codex CLI (codex)") selected_agent="codex" ;;
            "Gemini CLI (gemini)") selected_agent="gemini" ;;
            "Done") break ;;
        esac

        install_agent_with_npm "$selected_agent"
        echo ""
    done
}

ask_default_agent_cli() {
    local -r out_var="$1"
    local -a installed_agents=("$@")
    installed_agents=("${installed_agents[@]:1}")
    local default_value="${DEVFLOW_DEFAULT_AI_CLI:-}"
    local selected_agent
    local menu_labels=()
    local default_index=0
    local i=0

    if [ ${#installed_agents[@]} -eq 0 ]; then
        export "$out_var"="${default_value:-}"
        return 0
    fi

    for selected_agent in "${installed_agents[@]}"; do
        local label
        label="$(get_agent_label "$selected_agent")"
        if [ "$selected_agent" = "$default_value" ]; then
            label="$label (current default)"
            default_index=$i
        fi
        menu_labels+=("$label")
        i=$((i + 1))
    done
    selected_agent=$(arrow_select menu_labels "$default_index" "Use arrow keys and Enter to choose the default AI CLI")
    export "$out_var"="${installed_agents[$default_index]}"
    for i in "${!menu_labels[@]}"; do
        [ "${menu_labels[$i]}" = "$selected_agent" ] && export "$out_var"="${installed_agents[$i]}"
    done
}

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo ""
echo -e "${CYAN}  ╔════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}  ║                                                    ║${NC}"
echo -e "${CYAN}  ║   🔐  devflow-cli — First-Time Setup Wizard      ║${NC}"
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
show_var GITHUB_HOST
show_var USE_SONAR
show_var SONAR_TOKEN
show_var SONAR_HOST
show_var DEVFLOW_DEFAULT_AI_CLI
echo ""
echo -e "  ${DIM}Project-specific settings (branch, project key, test runner) are${NC}"
echo -e "  ${DIM}configured per-project via: devflow project-setup${NC}"
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
    echo -e "  ${DIM}Project path is also auto-detected from git remote on each push.${NC}"
    echo ""

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

    echo -e "  ${DIM}Project path is auto-detected from git remote on each push.${NC}"
    echo ""

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

DEFAULT_AGENT_STEP_NUM=$((SONAR_STEP_NUM + 1))
print_step "Step $DEFAULT_AGENT_STEP_NUM — AI Coding CLI"

mapfile -t INSTALLED_AGENTS < <(collect_installed_agents)

if [ ${#INSTALLED_AGENTS[@]} -eq 0 ]; then
    echo -e "  ${YELLOW}No supported AI coding CLI detected.${NC}"
    echo -e "  ${DIM}devflow supports Claude Code, Codex, and Gemini.${NC}"
    echo ""
    if ask_yes_no "Install one or more AI CLIs with npm now? (Y/n):" "y"; then
        prompt_install_agents
        mapfile -t INSTALLED_AGENTS < <(collect_installed_agents)
    else
        echo -e "  Manual install commands:"
        for agent in "${AI_CLI_CHOICES[@]}"; do
            echo -e "    ${CYAN}npm install -g $(get_agent_package "$agent")${NC}  ${DIM}# $(get_agent_label "$agent")${NC}"
        done
        echo ""
    fi
else
    echo -e "  ${GREEN}Detected AI CLIs:${NC}"
    for agent in "${INSTALLED_AGENTS[@]}"; do
        echo -e "    ${GREEN}✓${NC} $(get_agent_label "$agent")"
    done
    echo ""
    if ask_yes_no "Install another AI CLI with npm? (y/N):"; then
        prompt_install_agents
        mapfile -t INSTALLED_AGENTS < <(collect_installed_agents)
    fi
fi

NEW_DEFAULT_AI_CLI="${DEVFLOW_DEFAULT_AI_CLI:-}"
if [ ${#INSTALLED_AGENTS[@]} -gt 0 ]; then
    ask_default_agent_cli NEW_DEFAULT_AI_CLI "${INSTALLED_AGENTS[@]}"
    echo -e "  ${GREEN}✓ Default AI CLI: ${CYAN}${NEW_DEFAULT_AI_CLI}${NC}"
else
    echo -e "  ${YELLOW}No AI CLI selected yet.${NC}"
    echo -e "  ${DIM}Install one later, then set DEVFLOW_DEFAULT_AI_CLI to claude, codex, or gemini.${NC}"
fi
echo ""

# ── Step 6: Save to profile ───────────────────────────────────────────────────
print_step "Step 6 — Saving to $PROFILE_FILE"

declare -A WRITE_MAP
VALUES_TO_WRITE=()

persist_value() {
    local VAR_NAME="$1"
    local VAR_VAL="$2"
    if [ -n "$VAR_VAL" ] || [ "$VAR_NAME" = "USE_SONAR" ] || [ "$VAR_NAME" = "GIT_PROVIDER" ]; then
        VALUES_TO_WRITE+=("$VAR_NAME")
        WRITE_MAP["$VAR_NAME"]="$VAR_VAL"
    fi
}

persist_value "GIT_PROVIDER" "$NEW_GIT_PROVIDER"
persist_value "USE_SONAR"    "$NEW_USE_SONAR"
persist_value "DEVFLOW_DEFAULT_AI_CLI" "$NEW_DEFAULT_AI_CLI"

if [ "$NEW_GIT_PROVIDER" = "github" ]; then
    persist_value "GITHUB_HOST"  "${NEW_GITHUB_HOST:-}"
    persist_value "GITHUB_TOKEN" "$NEW_GIT_TOKEN"
else
    persist_value "GITLAB_HOST"  "${NEW_GITLAB_HOST:-}"
    persist_value "GITLAB_TOKEN" "$NEW_GIT_TOKEN"
fi

if [ "$NEW_USE_SONAR" = "1" ]; then
    persist_value "SONAR_HOST"  "$NEW_SONAR_HOST"
    persist_value "SONAR_TOKEN" "$NEW_SONAR_TOKEN"
fi

touch "$PROFILE_FILE"
cp "$PROFILE_FILE" "$PROFILE_FILE.backup.$(date +%s)"
echo -e "  ${GREEN}✓ Created backup${NC}"

if grep -q "# devflow-cli" "$PROFILE_FILE" 2>/dev/null; then
    sed_inplace '/# devflow-cli/,/# \/devflow-cli/d' "$PROFILE_FILE"
fi

{
    printf "\n"
    printf "# devflow-cli\n"
    printf "# Updated: %s\n" "$(date)"
    for VAR_NAME in "${VALUES_TO_WRITE[@]}"; do
        printf "export %s='%s'\n" "$VAR_NAME" "${WRITE_MAP[$VAR_NAME]}"
    done
    printf "# /devflow-cli\n"
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

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}  ╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}  ║   ✓  Setup complete!                               ║${NC}"
echo -e "${GREEN}  ╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Open a ${YELLOW}new terminal${NC} (or run ${CYAN}source $PROFILE_FILE${NC}) then:"
echo ""
echo -e "    ${CYAN}devflow project-setup${NC}  — configure this project (branch, SonarQube key, tests)"
echo -e "    ${CYAN}devflow check${NC}          — verify everything is configured"
echo -e "    ${CYAN}devflow push${NC}           — run the full pipeline"
echo -e "    ${CYAN}devflow init${NC}           — install the git pre-push hook"
echo -e "    ${CYAN}${NEW_DEFAULT_AI_CLI:-claude}${NC}                     — open your default AI coding CLI"
echo ""
echo -e "  ${DIM}Security: never commit $PROFILE_FILE • rotate tokens every 6–12 months${NC}"
echo ""
