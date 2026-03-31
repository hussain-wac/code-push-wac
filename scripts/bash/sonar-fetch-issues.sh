#!/bin/bash

# SonarQube Issue Fetcher
# Fetches issues from SonarQube API for the current project
#
# Usage:
#   ./sonar-fetch-issues.sh                          # all project issues
#   ./sonar-fetch-issues.sh --branch feature/my-br  # branch-specific issues
#   ./sonar-fetch-issues.sh --issue AX1a2b3c         # specific issue key
#   ./sonar-fetch-issues.sh --output /tmp/my.json    # custom output file
#   ./sonar-fetch-issues.sh --checklist              # print numbered checklist
#   ./sonar-fetch-issues.sh [output-file]            # legacy positional arg

set -e

# ── Configuration & Environment ───────────────────────────────────────────────
_PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
_DEVFLOW_JSON="${_PROJECT_ROOT}/.devflow/devflow-project-setting.json"
_LEGACY_DEVFLOW_JSON="${_PROJECT_ROOT}/.devflow.json"
_PYTHON_EARLY=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")

[ -f "$_DEVFLOW_JSON" ] || _DEVFLOW_JSON="$_LEGACY_DEVFLOW_JSON"

# Load profile vars helper
load_profile_vars() {
    local var_name="$1"
    if [ -z "${!var_name}" ] || [[ "${!var_name}" == *"example.com"* ]]; then
        local profiles=("$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bash_profile")
        for profile in "${profiles[@]}"; do
            if [ -f "$profile" ]; then
                local line=$(grep "export $var_name=" "$profile" | tail -1)
                if [ -n "$line" ]; then
                    local val=$(echo "$line" | cut -d'=' -f2- | sed "s/^'//; s/'$//; s/^\"//; s/\"$//")
                    if [ -n "$val" ] && [[ "$val" != *"example.com"* ]]; then
                        export "$var_name"="$val"
                        return 0
                    fi
                fi
            fi
        done
    fi
}

load_profile_vars "SONAR_HOST"
load_profile_vars "SONAR_TOKEN"
load_profile_vars "SONAR_PROJECT_KEY"

# Fallbacks
SONAR_HOST="${SONAR_HOST:-https://sonarqube.wachost.com}"
SONAR_HOST="${SONAR_HOST%/}" # Remove trailing slash

if [ -f "$_DEVFLOW_JSON" ] && [ -n "$_PYTHON_EARLY" ]; then
    _cfg_sonar_key=$("$_PYTHON_EARLY" -c "import json; d=json.load(open('$_DEVFLOW_JSON')); print(d.get('sonar',{}).get('projectKey',''))" 2>/dev/null || echo "")
    [ -n "$_cfg_sonar_key" ]  && [ -z "${SONAR_PROJECT_KEY:-}" ]    && SONAR_PROJECT_KEY="$_cfg_sonar_key"
fi

PROJECT_KEY="${SONAR_PROJECT_KEY:-}"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Argument Parsing ─────────────────────────────────────────────────────────
BRANCH_FILTER=""
ISSUE_FILTER=""
TMPDIR="${TMPDIR:-/tmp}"
OUTPUT_FILE="${TMPDIR}/sonar-issues.json"
CHECKLIST_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)
      BRANCH_FILTER="$2"
      shift 2
      ;;
    --issue|--issues)
      ISSUE_FILTER="$2"
      shift 2
      ;;
    --output|-o)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --checklist)
      CHECKLIST_MODE=true
      shift
      ;;
    -*)
      echo -e "${RED}Unknown option: $1${NC}" >&2
      exit 1
      ;;
    *)
      OUTPUT_FILE="$1"
      shift
      ;;
  esac
done

# ── Token check ───────────────────────────────────────────────────────────────
if [ -z "$SONAR_TOKEN" ]; then
    echo -e "${RED}Error: SONAR_TOKEN environment variable is not set${NC}"
    echo "  Please run: devflow setup"
    exit 1
fi

if [ -z "$PROJECT_KEY" ]; then
    echo -e "${RED}Error: SONAR_PROJECT_KEY not set${NC}"
    echo "  Please run: devflow project-setup"
    exit 1
fi

# ── URL Encoding Helper ──────────────────────────────────────────────────────
urlencode() {
    if [ -n "$_PYTHON_EARLY" ]; then
        "$_PYTHON_EARLY" -c "import urllib.parse, sys; print(urllib.parse.quote(sys.stdin.read().strip(), safe=''))" <<< "$1"
    else
        echo "$1" | sed 's/\//%2F/g; s/:/%3A/g; s/ /%20/g'
    fi
}

# ── Build API URL ─────────────────────────────────────────────────────────────
ENCODED_PROJECT=$(urlencode "$PROJECT_KEY")
# resolved=false covers OPEN, CONFIRMED, REOPENED, TO_REVIEW, IN_PROGRESS
# Increased ps to 500 to capture more issues in one go
ISSUES_URL="$SONAR_HOST/api/issues/search?componentKeys=$ENCODED_PROJECT&resolved=false&ps=500&s=SEVERITY&asc=false"

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
FINAL_BRANCH="${BRANCH_FILTER:-$CURRENT_BRANCH}"

if [ -n "$FINAL_BRANCH" ] && [ "$FINAL_BRANCH" != "HEAD" ]; then
    ENCODED_BRANCH=$(urlencode "$FINAL_BRANCH")
    ISSUES_URL="${ISSUES_URL}&branch=${ENCODED_BRANCH}"
fi

if [ -n "$ISSUE_FILTER" ]; then
    ENCODED_ISSUE=$(urlencode "$ISSUE_FILTER")
    ISSUES_URL="${ISSUES_URL}&issues=${ENCODED_ISSUE}"
fi

# ── Display header ────────────────────────────────────────────────────────────
echo -e "${BLUE}Fetching SonarQube issues...${NC}"
echo "  Host:    $SONAR_HOST"
echo "  Project: $PROJECT_KEY"
[ -n "$FINAL_BRANCH" ] && echo "  Branch:  $FINAL_BRANCH"
[ -n "$ISSUE_FILTER" ]   && echo "  Issue:   $ISSUE_FILTER"
echo ""

# ── Fetch from API ────────────────────────────────────────────────────────────
fetch_issues() {
    local url="$1"
    local response=$(curl -sS -L -u "$SONAR_TOKEN:" "$url")
    echo "$response"
}

ISSUES_RESPONSE=$(fetch_issues "$ISSUES_URL")

if [ $? -ne 0 ] || [ -z "$ISSUES_RESPONSE" ]; then
    echo -e "${RED}Error: Failed to connect to SonarQube at $SONAR_HOST${NC}"
    echo "  Check your VPN or SONAR_HOST reachability."
    exit 1
fi

# Parse total issues robustly
get_total() {
    local resp="$1"
    if [ -n "$_PYTHON_EARLY" ]; then
        "$_PYTHON_EARLY" -c "import json, sys; d=json.load(sys.stdin); print(d.get('paging', {}).get('total', d.get('total', 0)))" <<< "$resp" 2>/dev/null || echo "0"
    else
        echo "$resp" | grep -o '"total":[0-9]*' | head -1 | cut -d':' -f2 || echo "0"
    fi
}

TOTAL_ISSUES=$(get_total "$ISSUES_RESPONSE")

# ── Smart Fallback ───────────────────────────────────────────────────────────
# If branch fetch returns 0, try fetching overall project issues
if { [ -z "$TOTAL_ISSUES" ] || [ "$TOTAL_ISSUES" = "0" ]; } && [ -n "$FINAL_BRANCH" ]; then
    echo -e "${YELLOW}No issues found for branch '$FINAL_BRANCH'. Checking overall project...${NC}"
    
    # URL without branch parameter
    OVERALL_URL="$SONAR_HOST/api/issues/search?componentKeys=$ENCODED_PROJECT&resolved=false&ps=500&s=SEVERITY&asc=false"
    FALLBACK_RESPONSE=$(fetch_issues "$OVERALL_URL")
    FALLBACK_TOTAL=$(get_total "$FALLBACK_RESPONSE")
    
    if [ -n "$FALLBACK_TOTAL" ] && [ "$FALLBACK_TOTAL" != "0" ]; then
        ISSUES_RESPONSE="$FALLBACK_RESPONSE"
        TOTAL_ISSUES="$FALLBACK_TOTAL"
        ISSUES_URL="$OVERALL_URL"
        echo -e "${GREEN}✓ Found $TOTAL_ISSUES issues in the overall project.${NC}"
    fi
fi

ERROR_MSG=$(echo "$ISSUES_RESPONSE" | grep -o '"errors":\[.*\]' 2>/dev/null || true)
if [ -n "$ERROR_MSG" ]; then
    echo -e "${RED}SonarQube API Error:${NC}"
    echo "  $ERROR_MSG"
    echo ""
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "  1. Check if the Project Key is correct: $PROJECT_KEY"
    echo "  2. Check if the Branch exists in SonarQube: $FINAL_BRANCH"
    echo "  3. Verify your SONAR_TOKEN has permissions for this project."
    echo ""
    echo -e "${DIM}Queried API: $ISSUES_URL${NC}"
    exit 1
fi

# ── Write JSON output ─────────────────────────────────────────────────────────
echo "$ISSUES_RESPONSE" > "$OUTPUT_FILE"

# Parse total issues robustly
TOTAL_ISSUES="0"
if [ -n "$_PYTHON_EARLY" ]; then
    TOTAL_ISSUES=$("$_PYTHON_EARLY" -c "import json, sys; d=json.load(sys.stdin); print(d.get('paging', {}).get('total', 0))" <<< "$ISSUES_RESPONSE" 2>/dev/null || echo "0")
else
    TOTAL_ISSUES=$(echo "$ISSUES_RESPONSE" | grep -o '"total":[0-9]*' | head -1 | cut -d':' -f2 || echo "0")
fi

if [ -z "$TOTAL_ISSUES" ] || [ "$TOTAL_ISSUES" = "0" ]; then
    echo -e "${GREEN}✓ No issues found! Your code is clean.${NC}"
    echo ""
    echo -e "${YELLOW}Note:${NC} If you see issues on the SonarQube dashboard but not here:"
    echo "  1. Ensure you are using the correct Project Key."
    echo "  2. Ensure the branch '$FINAL_BRANCH' has been scanned (check your pipeline)."
    echo "  3. If this is a new branch, SonarQube might be empty until the first scan completes."
    echo ""
    echo -e "${DIM}Queried API: $ISSUES_URL${NC}"
    exit 0
fi

echo -e "${YELLOW}Found ${BOLD}$TOTAL_ISSUES${NC}${YELLOW} issue(s)${NC}"
echo ""

# ── Severity summary ──────────────────────────────────────────────────────────
BLOCKERS=$(echo "$ISSUES_RESPONSE"  | grep -o '"severity":"BLOCKER"'  | wc -l | tr -d ' ')
CRITICALS=$(echo "$ISSUES_RESPONSE" | grep -o '"severity":"CRITICAL"' | wc -l | tr -d ' ')
MAJORS=$(echo "$ISSUES_RESPONSE"    | grep -o '"severity":"MAJOR"'    | wc -l | tr -d ' ')
MINORS=$(echo "$ISSUES_RESPONSE"    | grep -o '"severity":"MINOR"'    | wc -l | tr -d ' ')
INFOS=$(echo "$ISSUES_RESPONSE"     | grep -o '"severity":"INFO"'     | wc -l | tr -d ' ')

echo "=== Severity Summary ==="
[ "$BLOCKERS" -gt 0 ]  && echo -e "  ${RED}BLOCKER:  $BLOCKERS${NC}"
[ "$CRITICALS" -gt 0 ] && echo -e "  ${RED}CRITICAL: $CRITICALS${NC}"
[ "$MAJORS" -gt 0 ]    && echo -e "  ${YELLOW}MAJOR:    $MAJORS${NC}"
[ "$MINORS" -gt 0 ]    && echo -e "  ${BLUE}MINOR:    $MINORS${NC}"
[ "$INFOS" -gt 0 ]     && echo    "  INFO:     $INFOS"
echo ""

# ── Numbered checklist ────────────────────────────────────────────────────────
if [ -n "$_PYTHON_EARLY" ]; then
    "$_PYTHON_EARLY" - "$OUTPUT_FILE" <<'PYEOF'
import json, sys

SEVERITY_COLOR = {
    "BLOCKER":  "\033[0;31m",
    "CRITICAL": "\033[0;31m",
    "MAJOR":    "\033[1;33m",
    "MINOR":    "\033[0;34m",
    "INFO":     "\033[0m",
}
RESET = "\033[0m"
BOLD  = "\033[1m"

try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except:
    sys.exit(0)

issues = data.get("issues", [])
if not issues:
    sys.exit(0)

print(f"{BOLD}=== Issue Checklist ==={RESET}")
print()
for i, issue in enumerate(issues, 1):
    component = issue.get("component", "").split(":")[-1]
    line      = issue.get("line", "?")
    severity  = issue.get("severity", "UNKNOWN")
    message   = issue.get("message", "No message")
    rule      = issue.get("rule", "")
    key       = issue.get("key", "")
    col       = SEVERITY_COLOR.get(severity, RESET)
    print(f"  [{i}] {col}{severity:<10}{RESET}  {BOLD}{component}:{line}{RESET}")
    print(f"       Rule:  {rule}")
    print(f"       Issue: {message}")
    print(f"       Key:   {key}")
    print()
PYEOF
fi

echo -e "${GREEN}Issues saved to: $OUTPUT_FILE${NC}"
echo ""

# Exit 0 always if fetch was successful, so pipeline can proceed to auto-fix
exit 0
