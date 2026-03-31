#!/bin/bash

# devflow-cli — Project Setup Wizard
# Detects project-level settings (test runner, SonarQube, target branch)
# and saves them to .devflow/devflow-project-setting.json in the project root.
# Tokens are NOT stored here — use `devflow setup` for those.

set -e

# ── OS compatibility ───────────────────────────────────────────────────────────
sed_inplace() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

normalize_path() {
    local path="$1"
    if [[ "$path" =~ ^[A-Za-z]:\\ ]]; then
        local drive="${path:0:1}"
        local rest="${path:2}"
        rest="${rest//\\//}"
        printf '/%s%s' "$(printf '%s' "$drive" | tr '[:upper:]' '[:lower:]')" "$rest"
    else
        printf '%s' "$path"
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

ask_yes_no() {
    local label="$1"
    local default="${2:-n}"
    local reply
    printf "  %s " "$label"
    read -r -n 1 reply
    echo ""
    if [ -z "$reply" ]; then reply="$default"; fi
    [[ "$reply" =~ ^[Yy]$ ]]
}

ask_value() {
    local -r out_var="$1"
    local -r label="$2"
    local -r default="$3"
    local value=""
    if [ -n "$default" ]; then
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

PYTHON_CMD=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")

# ── Detection helpers ──────────────────────────────────────────────────────────

detect_test_runner() {
    local pkg="$PROJECT_ROOT/package.json"

    # Check config files first — most reliable signal
    [ -f "$PROJECT_ROOT/vitest.config.js" ]   && echo "vitest"  && return
    [ -f "$PROJECT_ROOT/vitest.config.ts" ]   && echo "vitest"  && return
    [ -f "$PROJECT_ROOT/vitest.config.mjs" ]  && echo "vitest"  && return
    [ -f "$PROJECT_ROOT/jest.config.js" ]     && echo "jest"    && return
    [ -f "$PROJECT_ROOT/jest.config.ts" ]     && echo "jest"    && return
    [ -f "$PROJECT_ROOT/jest.config.mjs" ]    && echo "jest"    && return
    [ -f "$PROJECT_ROOT/playwright.config.js" ] && echo "playwright" && return
    [ -f "$PROJECT_ROOT/playwright.config.ts" ] && echo "playwright" && return
    [ -f "$PROJECT_ROOT/cypress.config.js" ]  && echo "cypress" && return
    [ -f "$PROJECT_ROOT/cypress.config.ts" ]  && echo "cypress" && return
    [ -f "$PROJECT_ROOT/.mocharc.js" ]        && echo "mocha"   && return
    [ -f "$PROJECT_ROOT/.mocharc.yml" ]       && echo "mocha"   && return
    [ -f "$PROJECT_ROOT/.mocharc.json" ]      && echo "mocha"   && return
    [ -f "$PROJECT_ROOT/karma.conf.js" ]      && echo "karma"   && return

    # Fall back to scanning package.json dependencies
    if [ -f "$pkg" ]; then
        local content
        content=$(cat "$pkg" 2>/dev/null || echo "")
        echo "$content" | grep -q '"vitest"'            && echo "vitest"     && return
        echo "$content" | grep -q '"jest"'              && echo "jest"       && return
        echo "$content" | grep -q '"@playwright/test"'  && echo "playwright" && return
        echo "$content" | grep -q '"cypress"'           && echo "cypress"    && return
        echo "$content" | grep -q '"mocha"'             && echo "mocha"      && return
        echo "$content" | grep -q '"jasmine"'           && echo "jasmine"    && return
        echo "$content" | grep -q '"ava"'               && echo "ava"        && return
        echo "$content" | grep -q '"karma"'             && echo "karma"      && return
        echo "$content" | grep -q '"@jest/core"'        && echo "jest"       && return
    fi

    echo ""
}

detect_test_command() {
    local runner="$1"
    local pkg="$PROJECT_ROOT/package.json"

    # If there's a meaningful "test" script in package.json, prefer npm test
    if [ -f "$pkg" ] && [ -n "$PYTHON_CMD" ]; then
        local test_script
        test_script=$(PKG_PATH="$pkg" "$PYTHON_CMD" -c "
import json, sys
try:
    with open(__import__('os').environ['PKG_PATH']) as f:
        d = json.load(f)
    s = d.get('scripts', {}).get('test', '')
    if s and 'no test specified' not in s:
        print('npm test')
    else:
        print('')
except:
    print('')
" 2>/dev/null || echo "")
        [ -n "$test_script" ] && echo "$test_script" && return
    fi

    case "$runner" in
        vitest)     echo "npx vitest run" ;;
        jest)       echo "npx jest" ;;
        playwright) echo "npx playwright test" ;;
        cypress)    echo "npx cypress run" ;;
        mocha)      echo "npx mocha" ;;
        jasmine)    echo "npx jasmine" ;;
        ava)        echo "npx ava" ;;
        karma)      echo "npx karma start --single-run" ;;
        *)          echo "npm test" ;;
    esac
}

detect_sonar() {
    # sonar-project.properties (on-premise SonarQube)
    [ -f "$PROJECT_ROOT/sonar-project.properties" ] && echo "properties" && return
    # SonarCloud config
    [ -f "$PROJECT_ROOT/.sonarcloud.properties" ]    && echo "sonarcloud" && return
    # sonar script in package.json
    if [ -f "$PROJECT_ROOT/package.json" ]; then
        grep -q '"sonar"' "$PROJECT_ROOT/package.json" 2>/dev/null && echo "script" && return
        grep -q 'sonar-scanner' "$PROJECT_ROOT/package.json" 2>/dev/null && echo "script" && return
    fi
    # Env vars already set
    if [ -n "${SONAR_TOKEN:-}" ] && [ -n "${SONAR_HOST:-}" ] && [ -n "${SONAR_PROJECT_KEY:-}" ]; then
        echo "env"
        return
    fi
    echo ""
}

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo ""
echo -e "${CYAN}  ╔════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}  ║                                                    ║${NC}"
echo -e "${CYAN}  ║   🛠   devflow-cli — Project Setup              ║${NC}"
echo -e "${CYAN}  ║                                                    ║${NC}"
echo -e "${CYAN}  ╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Saves project config to ${CYAN}.devflow/devflow-project-setting.json${NC} — safe to commit."
echo -e "  ${DIM}For tokens & credentials, run: devflow setup${NC}"
echo ""

# ── Resolve project root ──────────────────────────────────────────────────────
PROJECT_ROOT="$(normalize_path "${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}")"
cd "$PROJECT_ROOT" 2>/dev/null || true
CONFIG_DIR="$PROJECT_ROOT/.devflow"
CONFIG_FILE="$CONFIG_DIR/devflow-project-setting.json"
LEGACY_CONFIG_FILE="$PROJECT_ROOT/.devflow.json"

echo -e "  ${BLUE}Project root:${NC} ${CYAN}$PROJECT_ROOT${NC}"

# ── Show existing config if present ──────────────────────────────────────────
EXISTING_MAIN_BRANCH=""
EXISTING_SONAR_ENABLED=""
EXISTING_SONAR_PROJECT_KEY=""
EXISTING_TEST_RUNNER=""
EXISTING_TEST_COMMAND=""
EXISTING_RUN_BEFORE_PUSH=""

if [ ! -f "$CONFIG_FILE" ] && [ -f "$LEGACY_CONFIG_FILE" ]; then
    CONFIG_FILE="$LEGACY_CONFIG_FILE"
fi

if [ -f "$CONFIG_FILE" ] && [ -n "$PYTHON_CMD" ]; then
    echo -e "  ${GREEN}✓ Existing project settings found: ${CYAN}${CONFIG_FILE#$PROJECT_ROOT/}${NC}"
    echo ""
    EXISTING_MAIN_BRANCH=$(CONFIG_PATH="$CONFIG_FILE" "$PYTHON_CMD" -c "import json, os; d=json.load(open(os.environ['CONFIG_PATH'])); print(d.get('mainBranch',''))" 2>/dev/null || echo "")
    EXISTING_SONAR_ENABLED=$(CONFIG_PATH="$CONFIG_FILE" "$PYTHON_CMD" -c "import json, os; d=json.load(open(os.environ['CONFIG_PATH'])); v=d.get('sonar',{}).get('enabled',''); print('true' if v==True else ('false' if v==False else ''))" 2>/dev/null || echo "")
    EXISTING_SONAR_PROJECT_KEY=$(CONFIG_PATH="$CONFIG_FILE" "$PYTHON_CMD" -c "import json, os; d=json.load(open(os.environ['CONFIG_PATH'])); print(d.get('sonar',{}).get('projectKey',''))" 2>/dev/null || echo "")
    EXISTING_TEST_RUNNER=$(CONFIG_PATH="$CONFIG_FILE" "$PYTHON_CMD" -c "import json, os; d=json.load(open(os.environ['CONFIG_PATH'])); print(d.get('tests',{}).get('runner',''))" 2>/dev/null || echo "")
    EXISTING_TEST_COMMAND=$(CONFIG_PATH="$CONFIG_FILE" "$PYTHON_CMD" -c "import json, os; d=json.load(open(os.environ['CONFIG_PATH'])); print(d.get('tests',{}).get('command',''))" 2>/dev/null || echo "")
    EXISTING_RUN_BEFORE_PUSH=$(CONFIG_PATH="$CONFIG_FILE" "$PYTHON_CMD" -c "import json, os; d=json.load(open(os.environ['CONFIG_PATH'])); v=d.get('tests',{}).get('runBeforePush',''); print('true' if v==True else 'false')" 2>/dev/null || echo "")

    [ -n "$EXISTING_MAIN_BRANCH" ]       && echo -e "    mainBranch          = ${CYAN}$EXISTING_MAIN_BRANCH${NC}"
    [ -n "$EXISTING_SONAR_ENABLED" ]     && echo -e "    sonar.enabled       = ${CYAN}$EXISTING_SONAR_ENABLED${NC}"
    [ -n "$EXISTING_SONAR_PROJECT_KEY" ] && echo -e "    sonar.projectKey    = ${CYAN}$EXISTING_SONAR_PROJECT_KEY${NC}"
    [ -n "$EXISTING_TEST_RUNNER" ]       && echo -e "    tests.runner        = ${CYAN}$EXISTING_TEST_RUNNER${NC}"
    [ -n "$EXISTING_TEST_COMMAND" ]      && echo -e "    tests.command       = ${CYAN}$EXISTING_TEST_COMMAND${NC}"
    [ -n "$EXISTING_RUN_BEFORE_PUSH" ]   && echo -e "    tests.runBeforePush = ${CYAN}$EXISTING_RUN_BEFORE_PUSH${NC}"
    echo ""
fi

read -r -p "  Start project setup? (Y/n): " -n 1 REPLY
echo ""
[[ "$REPLY" =~ ^[Nn]$ ]] && echo "  Setup cancelled." && exit 0
echo ""

# ── Step 1: Target Branch ─────────────────────────────────────────────────────
print_step "Step 1 — Target Branch"

DETECTED_MAIN=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|.*/||' || echo "")
FINAL_MAIN_BRANCH=""

if [ -n "$EXISTING_MAIN_BRANCH" ]; then
    echo -e "  Current: ${CYAN}$EXISTING_MAIN_BRANCH${NC}"
    if ask_yes_no "  Change target branch? (y/N):"; then
        ask_branch FINAL_MAIN_BRANCH "${DETECTED_MAIN:-${EXISTING_MAIN_BRANCH}}"
    else
        FINAL_MAIN_BRANCH="$EXISTING_MAIN_BRANCH"
        echo -e "  ${GREEN}✓ Keeping: ${CYAN}$FINAL_MAIN_BRANCH${NC}"
        echo ""
    fi
else
    ask_branch FINAL_MAIN_BRANCH "${DETECTED_MAIN:-develop}"
fi

# ── Step 2: SonarQube ─────────────────────────────────────────────────────────
print_step "Step 2 — SonarQube"

SONAR_SIGNAL=$(detect_sonar)
FINAL_SONAR_ENABLED="false"
FINAL_SONAR_PROJECT_KEY=""

case "$SONAR_SIGNAL" in
    properties)
        echo -e "  ${GREEN}✓ Detected:${NC} ${CYAN}sonar-project.properties${NC} found"
        FINAL_SONAR_ENABLED="true"
        ;;
    sonarcloud)
        echo -e "  ${GREEN}✓ Detected:${NC} ${CYAN}.sonarcloud.properties${NC} found"
        FINAL_SONAR_ENABLED="true"
        ;;
    script)
        echo -e "  ${GREEN}✓ Detected:${NC} sonar-scanner script in ${CYAN}package.json${NC}"
        FINAL_SONAR_ENABLED="true"
        ;;
    env)
        echo -e "  ${GREEN}✓ Detected:${NC} SonarQube env vars already configured"
        FINAL_SONAR_ENABLED="true"
        ;;
    *)
        echo -e "  ${YELLOW}No SonarQube config detected in this project.${NC}"
        ;;
esac

echo ""

if [ "$FINAL_SONAR_ENABLED" = "true" ]; then
    if ask_yes_no "  Enable SonarQube for this project? (Y/n):" "y"; then
        FINAL_SONAR_ENABLED="true"
        echo -e "  ${GREEN}✓ SonarQube enabled${NC}"
    else
        FINAL_SONAR_ENABLED="false"
        echo -e "  ${YELLOW}SonarQube disabled for this project${NC}"
    fi
else
    if ask_yes_no "  Enable SonarQube anyway? (y/N):"; then
        FINAL_SONAR_ENABLED="true"
        echo -e "  ${GREEN}✓ SonarQube enabled${NC}"
        echo -e "  ${DIM}Run 'devflow setup' to configure SONAR_TOKEN and SONAR_HOST${NC}"
    else
        FINAL_SONAR_ENABLED="false"
        echo -e "  ${DIM}SonarQube disabled — run project-setup again to enable later${NC}"
    fi
fi

if [ "$FINAL_SONAR_ENABLED" = "true" ]; then
    echo ""
    # Auto-suggest project key from project path
    _REMOTE_PATH=$(git remote get-url origin 2>/dev/null | sed 's|\.git$||; s|.*[:/]||; s|.*/\(.*\)|\1|' || echo "")
    _SUGGESTED_KEY=$(git remote get-url origin 2>/dev/null | sed 's|\.git$||' | grep -o '[^/:]*\/[^/:]*$' | sed 's|/|_|g; s|-|_|g' | tr '[:upper:]' '[:lower:]' || echo "")

    # Try to extract from file if not already set
    _FILE_KEY=""
    if [ -f "$PROJECT_ROOT/sonar-project.properties" ]; then
        _FILE_KEY=$(grep "^sonar.projectKey=" "$PROJECT_ROOT/sonar-project.properties" | cut -d'=' -f2)
    elif [ -f "$PROJECT_ROOT/.sonarcloud.properties" ]; then
        _FILE_KEY=$(grep "^sonar.projectKey=" "$PROJECT_ROOT/.sonarcloud.properties" | cut -d'=' -f2)
    fi

    FINAL_SONAR_PROJECT_KEY="${EXISTING_SONAR_PROJECT_KEY:-${SONAR_PROJECT_KEY:-}}"
    [ -z "$FINAL_SONAR_PROJECT_KEY" ] && [ -n "$_FILE_KEY" ] && FINAL_SONAR_PROJECT_KEY="$_FILE_KEY"

    if [ -n "$FINAL_SONAR_PROJECT_KEY" ]; then
        echo -e "  ${GREEN}✓ SonarQube project key: ${CYAN}$FINAL_SONAR_PROJECT_KEY${NC}"
        if ask_yes_no "  Change project key? (y/N):"; then
            [ -n "$_SUGGESTED_KEY" ] && echo -e "  ${BLUE}Suggested:${NC} ${DIM}${_SUGGESTED_KEY}_<uniqueId>${NC}"
            ask_value FINAL_SONAR_PROJECT_KEY "SonarQube project key" "$FINAL_SONAR_PROJECT_KEY"
        fi
    else
        [ -n "$_SUGGESTED_KEY" ] && echo -e "  ${BLUE}Suggested key prefix:${NC} ${DIM}${_SUGGESTED_KEY}_<uniqueId>${NC}"
        echo -e "  ${BLUE}Find your key at:${NC} SonarQube Dashboard → Project → Project Information"
        echo ""
        ask_value FINAL_SONAR_PROJECT_KEY "SonarQube project key" "${_SUGGESTED_KEY:-}"
    fi
fi

# ── Step 3: Test Runner ───────────────────────────────────────────────────────
print_step "Step 3 — Test Runner"

DETECTED_RUNNER=$(detect_test_runner)
FINAL_TEST_RUNNER=""
FINAL_TEST_COMMAND=""
FINAL_RUN_BEFORE_PUSH="false"

TEST_RUNNERS=("jest" "vitest" "mocha" "jasmine" "ava" "karma" "playwright" "cypress" "none")

if [ -n "$DETECTED_RUNNER" ]; then
    echo -e "  ${GREEN}✓ Auto-detected:${NC} ${CYAN}$DETECTED_RUNNER${NC}"
    DETECTED_CMD=$(detect_test_command "$DETECTED_RUNNER")
    echo -e "  ${BLUE}  Command:${NC} ${CYAN}$DETECTED_CMD${NC}"
    echo ""
    if ask_yes_no "  Use detected runner? (Y/n):" "y"; then
        FINAL_TEST_RUNNER="$DETECTED_RUNNER"
        FINAL_TEST_COMMAND="$DETECTED_CMD"
    fi
fi

if [ -z "$FINAL_TEST_RUNNER" ]; then
    FINAL_TEST_RUNNER=$(arrow_select TEST_RUNNERS 0 "Use arrow keys and Enter to select the test runner")

    if [ "$FINAL_TEST_RUNNER" = "none" ]; then
        FINAL_TEST_RUNNER=""
        FINAL_TEST_COMMAND=""
        echo -e "  ${DIM}No test runner configured${NC}"
    else
        DETECTED_CMD=$(detect_test_command "$FINAL_TEST_RUNNER")
        ask_value FINAL_TEST_COMMAND "Test command" "$DETECTED_CMD"
        echo -e "  ${GREEN}✓ Test runner: ${CYAN}$FINAL_TEST_RUNNER${NC}"
    fi
fi

if [ -n "$FINAL_TEST_RUNNER" ] && [ "$FINAL_TEST_RUNNER" != "none" ]; then
    echo ""
    if ask_yes_no "  Run tests automatically before every push? (y/N):"; then
        FINAL_RUN_BEFORE_PUSH="true"
        echo -e "  ${GREEN}✓ Tests will run before each push${NC}"
    else
        FINAL_RUN_BEFORE_PUSH="false"
        echo -e "  ${DIM}Tests will not run automatically before push${NC}"
    fi
fi

# ── Step 4: Write project settings ────────────────────────────────────────────
print_step "Step 4 — Saving project settings"

mkdir -p "$CONFIG_DIR"
CONFIG_FILE="$CONFIG_DIR/devflow-project-setting.json"

# Build JSON with python if available, else manual string
if [ -n "$PYTHON_CMD" ]; then
    CONFIG_PATH="$CONFIG_FILE" \
    FINAL_MAIN_BRANCH="$FINAL_MAIN_BRANCH" \
    FINAL_SONAR_ENABLED="$FINAL_SONAR_ENABLED" \
    FINAL_SONAR_PROJECT_KEY="$FINAL_SONAR_PROJECT_KEY" \
    FINAL_TEST_RUNNER="$FINAL_TEST_RUNNER" \
    FINAL_TEST_COMMAND="$FINAL_TEST_COMMAND" \
    FINAL_RUN_BEFORE_PUSH="$FINAL_RUN_BEFORE_PUSH" \
    "$PYTHON_CMD" -c "
import json
import os

cfg = {
    'mainBranch': os.environ['FINAL_MAIN_BRANCH'],
    'sonar': {
        'enabled': os.environ['FINAL_SONAR_ENABLED'] == 'true',
        'projectKey': os.environ['FINAL_SONAR_PROJECT_KEY']
    },
    'tests': {
        'runner': os.environ['FINAL_TEST_RUNNER'],
        'command': os.environ['FINAL_TEST_COMMAND'],
        'runBeforePush': os.environ['FINAL_RUN_BEFORE_PUSH'] == 'true'
    }
}
with open(os.environ['CONFIG_PATH'], 'w') as f:
    json.dump(cfg, f, indent=2)
    f.write('\n')
print('ok')
" 2>/dev/null
else
    # Minimal fallback without python
    cat > "$CONFIG_FILE" <<EOF
{
  "mainBranch": "$FINAL_MAIN_BRANCH",
  "sonar": {
    "enabled": $FINAL_SONAR_ENABLED,
    "projectKey": "$FINAL_SONAR_PROJECT_KEY"
  },
  "tests": {
    "runner": "$FINAL_TEST_RUNNER",
    "command": "$FINAL_TEST_COMMAND",
    "runBeforePush": $FINAL_RUN_BEFORE_PUSH
  }
}
EOF
fi

echo -e "  ${GREEN}✓ Written: ${CYAN}$CONFIG_FILE${NC}"
echo ""
echo -e "  ${BLUE}Contents:${NC}"
cat "$CONFIG_FILE" | sed 's/^/    /'
echo ""

# ── Offer to gitignore (only if sensitive — it's not, so offer to commit) ─────
if [ -f "$PROJECT_ROOT/.gitignore" ]; then
    if grep -Eq '(^|/)\.devflow/?($|/)|\.devflow\.json' "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
        echo -e "  ${YELLOW}Note:${NC} devflow project settings are currently ignored by git"
        if ask_yes_no "  Remove from .gitignore so it can be committed? (y/N):"; then
            sed_inplace '/\.devflow\.json/d' "$PROJECT_ROOT/.gitignore"
            sed_inplace '/^\.devflow\/$/d' "$PROJECT_ROOT/.gitignore"
            sed_inplace '/^\.devflow$/d' "$PROJECT_ROOT/.gitignore"
            echo -e "  ${GREEN}✓ Removed from .gitignore${NC}"
        fi
    else
        echo -e "  ${DIM}Tip: .devflow/devflow-project-setting.json contains no secrets — safe to commit to git.${NC}"
    fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}  ╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}  ║   ✓  Project setup complete!                       ║${NC}"
echo -e "${GREEN}  ╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BLUE}Summary:${NC}"
echo -e "    Target branch      → ${CYAN}$FINAL_MAIN_BRANCH${NC}"
echo -e "    SonarQube          → ${CYAN}$FINAL_SONAR_ENABLED${NC}"
[ -n "$FINAL_SONAR_PROJECT_KEY" ] && echo -e "    SonarQube key      → ${CYAN}$FINAL_SONAR_PROJECT_KEY${NC}"
if [ -n "$FINAL_TEST_RUNNER" ]; then
echo -e "    Test runner        → ${CYAN}$FINAL_TEST_RUNNER${NC}"
echo -e "    Test command       → ${CYAN}$FINAL_TEST_COMMAND${NC}"
echo -e "    Run before push    → ${CYAN}$FINAL_RUN_BEFORE_PUSH${NC}"
else
echo -e "    Test runner        → ${CYAN}none${NC}"
fi
echo ""
echo -e "  Next steps:"
echo -e "    ${CYAN}devflow push${NC}     — run the pipeline (picks up new config)"
echo -e "    ${CYAN}devflow check${NC}    — verify full environment"
echo -e "    ${CYAN}git add .devflow/devflow-project-setting.json && git commit${NC}  — commit project config"
echo ""
