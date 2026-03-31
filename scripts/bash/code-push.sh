#!/bin/bash

# Automated Code Push & SonarQube Fix Pipeline
# Complete workflow: stage → commit → push → MR → pipeline → sonar fix → loop

set -e

# ── Configuration ─────────────────────────────────────────────────────────────
GIT_PROVIDER="${GIT_PROVIDER:-gitlab}"
USE_SONAR="${USE_SONAR:-}"

# ── Auto-detect project path from current git remote ─────────────────────────
# This ensures each project uses its own path, not a global env var from another project.
_detect_project_path() {
    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    [ -z "$remote_url" ] && return
    local clean="${remote_url%.git}"
    # HTTPS: https://host/org/repo
    if [[ "$clean" =~ ^https://([^/]+)/(.+)$ ]]; then
        echo "${BASH_REMATCH[2]}"
    # SSH: git@host:org/repo
    elif [[ "$clean" =~ ^git@([^:]+):(.+)$ ]]; then
        echo "${BASH_REMATCH[2]}"
    fi
}

_detect_git_host() {
    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    [ -z "$remote_url" ] && return
    local clean="${remote_url%.git}"
    if [[ "$clean" =~ ^https://([^/]+)/(.+)$ ]]; then
        echo "https://${BASH_REMATCH[1]}"
    elif [[ "$clean" =~ ^git@([^:]+):(.+)$ ]]; then
        echo "https://${BASH_REMATCH[1]}"
    fi
}

# Resolve provider-specific vars
if [ "$GIT_PROVIDER" = "github" ]; then
    export GIT_TOKEN="${GITHUB_TOKEN:-}"
    export GIT_HOST="${GITHUB_HOST:-$(_detect_git_host)}"
    export GIT_HOST="${GIT_HOST:-https://github.com}"
    export PROJECT_PATH="$(_detect_project_path)"
    export PROJECT_PATH="${PROJECT_PATH:-${GITHUB_PROJECT_PATH:-${GITLAB_PROJECT_PATH:-}}}"
    export MAIN_BRANCH="${MAIN_BRANCH:-main}"
else
    export GIT_TOKEN="${GITLAB_TOKEN:-}"
    export GIT_HOST="${GITLAB_HOST:-$(_detect_git_host)}"
    export GIT_HOST="${GIT_HOST:-https://gitlab.com}"
    export PROJECT_PATH="$(_detect_project_path)"
    export PROJECT_PATH="${PROJECT_PATH:-${GITLAB_PROJECT_PATH:-}}"
    export MAIN_BRANCH="${MAIN_BRANCH:-develop}"
fi

# ── Load per-project config from .devflow/devflow-project-setting.json ───────
_PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
_DEVFLOW_JSON="${_PROJECT_ROOT}/.devflow/devflow-project-setting.json"
_LEGACY_DEVFLOW_JSON="${_PROJECT_ROOT}/.devflow.json"
_PYTHON_EARLY=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")

[ -f "$_DEVFLOW_JSON" ] || _DEVFLOW_JSON="$_LEGACY_DEVFLOW_JSON"

if [ -f "$_DEVFLOW_JSON" ] && [ -n "$_PYTHON_EARLY" ]; then
    _cfg_branch=$("$_PYTHON_EARLY" -c "import json; d=json.load(open('$_DEVFLOW_JSON')); print(d.get('mainBranch',''))" 2>/dev/null || echo "")
    _cfg_sonar=$("$_PYTHON_EARLY" -c "import json; d=json.load(open('$_DEVFLOW_JSON')); v=d.get('sonar',{}).get('enabled',''); print('1' if v==True else ('0' if v==False else ''))" 2>/dev/null || echo "")
    _cfg_sonar_key=$("$_PYTHON_EARLY" -c "import json; d=json.load(open('$_DEVFLOW_JSON')); print(d.get('sonar',{}).get('projectKey',''))" 2>/dev/null || echo "")
    _cfg_test_runner=$("$_PYTHON_EARLY" -c "import json; d=json.load(open('$_DEVFLOW_JSON')); print(d.get('tests',{}).get('runner',''))" 2>/dev/null || echo "")
    _cfg_test_cmd=$("$_PYTHON_EARLY" -c "import json; d=json.load(open('$_DEVFLOW_JSON')); print(d.get('tests',{}).get('command',''))" 2>/dev/null || echo "")
    _cfg_run_tests=$("$_PYTHON_EARLY" -c "import json; d=json.load(open('$_DEVFLOW_JSON')); v=d.get('tests',{}).get('runBeforePush',False); print('1' if v else '0')" 2>/dev/null || echo "0")

    # Only apply if not already overridden by env or CLI
    [ -n "$_cfg_branch" ]     && [ -z "${MAIN_BRANCH_OVERRIDE:-}" ] && export MAIN_BRANCH="$_cfg_branch"
    [ -n "$_cfg_sonar" ]      && [ -z "${USE_SONAR:-}" ]            && export USE_SONAR="$_cfg_sonar"
    [ -n "$_cfg_sonar_key" ]  && [ -z "${SONAR_PROJECT_KEY:-}" ]    && export SONAR_PROJECT_KEY="$_cfg_sonar_key"
    [ -n "$_cfg_test_runner" ] && export TEST_RUNNER="${TEST_RUNNER:-$_cfg_test_runner}"
    [ -n "$_cfg_test_cmd" ]    && export TEST_COMMAND="${TEST_COMMAND:-$_cfg_test_cmd}"
    export RUN_TESTS_BEFORE_PUSH="${RUN_TESTS_BEFORE_PUSH:-$_cfg_run_tests}"
fi

# Backward-compat: if USE_SONAR not explicitly set, infer from whether vars exist
if [ -z "$USE_SONAR" ]; then
    if [ -n "$SONAR_TOKEN" ] && [ -n "$SONAR_PROJECT_KEY" ] && [ -n "$SONAR_HOST" ]; then
        export USE_SONAR="1"
    else
        export USE_SONAR="0"
    fi
fi

export SONAR_HOST="${SONAR_HOST:-}"
export SONAR_TOKEN="${SONAR_TOKEN:-}"
export SONAR_PROJECT_KEY="${SONAR_PROJECT_KEY:-}"
PROJECT_KEY="$SONAR_PROJECT_KEY"
MAX_RETRIES="${MAX_RETRIES:-3}"
DEFAULT_AI_CLI="${DEVFLOW_DEFAULT_AI_CLI:-}"

# Temp files — use TMPDIR for macOS compatibility
TMPDIR="${TMPDIR:-/tmp}"
SONAR_ISSUES_FILE="$TMPDIR/sonar-issues.json"
SONAR_PARSED_ISSUES_FILE="$TMPDIR/sonar-issues-parsed.txt"

# ── OS compatibility ───────────────────────────────────────────────────────────
# Portable python command
PYTHON_CMD=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")

# Portable sed -i (BSD sed on macOS requires an empty-string argument)
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
NC='\033[0m'

# ── Animation utilities ───────────────────────────────────────────────────────
_SPINNER_PID=""

start_spinner() {
    local msg="${1:-Processing...}"
    (
        local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local i=0
        trap "exit 0" TERM INT
        while true; do
            printf "\r\033[0;36m%s\033[0m %s" "${frames[$i]}" "$msg" > /dev/tty 2>/dev/null || true
            i=$(( (i+1) % ${#frames[@]} ))
            sleep 0.1
        done
    ) &
    _SPINNER_PID=$!
    disown "$_SPINNER_PID" 2>/dev/null || true
}

stop_spinner() {
    local msg="${1:-}"
    if [ -n "$_SPINNER_PID" ] && kill -0 "$_SPINNER_PID" 2>/dev/null; then
        kill "$_SPINNER_PID" 2>/dev/null
        wait "$_SPINNER_PID" 2>/dev/null || true
        _SPINNER_PID=""
    fi
    printf "\r%-80s\r" " " > /dev/tty 2>/dev/null || true
    [ -n "$msg" ] && echo -e "$msg"
}

# Smooth animated countdown — 60fps, countdown in seconds
animated_wait() {
    local seconds=$1
    local msg="${2:-Waiting}"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local total_ticks=$(( seconds * 60 ))
    local i=0
    for ((t=total_ticks; t>0; t--)); do
        local remaining=$(( (t + 59) / 60 ))
        printf "\r\033[0;36m%s\033[0m \033[0;33m%s\033[0m \033[0;34m(%ds)\033[0m   " \
            "${frames[$i]}" "$msg" "$remaining" > /dev/tty 2>/dev/null || true
        i=$(( (i+1) % ${#frames[@]} ))
        sleep 0.016
    done
    printf "\r\033[0;36m↻\033[0m \033[0;33m%s\033[0m \033[0;34m(checking...)\033[0m          " \
        "$msg" > /dev/tty 2>/dev/null || true
}

# Clear the animation line and move to a fresh line before printing normal output
clear_animation_line() {
    printf "\r%-100s\r\n" " " > /dev/tty 2>/dev/null || true
}

render_live_status() {
    local message="$1"
    printf "\r\033[0;36m%s\033[0m" "$message" > /dev/tty 2>/dev/null || true
}

# ── Script directory ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Utilities ─────────────────────────────────────────────────────────────────
print_banner() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                   ║${NC}"
    echo -e "${CYAN}║   🚀 Automated Code Push & SonarQube Pipeline    ║${NC}"
    echo -e "${CYAN}║                                                   ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo ""
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}$1${NC}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

check_tokens() {
    if [ -z "$GIT_TOKEN" ]; then
        if [ "$GIT_PROVIDER" = "github" ]; then
            echo -e "${RED}Error: GITHUB_TOKEN not set${NC}"
            echo "  export GITHUB_TOKEN='your-token'"
            echo "  Generate at: $GIT_HOST/settings/tokens/new"
            echo "  Required scopes: repo"
        else
            echo -e "${RED}Error: GITLAB_TOKEN not set${NC}"
            echo "  export GITLAB_TOKEN='your-token'"
            echo "  Generate at: $GIT_HOST/-/user_settings/personal_access_tokens"
            echo "  Required scopes: api, write_repository"
        fi
        exit 1
    fi

    if [ -z "$PROJECT_PATH" ]; then
        echo -e "${RED}Error: could not detect project path${NC}"
        echo "  Make sure you have a git remote set:  git remote -v"
        echo "  Or set it manually:"
        echo "    export GITLAB_PROJECT_PATH='myorg/my-repo'  (GitLab)"
        echo "    export GITHUB_PROJECT_PATH='myorg/my-repo'  (GitHub)"
        exit 1
    fi

    if [ "$USE_SONAR" = "1" ]; then
        if [ -z "$SONAR_TOKEN" ]; then
            echo -e "${RED}Error: SONAR_TOKEN not set${NC}"
            echo "  export SONAR_TOKEN='your-token'  (or run: devflow setup)"
            exit 1
        fi
        if [ -z "$PROJECT_KEY" ]; then
            echo -e "${RED}Error: SONAR_PROJECT_KEY not set${NC}"
            echo "  export SONAR_PROJECT_KEY='myorg_my-repo_abc123'"
            echo "  Find it in: SonarQube → Project → Project Information"
            exit 1
        fi
        if [ -z "$SONAR_HOST" ]; then
            echo -e "${RED}Error: SONAR_HOST not set${NC}"
            echo "  export SONAR_HOST='https://sonarqube.example.com'"
            exit 1
        fi
    fi
}

AI_CMD=""
check_agents() {
    local candidate
    for candidate in "$DEFAULT_AI_CLI" claude codex gemini; do
        [ -z "$candidate" ] && continue
        if command -v "$candidate" &> /dev/null; then
            AI_CMD="$candidate"
            return 0
        fi
    done
    # Sonar fix requires an AI agent — only fail if sonar is enabled
    if [ "$USE_SONAR" = "1" ]; then
        echo -e "${YELLOW}⚠  No supported AI CLI found — AI auto-fix will be skipped${NC}"
        echo "  Install one of:"
        echo "    npm install -g @anthropic-ai/claude-code"
        echo "    npm install -g @openai/codex"
        echo "    npm install -g @google/gemini-cli"
    fi
}

# ── Git operations ─────────────────────────────────────────────────────────────
create_new_branch() {
    echo ""
    echo -e "${CYAN}Let's create a new feature branch${NC}"
    echo ""
    echo -e "${BLUE}Suggested prefixes:${NC}"
    echo "  feat/     - New feature"
    echo "  fix/      - Bug fix"
    echo "  refactor/ - Code refactoring"
    echo "  test/     - Adding tests"
    echo "  docs/     - Documentation"
    echo "  chore/    - Maintenance"
    echo ""

    read -p "Enter new branch name (e.g., feat/user-authentication): " NEW_BRANCH_NAME

    if [ -z "$NEW_BRANCH_NAME" ]; then
        echo -e "${RED}No branch name provided${NC}"
        exit 1
    fi

    if [[ ! "$NEW_BRANCH_NAME" =~ ^[a-zA-Z0-9/_-]+$ ]]; then
        echo -e "${RED}Invalid branch name. Use only letters, numbers, -, _, and /${NC}"
        exit 1
    fi

    if git show-ref --verify --quiet refs/heads/"$NEW_BRANCH_NAME"; then
        echo -e "${RED}Branch '$NEW_BRANCH_NAME' already exists${NC}"
        read -p "Switch to existing branch? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git checkout "$NEW_BRANCH_NAME"
            echo -e "${GREEN}✓ Switched to existing branch: $NEW_BRANCH_NAME${NC}"
        else
            exit 1
        fi
    else
        git checkout -b "$NEW_BRANCH_NAME"
        echo -e "${GREEN}✓ Created and switched to new branch: $NEW_BRANCH_NAME${NC}"
    fi
    echo ""
}

check_git_status() {
    print_step "📋 Step 1: Checking Git Status"

    local CURRENT_BRANCH
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    echo -e "${BLUE}Current branch: ${GREEN}$CURRENT_BRANCH${NC}"
    echo ""

    if [ "$CURRENT_BRANCH" = "$MAIN_BRANCH" ] || [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
        echo -e "${RED}╔════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  ⚠️  DANGER: You're on the main branch!      ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}Direct pushes to '$CURRENT_BRANCH' are not recommended.${NC}"
        echo ""
        echo "  1) Create a new feature branch (recommended)"
        echo "  2) Cancel"
        echo ""
        read -p "Enter choice [1-2]: " -n 1 -r
        echo

        if [[ $REPLY = "1" ]]; then
            create_new_branch
            CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
            echo -e "${BLUE}Now on branch: ${GREEN}$CURRENT_BRANCH${NC}"
            echo ""
        else
            echo -e "${YELLOW}Aborted. Create a feature branch manually:${NC}"
            echo "  git checkout -b feat/your-feature-name"
            exit 0
        fi
    fi

    if git diff --quiet && git diff --staged --quiet; then
        local UNPUSHED_COMMITS
        UNPUSHED_COMMITS=$(git log @{u}.. --oneline 2>/dev/null | wc -l)

        if [ "$UNPUSHED_COMMITS" -gt 0 ]; then
            echo -e "${YELLOW}No new changes in working directory${NC}"
            echo -e "${BLUE}Found $UNPUSHED_COMMITS unpushed commit(s)${NC}"
            echo ""
            git log @{u}.. --oneline
            echo ""
            echo -e "${CYAN}Will push existing commits without creating a new commit${NC}"
            return 1
        else
            echo -e "${YELLOW}No local changes and nothing to push.${NC}"
            echo -e "${CYAN}Checking for existing MR/PR and pipeline...${NC}"
            return 2
        fi
    fi

    echo -e "${GREEN}✓ Changes detected${NC}"
    echo ""
    git status --short
    echo ""
    return 0
}

generate_commit_message_with_ai() {
    local agent="$1"
    local DIFF_SUMMARY
    DIFF_SUMMARY=$(git diff --cached --stat --color=never 2>/dev/null || git diff --stat --color=never | head -20)
    local CHANGED_FILES
    CHANGED_FILES=$(git diff --cached --name-only 2>/dev/null || git diff --name-only)
    local DIFF_CONTENT
    DIFF_CONTENT=$(git diff --cached --unified=3 2>/dev/null || git diff --unified=3)

    local DIFF_LINES
    DIFF_LINES=$(echo "$DIFF_CONTENT" | wc -l)
    if [ "$DIFF_LINES" -gt 500 ]; then
        DIFF_CONTENT=$(echo "$DIFF_CONTENT" | head -500)
        DIFF_CONTENT="$DIFF_CONTENT

... (diff truncated, showing first 500 lines)"
    fi

    local PROMPT
    PROMPT=$(cat <<'PROMPT_END'
Analyze the following git changes and generate a conventional commit message.

REQUIREMENTS:
1. Use conventional commit format: type(scope): subject
2. Types: feat, fix, refactor, perf, style, test, docs, chore, ci, build
3. Keep subject line under 70 characters
4. Subject should be imperative, lowercase, no period
5. Add a brief body if needed (2-3 lines max)
6. Focus on WHAT changed and WHY, not HOW

CHANGED FILES:
CHANGED_FILES_PLACEHOLDER

DIFF SUMMARY:
DIFF_SUMMARY_PLACEHOLDER

CODE CHANGES:
DIFF_CONTENT_PLACEHOLDER

Generate ONLY the commit message in this exact format:
type(scope): subject line

Optional body paragraph explaining the change.

Now generate the commit message for the changes above.
PROMPT_END
)

    PROMPT="${PROMPT//CHANGED_FILES_PLACEHOLDER/$CHANGED_FILES}"
    PROMPT="${PROMPT//DIFF_SUMMARY_PLACEHOLDER/$DIFF_SUMMARY}"
    PROMPT="${PROMPT//DIFF_CONTENT_PLACEHOLDER/$DIFF_CONTENT}"

    local AI_OUTPUT
    set +e
    case "$agent" in
        claude)
            AI_OUTPUT=$(printf '%s\n' "$PROMPT" | claude --model haiku --print 2>&1)
            ;;
        codex)
            AI_OUTPUT=$(codex exec "$PROMPT" 2>&1)
            ;;
        gemini)
            AI_OUTPUT=$(gemini -p "$PROMPT" 2>&1)
            ;;
        *)
            AI_OUTPUT=""
            ;;
    esac
    local AI_STATUS=$?
    set -e

    if [ $AI_STATUS -eq 0 ] && [ -n "$AI_OUTPUT" ]; then
        local COMMIT_MSG
        COMMIT_MSG=$(echo "$AI_OUTPUT" | \
            grep -v "^I'll" | grep -v "^I will" | grep -v "^Here" | \
            grep -v "^Based on" | grep -v "^Analyzing" | grep -v "^Generating" | \
            sed -n '/^[a-z]\+[(:].*$/,$p' | \
            sed '/^$/N;/^\n$/D' | head -20)

        if [ -n "$COMMIT_MSG" ]; then
            echo "$COMMIT_MSG"
            return 0
        fi
    fi

    return 1
}

generate_commit_message_fallback() {
    local CHANGED_FILES
    CHANGED_FILES=$(git diff --cached --name-only 2>/dev/null || git diff --name-only)
    local FILE_COUNT
    FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')
    local DIFF_OUTPUT
    DIFF_OUTPUT=$(git diff --cached 2>/dev/null || git diff)

    local COMMIT_TYPE="feat"
    if   echo "$DIFF_OUTPUT" | grep -qi "fix\|bug\|issue\|error\|patch";         then COMMIT_TYPE="fix"
    elif echo "$DIFF_OUTPUT" | grep -qi "refactor\|restructure\|reorganize";      then COMMIT_TYPE="refactor"
    elif echo "$DIFF_OUTPUT" | grep -qi "test\|spec\|\.test\|\.spec";             then COMMIT_TYPE="test"
    elif echo "$DIFF_OUTPUT" | grep -qi "style\|css\|scss\|tailwind";             then COMMIT_TYPE="style"
    elif echo "$DIFF_OUTPUT" | grep -qi "doc\|readme\|comment";                   then COMMIT_TYPE="docs"
    elif echo "$DIFF_OUTPUT" | grep -qi "perf\|performance\|optimize";            then COMMIT_TYPE="perf"
    fi

    local COMMIT_SCOPE=""
    if   echo "$CHANGED_FILES" | grep -q "^src/features/";  then COMMIT_SCOPE=$(echo "$CHANGED_FILES" | grep "^src/features/" | head -1 | cut -d'/' -f3)
    elif echo "$CHANGED_FILES" | grep -q "^src/components/"; then COMMIT_SCOPE="components"
    elif echo "$CHANGED_FILES" | grep -q "^src/hooks/";      then COMMIT_SCOPE="hooks"
    elif echo "$CHANGED_FILES" | grep -q "^src/utils/";      then COMMIT_SCOPE="utils"
    elif echo "$CHANGED_FILES" | grep -q "^src/api/";        then COMMIT_SCOPE="api"
    fi

    local SUBJECT="update implementation"
    if [ "$FILE_COUNT" -eq 1 ]; then
        local FILENAME
        FILENAME=$(basename "$CHANGED_FILES")
        SUBJECT="update ${FILENAME%.*}"
    fi

    local COMMIT_MSG="$COMMIT_TYPE"
    [ -n "$COMMIT_SCOPE" ] && COMMIT_MSG="$COMMIT_MSG($COMMIT_SCOPE)"
    COMMIT_MSG="$COMMIT_MSG: $SUBJECT"

    local BODY
    if [ "$FILE_COUNT" -le 5 ]; then
        BODY=$(echo "$CHANGED_FILES" | sed 's/^/- /')
    else
        BODY="Updated $FILE_COUNT files across the codebase"
    fi

    cat <<EOF
$COMMIT_MSG

$BODY

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
}

generate_commit_message() {
    if [ -n "$AI_CMD" ]; then
        echo -e "${BLUE}Generating commit message with ${AI_CMD}...${NC}" >&2
        start_spinner "Analyzing changes..."
        local GENERATED_MESSAGE
        GENERATED_MESSAGE=$(generate_commit_message_with_ai "$AI_CMD" 2>&1)
        local cm_status=$?
        stop_spinner

        if [ $cm_status -eq 0 ] && [ -n "$GENERATED_MESSAGE" ]; then
            echo "$GENERATED_MESSAGE"
            return 0
        else
            echo -e "${YELLOW}⚠️  ${AI_CMD} generation failed, using fallback method${NC}" >&2
        fi
    else
        echo -e "${YELLOW}⚠️  No AI CLI found, using fallback method${NC}" >&2
    fi

    generate_commit_message_fallback
}

stage_and_commit() {
    print_step "📝 Step 2: Staging & Committing Changes"

    echo -e "${BLUE}Staging all changes...${NC}"
    git add -A

    local COMMIT_MESSAGE
    COMMIT_MESSAGE=$(generate_commit_message 2>&2)

    echo ""
    echo -e "${CYAN}Generated commit message:${NC}"
    echo "---"
    echo "$COMMIT_MESSAGE"
    echo "---"
    echo ""

    read -p "Use this commit message? (Y/n): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Enter your commit message (end with Ctrl+D):"
        COMMIT_MESSAGE=$(cat)
    fi

    echo -e "${BLUE}Creating commit...${NC}"
    git commit -m "$COMMIT_MESSAGE"
    echo -e "${GREEN}✓ Changes committed${NC}"
}

push_to_remote() {
    print_step "🚀 Step 3: Pushing to Remote"

    local CURRENT_BRANCH
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    echo -e "${BLUE}Pushing branch: ${GREEN}$CURRENT_BRANCH${NC}"

    if ! git rev-parse --abbrev-ref --symbolic-full-name @{u} &>/dev/null; then
        echo -e "${YELLOW}No upstream branch set. Pushing with -u flag${NC}"
        SKIP_SONAR=1 git push -u origin "$CURRENT_BRANCH" 2>&1 || { echo -e "${RED}Push failed${NC}"; exit 1; }
    else
        SKIP_SONAR=1 git push 2>&1 || { echo -e "${RED}Push failed${NC}"; exit 1; }
    fi

    echo -e "${GREEN}✓ Push successful${NC}"
}

sync_with_target_branch() {
    print_step "🔄 Step 3: Syncing with Target Branch"

    local CURRENT_BRANCH
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

    echo -e "${BLUE}Fetching latest target branch:${NC} ${CYAN}origin/$MAIN_BRANCH${NC}"
    git fetch origin "$MAIN_BRANCH" || {
        echo -e "${RED}Failed to fetch origin/$MAIN_BRANCH${NC}"
        exit 1
    }

    echo -e "${BLUE}Merging ${CYAN}origin/$MAIN_BRANCH${NC} ${BLUE}into${NC} ${CYAN}$CURRENT_BRANCH${NC}"
    if git merge --no-edit "origin/$MAIN_BRANCH"; then
        echo -e "${GREEN}✓ Branch synced with origin/$MAIN_BRANCH${NC}"
        return 0
    fi

    echo ""
    echo -e "${RED}Merge conflict detected while syncing with origin/$MAIN_BRANCH${NC}"
    echo -e "${YELLOW}Resolve the conflicts manually, commit the resolution if needed, and run ${CYAN}devflow push${NC}${YELLOW} again.${NC}"
    exit 1
}

# ── MR / PR creation (GitLab + GitHub) ───────────────────────────────────────
check_or_create_mr() {
    print_step "🔀 Step 4: Checking/Creating ${GIT_PROVIDER^} MR/PR"

    local CURRENT_BRANCH
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    local PR_TITLE
    PR_TITLE=$(git log -1 --pretty=%s)

    if [ "$GIT_PROVIDER" = "github" ]; then
        _github_check_or_create_pr "$CURRENT_BRANCH" "$PR_TITLE"
    else
        _gitlab_check_or_create_mr "$CURRENT_BRANCH" "$PR_TITLE"
    fi
}

_gitlab_check_or_create_mr() {
    local CURRENT_BRANCH="$1"
    local MR_TITLE="$2"
    local ENCODED_PROJECT
    ENCODED_PROJECT=$(echo "$PROJECT_PATH" | sed 's/\//%2F/g')
    local ENCODED_BRANCH
    ENCODED_BRANCH=$(echo "$CURRENT_BRANCH" | sed 's/\//%2F/g')

    echo -e "${BLUE}Checking for existing merge requests...${NC}"

    local MR_RESPONSE
    MR_RESPONSE=$(curl -s --header "PRIVATE-TOKEN: $GIT_TOKEN" \
        "$GIT_HOST/api/v4/projects/$ENCODED_PROJECT/merge_requests?source_branch=$ENCODED_BRANCH&state=opened")

    local MR_COUNT
    MR_COUNT=$(echo "$MR_RESPONSE" | grep -o '"iid":[0-9]*' | wc -l)

    if [ "$MR_COUNT" -gt 0 ]; then
        local MR_IID
        MR_IID=$(echo "$MR_RESPONSE" | grep -o '"iid":[0-9]*' | head -1 | cut -d':' -f2)
        local TITLE
        TITLE=$(echo "$MR_RESPONSE" | grep -o '"title":"[^"]*"' | head -1 | cut -d'"' -f4)
        echo -e "${GREEN}✓ Found existing MR: !$MR_IID${NC}"
        echo -e "${CYAN}Title: $TITLE${NC}"
        echo -e "${CYAN}URL: $GIT_HOST/$PROJECT_PATH/-/merge_requests/$MR_IID${NC}"
        return 0
    fi

    echo -e "${YELLOW}No existing MR found. Creating...${NC}"

    local JSON_PAYLOAD
    if [ -n "$PYTHON_CMD" ]; then
        JSON_PAYLOAD=$("$PYTHON_CMD" -c "
import json
print(json.dumps({'source_branch':'$CURRENT_BRANCH','target_branch':'$MAIN_BRANCH','title':'''$MR_TITLE''','description':'Generated with devflow-cli','remove_source_branch':True}))
" 2>/dev/null)
    fi
    [ -z "$JSON_PAYLOAD" ] && \
        JSON_PAYLOAD="{\"source_branch\":\"$CURRENT_BRANCH\",\"target_branch\":\"$MAIN_BRANCH\",\"title\":\"$MR_TITLE\",\"remove_source_branch\":true}"

    local CREATE_RESPONSE HTTP_CODE RESPONSE_BODY
    CREATE_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" --request POST \
        --header "PRIVATE-TOKEN: $GIT_TOKEN" \
        --header "Content-Type: application/json" \
        --data "$JSON_PAYLOAD" \
        "$GIT_HOST/api/v4/projects/$ENCODED_PROJECT/merge_requests")
    HTTP_CODE=$(echo "$CREATE_RESPONSE" | grep "HTTP_CODE:" | cut -d':' -f2)
    RESPONSE_BODY=$(echo "$CREATE_RESPONSE" | sed '/HTTP_CODE:/d')

    local NEW_MR_IID
    NEW_MR_IID=$(echo "$RESPONSE_BODY" | grep -o '"iid":[0-9]*' | head -1 | cut -d':' -f2)
    if [ -n "$NEW_MR_IID" ]; then
        echo -e "${GREEN}✓ Merge request created: !$NEW_MR_IID${NC}"
        echo -e "${CYAN}URL: $GIT_HOST/$PROJECT_PATH/-/merge_requests/$NEW_MR_IID${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not create MR automatically (HTTP $HTTP_CODE)${NC}"
        local ERROR_MSG
        ERROR_MSG=$(echo "$RESPONSE_BODY" | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)
        [ -n "$ERROR_MSG" ] && echo -e "${RED}  $ERROR_MSG${NC}"
        echo -e "${BLUE}Create manually: $GIT_HOST/$PROJECT_PATH/-/merge_requests/new?merge_request[source_branch]=$CURRENT_BRANCH${NC}"
    fi
}

_github_check_or_create_pr() {
    local CURRENT_BRANCH="$1"
    local PR_TITLE="$2"
    local OWNER
    OWNER=$(echo "$PROJECT_PATH" | cut -d'/' -f1)

    echo -e "${BLUE}Checking for existing pull requests...${NC}"

    local LIST_RESPONSE
    LIST_RESPONSE=$(curl -s \
        --header "Authorization: Bearer $GIT_TOKEN" \
        --header "Accept: application/vnd.github+json" \
        "$GIT_HOST/api/v3/repos/$PROJECT_PATH/pulls?head=$OWNER:$CURRENT_BRANCH&state=open" 2>/dev/null || \
        curl -s \
        --header "Authorization: Bearer $GIT_TOKEN" \
        --header "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$PROJECT_PATH/pulls?head=$OWNER:$CURRENT_BRANCH&state=open")

    local PR_NUMBER
    PR_NUMBER=$(echo "$LIST_RESPONSE" | grep -o '"number":[0-9]*' | head -1 | cut -d':' -f2)

    if [ -n "$PR_NUMBER" ]; then
        local PR_EXISTING_TITLE
        PR_EXISTING_TITLE=$(echo "$LIST_RESPONSE" | grep -o '"title":"[^"]*"' | head -1 | cut -d'"' -f4)
        echo -e "${GREEN}✓ Found existing PR: #$PR_NUMBER${NC}"
        echo -e "${CYAN}Title: $PR_EXISTING_TITLE${NC}"
        echo -e "${CYAN}URL: $GIT_HOST/$PROJECT_PATH/pull/$PR_NUMBER${NC}"
        return 0
    fi

    echo -e "${YELLOW}No existing PR found. Creating...${NC}"

    local JSON_PAYLOAD
    if [ -n "$PYTHON_CMD" ]; then
        JSON_PAYLOAD=$("$PYTHON_CMD" -c "
import json
print(json.dumps({'title':'''$PR_TITLE''','head':'$CURRENT_BRANCH','base':'$MAIN_BRANCH','body':'Generated with devflow-cli'}))
" 2>/dev/null)
    fi
    [ -z "$JSON_PAYLOAD" ] && \
        JSON_PAYLOAD="{\"title\":\"$PR_TITLE\",\"head\":\"$CURRENT_BRANCH\",\"base\":\"$MAIN_BRANCH\"}"

    local API_URL="https://api.github.com/repos/$PROJECT_PATH/pulls"
    # Use custom host for GitHub Enterprise
    [[ "$GIT_HOST" != "https://github.com" ]] && API_URL="$GIT_HOST/api/v3/repos/$PROJECT_PATH/pulls"

    local CREATE_RESPONSE HTTP_CODE RESPONSE_BODY
    CREATE_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" --request POST \
        --header "Authorization: Bearer $GIT_TOKEN" \
        --header "Accept: application/vnd.github+json" \
        --header "Content-Type: application/json" \
        --data "$JSON_PAYLOAD" \
        "$API_URL")
    HTTP_CODE=$(echo "$CREATE_RESPONSE" | grep "HTTP_CODE:" | cut -d':' -f2)
    RESPONSE_BODY=$(echo "$CREATE_RESPONSE" | sed '/HTTP_CODE:/d')

    local NEW_PR_NUMBER
    NEW_PR_NUMBER=$(echo "$RESPONSE_BODY" | grep -o '"number":[0-9]*' | head -1 | cut -d':' -f2)
    if [ -n "$NEW_PR_NUMBER" ]; then
        echo -e "${GREEN}✓ Pull request created: #$NEW_PR_NUMBER${NC}"
        echo -e "${CYAN}URL: $GIT_HOST/$PROJECT_PATH/pull/$NEW_PR_NUMBER${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not create PR automatically (HTTP $HTTP_CODE)${NC}"
        local ERROR_MSG
        ERROR_MSG=$(echo "$RESPONSE_BODY" | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)
        [ -n "$ERROR_MSG" ] && echo -e "${RED}  $ERROR_MSG${NC}"
        echo -e "${BLUE}Create manually: $GIT_HOST/$PROJECT_PATH/compare/$MAIN_BRANCH...$CURRENT_BRANCH${NC}"
    fi
}

# ── CI Pipeline (GitLab + GitHub Actions) ────────────────────────────────────
wait_for_pipeline() {
    if [ "$GIT_PROVIDER" = "github" ]; then
        _wait_github_actions
    else
        _wait_gitlab_pipeline
    fi
}

_wait_gitlab_pipeline() {
    local CURRENT_BRANCH CURRENT_SHA ENCODED_PROJECT ENCODED_BRANCH
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    CURRENT_SHA=$(git rev-parse HEAD)
    ENCODED_PROJECT=$(echo "$PROJECT_PATH" | sed 's/\//%2F/g')
    ENCODED_BRANCH=$(echo "$CURRENT_BRANCH" | sed 's/\//%2F/g')

    # ── Debug: show resolved config ────────────────────────────────────────────
    echo -e "${BLUE}  Host:    ${CYAN}$GIT_HOST${NC}"
    echo -e "${BLUE}  Project: ${CYAN}$PROJECT_PATH${NC}"
    echo -e "${BLUE}  Token:   ${CYAN}$([ -n "$GIT_TOKEN" ] && echo "set (${#GIT_TOKEN} chars)" || echo "NOT SET")${NC}"
    echo -e "${BLUE}  Branch:  ${CYAN}$CURRENT_BRANCH${NC}"
    echo -e "${BLUE}  SHA:     ${CYAN}${CURRENT_SHA:0:8}${NC}"
    echo ""

    animated_wait 10 "Waiting for pipeline to initialise"
    clear_animation_line

    local PIPELINE_ID="" PIPELINE_STATUS="" PIPELINE_RESPONSE=""
    local POLL_INTERVAL=10 MAX_WAIT=1800 WAITED=0

    # Try SHA-specific lookup first
    PIPELINE_RESPONSE=$(curl -s --header "PRIVATE-TOKEN: $GIT_TOKEN" \
        "$GIT_HOST/api/v4/projects/$ENCODED_PROJECT/pipelines?ref=$ENCODED_BRANCH&sha=$CURRENT_SHA&per_page=1")
    PIPELINE_ID=$(echo "$PIPELINE_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
    PIPELINE_STATUS=$(echo "$PIPELINE_RESPONSE" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)

    # Fallback: most recent pipeline on this branch (SHA may not be indexed yet)
    if [ -z "$PIPELINE_ID" ]; then
        PIPELINE_RESPONSE=$(curl -s --header "PRIVATE-TOKEN: $GIT_TOKEN" \
            "$GIT_HOST/api/v4/projects/$ENCODED_PROJECT/pipelines?ref=$ENCODED_BRANCH&per_page=1")
        PIPELINE_ID=$(echo "$PIPELINE_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
        PIPELINE_STATUS=$(echo "$PIPELINE_RESPONSE" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
    fi

    if [ -z "$PIPELINE_ID" ]; then
        echo -e "${YELLOW}⚠  No pipeline found after waiting 10 seconds. Exiting.${NC}"
        return 0
    fi

    echo -e "${GREEN}✓ Pipeline found: #$PIPELINE_ID${NC}"

    while [ "$PIPELINE_STATUS" = "running" ] || [ "$PIPELINE_STATUS" = "pending" ] || [ "$PIPELINE_STATUS" = "created" ]; do
        animated_wait $POLL_INTERVAL "Pipeline: $PIPELINE_STATUS | ${WAITED}s elapsed"
        clear_animation_line
        WAITED=$((WAITED + POLL_INTERVAL))
        [ $WAITED -ge $MAX_WAIT ] && echo -e "${RED}Timeout waiting for pipeline${NC}" && return 1
        PIPELINE_RESPONSE=$(curl -s --header "PRIVATE-TOKEN: $GIT_TOKEN" \
            "$GIT_HOST/api/v4/projects/$ENCODED_PROJECT/pipelines/$PIPELINE_ID")
        PIPELINE_STATUS=$(echo "$PIPELINE_RESPONSE" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
        render_live_status "Pipeline status: $PIPELINE_STATUS"
    done
    printf "\r%-100s\r" " " > /dev/tty 2>/dev/null || true

    echo -e "Pipeline finished: ${GREEN}$PIPELINE_STATUS${NC}"
    [ "$PIPELINE_STATUS" = "success" ] && return 0
    return 2
}

_wait_github_actions() {
    local CURRENT_BRANCH CURRENT_SHA
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    CURRENT_SHA=$(git rev-parse HEAD)

    local API_URL="https://api.github.com/repos/$PROJECT_PATH/actions/runs"
    [[ "$GIT_HOST" != "https://github.com" ]] && API_URL="$GIT_HOST/api/v3/repos/$PROJECT_PATH/actions/runs"

    echo -e "${BLUE}Waiting for GitHub Actions (commit: ${CURRENT_SHA:0:8})${NC}"
    animated_wait 15 "Waiting for workflow to start"
    clear_animation_line

    local RUN_ID="" RUN_STATUS="" RUN_CONCLUSION=""
    local CREATION_WAITED=0 CREATION_TIMEOUT=120
    local POLL_INTERVAL=10 MAX_WAIT=1800 WAITED=0

    while [ -z "$RUN_ID" ]; do
        local RUNS_RESPONSE
        RUNS_RESPONSE=$(curl -s \
            --header "Authorization: Bearer $GIT_TOKEN" \
            --header "Accept: application/vnd.github+json" \
            "$API_URL?branch=$CURRENT_BRANCH&per_page=5")
        RUN_ID=$(echo "$RUNS_RESPONSE" | "$PYTHON_CMD" -c "
import json,sys
try:
    data=json.load(sys.stdin)
    for r in data.get('workflow_runs',[]):
        if r.get('head_sha','').startswith('${CURRENT_SHA:0:8}') or r.get('head_sha','')=='$CURRENT_SHA':
            print(r['id']); break
except: pass
" 2>/dev/null || echo "")
        [ -n "$RUN_ID" ] && break
        if [ $CREATION_WAITED -ge $CREATION_TIMEOUT ]; then
            clear_animation_line
            echo -e "${YELLOW}No workflow run found — CI may not be configured${NC}"; return 0
        fi
        animated_wait $POLL_INTERVAL "Waiting for workflow | ${CREATION_WAITED}s elapsed"
        clear_animation_line
        CREATION_WAITED=$((CREATION_WAITED + POLL_INTERVAL))
    done

    echo -e "${GREEN}✓ Workflow run found: #$RUN_ID${NC}"

    RUN_STATUS="in_progress"
    while [ "$RUN_STATUS" = "in_progress" ] || [ "$RUN_STATUS" = "queued" ] || [ "$RUN_STATUS" = "waiting" ]; do
        animated_wait $POLL_INTERVAL "Actions: $RUN_STATUS | ${WAITED}s elapsed"
        clear_animation_line
        WAITED=$((WAITED + POLL_INTERVAL))
        [ $WAITED -ge $MAX_WAIT ] && echo -e "${RED}Timeout waiting for Actions${NC}" && return 1
        local RUN_RESPONSE
        RUN_RESPONSE=$(curl -s \
            --header "Authorization: Bearer $GIT_TOKEN" \
            --header "Accept: application/vnd.github+json" \
            "$API_URL/$RUN_ID")
        RUN_STATUS=$(echo "$RUN_RESPONSE" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
        RUN_CONCLUSION=$(echo "$RUN_RESPONSE" | grep -o '"conclusion":"[^"]*"' | head -1 | cut -d'"' -f4)
        render_live_status "Actions status: $RUN_STATUS"
    done
    printf "\r%-100s\r" " " > /dev/tty 2>/dev/null || true

    echo -e "Workflow finished: ${GREEN}$RUN_CONCLUSION${NC}"
    [ "$RUN_CONCLUSION" = "success" ] && return 0
    return 2
}

fetch_sonar_issues() {
    animated_wait 15 "Waiting for SonarQube to process"
    clear_animation_line

    rm -f "$SONAR_ISSUES_FILE" "$SONAR_PARSED_ISSUES_FILE"

    if ! "$SCRIPT_DIR/sonar-fetch-issues.sh" "$SONAR_ISSUES_FILE"; then
        return 3
    fi

    [ ! -f "$SONAR_ISSUES_FILE" ] && { echo -e "${RED}Sonar issues file was not generated.${NC}"; return 3; }

    local TOTAL=""
    if [ -n "$PYTHON_CMD" ]; then
        TOTAL=$("$PYTHON_CMD" -c "import json, sys; d=json.load(open('$SONAR_ISSUES_FILE')); print(d.get('paging', {}).get('total', 0))" 2>/dev/null || echo "")
    fi
    if [ -z "$TOTAL" ]; then
        TOTAL=$(grep -o '"total":[0-9]*' "$SONAR_ISSUES_FILE" | head -1 | cut -d':' -f2)
    fi

    [ -z "$TOTAL" ] || [ "$TOTAL" = "0" ] && return 1

    local ISSUES_TEXT
    if [ -n "$PYTHON_CMD" ]; then
        ISSUES_TEXT=$("$PYTHON_CMD" -c "
import json, sys
try:
    with open('$SONAR_ISSUES_FILE', 'r') as f:
        data = json.load(f)
    for i, issue in enumerate(data.get('issues', []), 1):
        component = issue.get('component', '').split(':')[-1]
        line = issue.get('line', 'N/A')
        severity = issue.get('severity', 'UNKNOWN')
        message = issue.get('message', 'No message')
        rule = issue.get('rule', '')
        print(f'{i}. [{severity}] {component}:{line}')
        print(f'   Rule: {rule}')
        print(f'   Issue: {message}')
        print()
except Exception as e:
    print(f'Error parsing issues: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null) || ISSUES_TEXT=""
    fi

    if [ -z "$ISSUES_TEXT" ]; then
        ISSUES_TEXT=$(grep -oE '"component":"[^"]*"|"message":"[^"]*"|"severity":"[^"]*"|"line":[0-9]*' "$SONAR_ISSUES_FILE" | \
            paste - - - - | sed 's/"component":"[^:]*://g; s/"//g')
    fi

    echo "$ISSUES_TEXT" > "$SONAR_PARSED_ISSUES_FILE"
    echo "$ISSUES_TEXT"
    return 0
}

build_fix_prompt() {
    local ISSUES
    ISSUES=$(cat "$SONAR_PARSED_ISSUES_FILE")

    cat <<EOF
Fix the following SonarQube issues in the codebase. Follow the project's coding standards and SonarQube rules. After fixing, do NOT commit or push — just fix the code.

Issues to fix:
$ISSUES

Instructions:
1. Read each file mentioned
2. Fix the specific issue at the line number indicated
3. Follow clean code and SonarQube best practices
4. Do not add unnecessary changes
EOF
}

fix_with_agent() {
    echo ""
    local PROMPT
    PROMPT=$(build_fix_prompt)

    if [ -z "$AI_CMD" ]; then
        echo -e "${YELLOW}No AI CLI found. Skipping auto-fix.${NC}"
        echo "  Install with npm:"
        echo "    npm install -g @anthropic-ai/claude-code"
        echo "    npm install -g @openai/codex"
        echo "    npm install -g @google/gemini-cli"
        return 1
    fi

    local AGENT_LABEL="Claude Code"
    [ "$AI_CMD" = "codex" ] && AGENT_LABEL="Codex"
    [ "$AI_CMD" = "gemini" ] && AGENT_LABEL="Gemini"

    echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       🤖 $AGENT_LABEL — Live Fix Session         ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""

    local OUTPUT_FILE
    OUTPUT_FILE=$(mktemp)

    set +e
    if [ "$AI_CMD" = "codex" ]; then
        codex exec --full-auto "$PROMPT" 2>&1 | tee "$OUTPUT_FILE"
    elif [ "$AI_CMD" = "gemini" ]; then
        gemini -p "$PROMPT" 2>&1 | tee "$OUTPUT_FILE"
    else
        printf '%s\n' "$PROMPT" | claude --print --dangerously-skip-permissions 2>&1 | tee "$OUTPUT_FILE"
    fi
    local _exit=${PIPESTATUS[1]}
    set -e

    echo ""
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    local AI_OUTPUT
    AI_OUTPUT=$(cat "$OUTPUT_FILE")
    rm -f "$OUTPUT_FILE"

    if [ "$_exit" -eq 0 ] && ! echo "$AI_OUTPUT" | grep -qi "You've hit your limit"; then
        echo -e "${GREEN}✓ $AGENT_LABEL finished processing${NC}"
        return 0
    fi

    echo -e "${YELLOW}$AGENT_LABEL failed or hit a limit.${NC}"
    return 1
}

commit_sonar_fixes() {
    echo -e "${BLUE}Checking for changes...${NC}"

    if git diff --quiet && git diff --staged --quiet; then
        echo -e "${YELLOW}No changes to commit${NC}"
        return 1
    fi

    echo -e "${BLUE}Committing fixes...${NC}"
    git add -A
    git commit -m "fix: resolve SonarQube issues

Co-Authored-By: Workflow Automation (Claude)"

    echo -e "${GREEN}✓ Changes committed${NC}"
    return 0
}

# ── Main workflow ─────────────────────────────────────────────────────────────
main() {
    # ── Argument parsing ───────────────────────────────────────────────────────
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -b|--branch)
                [ -z "$2" ] && { echo "Error: --branch requires a value (e.g. main, master, develop, stage)"; exit 1; }
                MAIN_BRANCH="$2"; MAIN_BRANCH_OVERRIDE="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    print_banner
    check_tokens
    check_agents

    echo -e "${BLUE}Provider:  ${CYAN}$GIT_PROVIDER${NC}"
    echo -e "${BLUE}Target:    ${CYAN}$MAIN_BRANCH${NC}"
    echo -e "${BLUE}SonarQube: ${CYAN}$([ "$USE_SONAR" = "1" ] && echo "enabled" || echo "disabled")${NC}"
    [ -n "${TEST_RUNNER:-}" ] && \
        echo -e "${BLUE}Tests:     ${CYAN}$TEST_RUNNER${NC}$([ "${RUN_TESTS_BEFORE_PUSH:-0}" = "1" ] && echo " (runs before push)" || echo "")"
    echo ""

    # ── Run tests before push (if configured in project settings) ─────────────
    if [ "${RUN_TESTS_BEFORE_PUSH:-0}" = "1" ] && [ -n "${TEST_COMMAND:-}" ]; then
        print_step "🧪 Running tests before push"
        echo -e "${BLUE}  Runner:  ${CYAN}${TEST_RUNNER:-unknown}${NC}"
        echo -e "${BLUE}  Command: ${CYAN}$TEST_COMMAND${NC}"
        echo ""
        set +e
        eval "$TEST_COMMAND"
        TEST_EXIT=$?
        set -e
        if [ $TEST_EXIT -ne 0 ]; then
            echo ""
            echo -e "${RED}╔═══════════════════════════════════════════════════╗${NC}"
            echo -e "${RED}║   ✗ Tests failed — push aborted                  ║${NC}"
            echo -e "${RED}╚═══════════════════════════════════════════════════╝${NC}"
            echo -e "${DIM}  Fix failing tests or set RUN_TESTS_BEFORE_PUSH=0 to skip.${NC}"
            exit 1
        fi
        echo ""
        echo -e "${GREEN}✓ All tests passed${NC}"
    fi

    # check_git_status returns:
    #   0 = has local changes → stage + commit + push + create MR
    #   1 = no local changes, has unpushed commits → push + create MR
    #   2 = nothing to push → find existing MR and jump straight to pipeline
    local GIT_STATUS=0
    set +e; check_git_status; GIT_STATUS=$?; set -e

    if [ $GIT_STATUS -eq 0 ]; then
        stage_and_commit
        sync_with_target_branch
        push_to_remote
        check_or_create_mr
    elif [ $GIT_STATUS -eq 1 ]; then
        sync_with_target_branch
        push_to_remote
        check_or_create_mr
    else
        # No changes, no push — just find the existing MR/PR for this branch
        check_or_create_mr
    fi

    # ── No SonarQube — just wait for CI to pass ────────────────────────────────
    if [ "$USE_SONAR" != "1" ]; then
        print_step "⏳ Waiting for CI to complete"
        local PIPELINE_STATUS=0
        if wait_for_pipeline; then PIPELINE_STATUS=0; else PIPELINE_STATUS=$?; fi

        if [ "$PIPELINE_STATUS" -eq 0 ]; then
            echo ""
            echo -e "${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║   ✓ CI passed! All checks successful             ║${NC}"
            echo -e "${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
        else
            echo ""
            echo -e "${YELLOW}╔═══════════════════════════════════════════════════╗${NC}"
            echo -e "${YELLOW}║   ⚠  CI did not pass — check manually            ║${NC}"
            echo -e "${YELLOW}╚═══════════════════════════════════════════════════╝${NC}"
        fi
        exit 0
    fi

    # ── SonarQube enabled — retry loop ────────────────────────────────────────
    local RETRY_COUNT=0
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        RETRY_COUNT=$((RETRY_COUNT + 1))
        print_step "🔄 Iteration $RETRY_COUNT of $MAX_RETRIES: Pipeline & SonarQube Check"

        local PIPELINE_STATUS=0
        if wait_for_pipeline; then PIPELINE_STATUS=0; else PIPELINE_STATUS=$?; fi

        if [ "$PIPELINE_STATUS" -eq 0 ]; then
            echo ""
            echo -e "${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║   ✓ Pipeline passed! All checks successful       ║${NC}"
            echo -e "${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
            exit 0
        fi

        # PIPELINE_STATUS=1 means hard failure (timeout/error) — warn but still check sonar
        if [ "$PIPELINE_STATUS" -eq 1 ]; then
            echo -e "${YELLOW}⚠  Pipeline check failed — proceeding to SonarQube check anyway${NC}"
        elif [ "$PIPELINE_STATUS" -ne 2 ]; then
            echo -e "${RED}Pipeline returned unexpected status: $PIPELINE_STATUS${NC}"; exit 1
        fi

        echo ""
        echo -e "${BLUE}Fetching SonarQube issues...${NC}"

        local FETCH_STATUS=0
        if fetch_sonar_issues; then FETCH_STATUS=0; else FETCH_STATUS=$?; fi

        if [ "$FETCH_STATUS" -eq 1 ]; then
            echo ""
            echo -e "${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║   ✓ All SonarQube issues resolved!               ║${NC}"
            echo -e "${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
            exit 0
        fi

        if [ "$FETCH_STATUS" -eq 3 ]; then
            echo -e "${RED}SonarQube query failed${NC}"; exit 1
        fi

        echo ""
        echo -e "${BLUE}Attempting to fix SonarQube issues...${NC}"

        if ! fix_with_agent; then
            echo -e "${YELLOW}Auto-fix failed. Manual intervention required.${NC}"; exit 1
        fi

        if ! commit_sonar_fixes; then
            echo -e "${YELLOW}No fixes were made. Manual intervention may be needed.${NC}"; exit 1
        fi

        echo ""
        echo -e "${BLUE}Pushing fixes...${NC}"
        SKIP_SONAR=1 git push

        echo ""
        echo -e "${CYAN}Retrying pipeline check...${NC}"
    done

    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║   ⚠️  Max retries reached. Check manually        ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════╝${NC}"
    exit 1
}

main "$@"
