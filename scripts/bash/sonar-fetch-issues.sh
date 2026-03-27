#!/bin/bash

# SonarQube Issue Fetcher

set -e

SONAR_HOST="${SONAR_HOST:-}"
SONAR_TOKEN="${SONAR_TOKEN:-}"
PROJECT_KEY="${SONAR_PROJECT_KEY:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ -z "$SONAR_TOKEN" ]; then
    echo -e "${RED}Error: SONAR_TOKEN not set${NC}"
    echo "  export SONAR_TOKEN='your-token'"
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

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

echo -e "${BLUE}Fetching SonarQube issues...${NC}"
echo "Host:    $SONAR_HOST"
echo "Project: $PROJECT_KEY"
[ -n "$CURRENT_BRANCH" ] && echo "Branch:  $CURRENT_BRANCH"
echo ""

ISSUES_URL="$SONAR_HOST/api/issues/search?componentKeys=$PROJECT_KEY&statuses=OPEN,CONFIRMED&ps=100&s=SEVERITY&asc=false"
ISSUES_RESPONSE=$(curl -s -u "$SONAR_TOKEN:" "$ISSUES_URL" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$ISSUES_RESPONSE" ]; then
    echo -e "${RED}Error: Failed to fetch issues from SonarQube${NC}"
    exit 1
fi

ERROR_MSG=$(echo "$ISSUES_RESPONSE" | grep -o '"errors":\[.*\]' 2>/dev/null || true)
if [ -n "$ERROR_MSG" ]; then
    echo -e "${RED}API Error: $ERROR_MSG${NC}"
    exit 1
fi

echo "API: $ISSUES_URL"

OUTPUT_FILE="${1:-${TMPDIR:-/tmp}/sonar-issues.json}"
echo "$ISSUES_RESPONSE" > "$OUTPUT_FILE"

TOTAL_ISSUES=$(echo "$ISSUES_RESPONSE" | grep -o '"total":[0-9]*' | head -1 | cut -d':' -f2)

if [ -z "$TOTAL_ISSUES" ] || [ "$TOTAL_ISSUES" = "0" ]; then
    echo -e "${GREEN}No issues found! Your code is clean.${NC}"
    exit 0
fi

echo -e "${YELLOW}Found $TOTAL_ISSUES issue(s)${NC}"
echo ""
echo -e "${GREEN}Issues saved to: $OUTPUT_FILE${NC}"
echo ""
echo "=== Issue Summary ==="

BLOCKERS=$(echo  "$ISSUES_RESPONSE" | grep -o '"severity":"BLOCKER"'   | wc -l)
CRITICALS=$(echo "$ISSUES_RESPONSE" | grep -o '"severity":"CRITICAL"'  | wc -l)
MAJORS=$(echo    "$ISSUES_RESPONSE" | grep -o '"severity":"MAJOR"'     | wc -l)
MINORS=$(echo    "$ISSUES_RESPONSE" | grep -o '"severity":"MINOR"'     | wc -l)
INFOS=$(echo     "$ISSUES_RESPONSE" | grep -o '"severity":"INFO"'      | wc -l)

[ "$BLOCKERS"  -gt 0 ] && echo -e "${RED}  BLOCKER:  $BLOCKERS${NC}"
[ "$CRITICALS" -gt 0 ] && echo -e "${RED}  CRITICAL: $CRITICALS${NC}"
[ "$MAJORS"    -gt 0 ] && echo -e "${YELLOW}  MAJOR:    $MAJORS${NC}"
[ "$MINORS"    -gt 0 ] && echo -e "${BLUE}  MINOR:    $MINORS${NC}"
[ "$INFOS"     -gt 0 ] && echo    "  INFO:     $INFOS"

echo ""
exit 0
