#!/bin/bash

# Preview the AI-generated commit message for current changes

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   AI-Powered Commit Message Generator — Test    ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

DEFAULT_AI_CLI="${DEVFLOW_DEFAULT_AI_CLI:-}"
AI_CMD=""
for candidate in "$DEFAULT_AI_CLI" claude codex gemini; do
    [ -z "$candidate" ] && continue
    if command -v "$candidate" >/dev/null 2>&1; then
        AI_CMD="$candidate"
        break
    fi
done

if git diff --quiet && git diff --staged --quiet; then
    echo -e "${YELLOW}No changes detected to analyze${NC}"
    echo "Stage some changes first:  git add <files>"
    exit 0
fi

if [ -z "$AI_CMD" ]; then
    echo -e "${RED}Error: no supported AI CLI found${NC}"
    echo "Install one of:"
    echo "  npm install -g @anthropic-ai/claude-code"
    echo "  npm install -g @openai/codex"
    echo "  npm install -g @google/gemini-cli"
    exit 1
fi

echo -e "${BLUE}Analyzing your changes...${NC}"
echo ""
echo -e "${CYAN}Changed files:${NC}"
git diff --cached --name-only 2>/dev/null || git diff --name-only
echo ""
echo -e "${CYAN}Change summary:${NC}"
git diff --cached --stat 2>/dev/null || git diff --stat
echo ""

DIFF_SUMMARY=$(git diff --cached --stat --color=never 2>/dev/null || git diff --stat --color=never | head -20)
CHANGED_FILES=$(git diff --cached --name-only 2>/dev/null || git diff --name-only)
DIFF_CONTENT=$(git diff --cached --unified=3 2>/dev/null || git diff --unified=3)

DIFF_LINES=$(echo "$DIFF_CONTENT" | wc -l)
if [ "$DIFF_LINES" -gt 500 ]; then
    DIFF_CONTENT=$(echo "$DIFF_CONTENT" | head -500)
    DIFF_CONTENT="$DIFF_CONTENT

... (diff truncated, showing first 500 lines)"
fi

PROMPT=$(cat <<'PROMPT_END'
Analyze the following git changes and generate a conventional commit message.

REQUIREMENTS:
1. Use conventional commit format: type(scope): subject
2. Types: feat, fix, refactor, perf, style, test, docs, chore, ci, build
3. Keep subject line under 70 characters
4. Subject should be imperative, lowercase, no period
5. Add a brief body if needed (2-3 lines max)

CHANGED FILES:
CHANGED_FILES_PLACEHOLDER

DIFF SUMMARY:
DIFF_SUMMARY_PLACEHOLDER

CODE CHANGES:
DIFF_CONTENT_PLACEHOLDER

Generate ONLY the commit message. No commentary.
PROMPT_END
)

PROMPT="${PROMPT//CHANGED_FILES_PLACEHOLDER/$CHANGED_FILES}"
PROMPT="${PROMPT//DIFF_SUMMARY_PLACEHOLDER/$DIFF_SUMMARY}"
PROMPT="${PROMPT//DIFF_CONTENT_PLACEHOLDER/$DIFF_CONTENT}"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Generating with ${AI_CMD}...${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ "$AI_CMD" = "claude" ]; then
    GENERATED_MSG=$(printf '%s\n' "$PROMPT" | claude --model haiku --print 2>&1)
elif [ "$AI_CMD" = "codex" ]; then
    GENERATED_MSG=$(codex exec "$PROMPT" 2>&1)
else
    GENERATED_MSG=$(gemini -p "$PROMPT" 2>&1)
fi

if [ $? -eq 0 ] && [ -n "$GENERATED_MSG" ]; then
    echo -e "${GREEN}✓ Generated commit message:${NC}"
    echo ""
    echo "─────────────────────────────────────────────────────"
    echo "$GENERATED_MSG"
    echo "─────────────────────────────────────────────────────"
    echo ""
    echo -e "${BLUE}This message will be used when you run:  ${CYAN}code-push push${NC}"
    echo ""
else
    echo -e "${RED}Failed to generate commit message${NC}"
    exit 1
fi
