#!/bin/bash

# devflow-cli — MR Creation Debugger
# Helps diagnose why MR creation is failing

GITLAB_HOST="${GITLAB_HOST:-https://gitlab.com}"
GITLAB_TOKEN="${GITLAB_TOKEN:-}"
PROJECT_PATH="${GITLAB_PROJECT_PATH:-}"
MAIN_BRANCH="${MAIN_BRANCH:-develop}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  GitLab MR Creation Debugger                    ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

if [ -z "$GITLAB_TOKEN" ]; then
    echo -e "${RED}Error: GITLAB_TOKEN not set${NC}"
    echo "  Run: devflow setup"
    exit 1
fi

if [ -z "$PROJECT_PATH" ]; then
    echo -e "${RED}Error: GITLAB_PROJECT_PATH not set${NC}"
    echo "  Run: devflow setup"
    exit 1
fi

echo -e "${GREEN}✓ GITLAB_TOKEN is set${NC}"
echo ""

PYTHON_CMD=$(command -v python3 || command -v python)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
ENCODED_PROJECT=$(echo "$PROJECT_PATH" | sed 's/\//%2F/g')
ENCODED_BRANCH=$(echo "$CURRENT_BRANCH" | sed 's/\//%2F/g')

echo -e "${BLUE}Current branch:${NC} $CURRENT_BRANCH"
echo -e "${BLUE}Target branch:${NC}  $MAIN_BRANCH"
echo -e "${BLUE}Project:${NC}        $PROJECT_PATH"
echo -e "${BLUE}GitLab host:${NC}    $GITLAB_HOST"
echo ""

# Test 1: Verify API access
echo -e "${CYAN}[Test 1] Verifying GitLab API access...${NC}"
API_TEST=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "$GITLAB_HOST/api/v4/projects/$ENCODED_PROJECT" 2>&1)

if echo "$API_TEST" | grep -q '"id"'; then
    PROJECT_ID=$(echo "$API_TEST" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
    echo -e "${GREEN}✓ API access works! Project ID: $PROJECT_ID${NC}"
else
    echo -e "${RED}✗ API access failed${NC}"
    echo "Response:"
    echo "$API_TEST" | head -10
    exit 1
fi
echo ""

# Test 2: Check token permissions
echo -e "${CYAN}[Test 2] Checking token permissions...${NC}"
USER_INFO=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "$GITLAB_HOST/api/v4/user")

USERNAME=$(echo "$USER_INFO" | grep -o '"username":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -n "$USERNAME" ]; then
    echo -e "${GREEN}✓ Authenticated as: $USERNAME${NC}"
else
    echo -e "${RED}✗ Could not get user info${NC}"
fi
echo ""

# Test 3: Check for existing MRs
echo -e "${CYAN}[Test 3] Checking for existing merge requests...${NC}"
MR_RESPONSE=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "$GITLAB_HOST/api/v4/projects/$ENCODED_PROJECT/merge_requests?source_branch=$ENCODED_BRANCH&state=opened")

MR_COUNT=$(echo "$MR_RESPONSE" | grep -o '"iid":[0-9]*' | wc -l)

if [ "$MR_COUNT" -gt 0 ]; then
    MR_IID=$(echo "$MR_RESPONSE" | grep -o '"iid":[0-9]*' | head -1 | cut -d':' -f2)
    MR_TITLE=$(echo "$MR_RESPONSE" | grep -o '"title":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo -e "${YELLOW}⚠  Existing MR found: !$MR_IID${NC}"
    echo "   Title: $MR_TITLE"
    echo "   URL: $GITLAB_HOST/$PROJECT_PATH/-/merge_requests/$MR_IID"
    echo ""
    echo -e "${CYAN}Note: Cannot create a new MR when one already exists for this branch${NC}"
    exit 0
else
    echo -e "${GREEN}✓ No existing MR found${NC}"
fi
echo ""

# Test 4: Attempt to create MR
echo -e "${CYAN}[Test 4] Attempting to create merge request...${NC}"

MR_TITLE=$(git log -1 --pretty=%s)
echo "Title: $MR_TITLE"
echo ""

JSON_PAYLOAD=$("$PYTHON_CMD" -c "
import json
data = {
    'source_branch': '$CURRENT_BRANCH',
    'target_branch': '$MAIN_BRANCH',
    'title': '''$MR_TITLE''',
    'description': '''Test MR created from debug script''',
    'remove_source_branch': False
}
print(json.dumps(data))
" 2>/dev/null)

echo "JSON Payload:"
echo "$JSON_PAYLOAD" | "$PYTHON_CMD" -m json.tool 2>/dev/null || echo "$JSON_PAYLOAD"
echo ""

CREATE_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" --request POST \
    --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --header "Content-Type: application/json" \
    --data "$JSON_PAYLOAD" \
    "$GITLAB_HOST/api/v4/projects/$ENCODED_PROJECT/merge_requests")

HTTP_CODE=$(echo "$CREATE_RESPONSE" | grep "HTTP_CODE:" | cut -d':' -f2)
RESPONSE_BODY=$(echo "$CREATE_RESPONSE" | sed '/HTTP_CODE:/d')

echo -e "${BLUE}HTTP Status Code:${NC} $HTTP_CODE"
echo ""

if [ "$HTTP_CODE" = "201" ]; then
    NEW_MR_IID=$(echo "$RESPONSE_BODY" | grep -o '"iid":[0-9]*' | head -1 | cut -d':' -f2)
    echo -e "${GREEN}✓ Merge request created successfully!${NC}"
    echo ""
    echo "MR !$NEW_MR_IID"
    echo "URL: $GITLAB_HOST/$PROJECT_PATH/-/merge_requests/$NEW_MR_IID"
else
    echo -e "${RED}✗ MR creation failed${NC}"
    echo ""
    echo -e "${YELLOW}Full API Response:${NC}"
    echo "$RESPONSE_BODY" | "$PYTHON_CMD" -m json.tool 2>/dev/null || echo "$RESPONSE_BODY"
    echo ""

    ERROR_MSG=$(echo "$RESPONSE_BODY" | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$ERROR_MSG" ]; then
        echo -e "${RED}Error Message: $ERROR_MSG${NC}"
    fi

    echo ""
    echo -e "${CYAN}Common Solutions:${NC}"
    echo ""

    if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
        echo -e "${YELLOW}Permission Issue (HTTP $HTTP_CODE):${NC}"
        echo "  1. Verify GITLAB_TOKEN has 'api' scope"
        echo "  2. Regenerate token with correct scopes: api, write_repository"
        echo "  3. Check you have Developer/Maintainer access to the repo"
    elif [ "$HTTP_CODE" = "409" ]; then
        echo -e "${YELLOW}Conflict (HTTP 409):${NC}"
        echo "  • An MR might already exist (check manually)"
        echo "  • Branch might have conflicts with target"
    elif [ "$HTTP_CODE" = "422" ]; then
        echo -e "${YELLOW}Validation Error (HTTP 422):${NC}"
        echo "  • Invalid branch name"
        echo "  • Target branch doesn't exist"
        echo "  • Branch has no commits compared to target"
    else
        echo -e "${YELLOW}HTTP $HTTP_CODE:${NC}"
        echo "  • Check GitLab server status"
        echo "  • Verify API endpoint is correct"
    fi

    echo ""
    echo -e "${BLUE}Manual MR Creation:${NC}"
    echo "  $GITLAB_HOST/$PROJECT_PATH/-/merge_requests/new?merge_request[source_branch]=$CURRENT_BRANCH"
fi

echo ""
