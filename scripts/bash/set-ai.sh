#!/bin/bash
# Set default AI CLI for devflow (interactive mode)

CONFIG_DIR="${HOME}/.devflow"
CONFIG_FILE="${CONFIG_DIR}/config.sh"

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

mkdir -p "$CONFIG_DIR"

print_step() {
    echo ""
    echo -e "${BLUE}━━━ $1 ━━━${NC}"
}

check_ai_installed() {
    command -v "$1" >/dev/null 2>&1
}

install_ai() {
    local ai="$1"
    echo ""
    echo -e "${YELLOW}Installing ${ai}...${NC}"
    
    if ! command -v npm >/dev/null 2>&1; then
        echo -e "${RED}✗ npm not found. Please install Node.js first.${NC}"
        return 1
    fi
    
    case "$ai" in
        claude)
            npm install -g @anthropic-ai/claude-code 2>&1
            ;;
        codex)
            npm install -g @openai/codex 2>&1
            ;;
        gemini)
            npm install -g @google/gemini-cli 2>&1
            ;;
    esac
    
    if check_ai_installed "$ai"; then
        echo -e "${GREEN}✓ ${ai} installed successfully!${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to install ${ai}${NC}"
        return 1
    fi
}

print_step "Select Default AI CLI"

echo "Available AI CLIs:"
echo "  [1] claude   - Claude Code (Anthropic)"
echo "  [2] codex    - Codex (OpenAI)"  
echo "  [3] gemini   - Gemini CLI (Google)"
echo ""

# Check what's installed
for ai in claude codex gemini; do
    if check_ai_installed "$ai"; then
        echo -e "    ${GREEN}✓${NC} $ai is installed"
    else
        echo -e "    ${RED}✗${NC} $ai is NOT installed"
    fi
done
echo ""

# Check for existing default
CURRENT=""
if [ -f "$CONFIG_FILE" ]; then
    CURRENT=$(grep "DEVFLOW_DEFAULT_AI_CLI" "$CONFIG_FILE" | cut -d"'" -f2 2>/dev/null || echo "")
fi
if [ -n "$CURRENT" ]; then
    echo -e "Current default: ${GREEN}$CURRENT${NC}"
    echo ""
fi

read -p "Enter choice [1-3]: " -n 1 -r
echo

case "$REPLY" in
    1) AI_CHOICE="claude" ;;
    2) AI_CHOICE="codex" ;;
    3) AI_CHOICE="gemini" ;;
    *) echo -e "${RED}Invalid choice.${NC}"
       exit 1 ;;
esac

# Check if selected AI is installed, offer to install if not
if ! check_ai_installed "$AI_CHOICE"; then
    echo ""
    echo -e "${YELLOW}$AI_CHOICE is not installed.${NC}"
    read -p "Install now? [Y/n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [ -z "$REPLY" ]; then
        install_ai "$AI_CHOICE" || true
    else
        echo -e "${YELLOW}Skipping installation. Will try to use anyway.${NC}"
    fi
fi

# Save config
echo "export DEVFLOW_DEFAULT_AI_CLI='$AI_CHOICE'" > "$CONFIG_FILE"

echo ""
echo -e "${GREEN}✓ Default AI set to: $AI_CHOICE${NC}"
echo ""
echo "Fallback order when $AI_CHOICE hits a limit:"
case "$AI_CHOICE" in
    claude)
        echo "  claude → codex → gemini"
        ;;
    codex)
        echo "  codex → gemini → claude"
        ;;
    gemini)
        echo "  gemini → claude → codex"
        ;;
esac

echo ""
echo -e "${BLUE}To apply in current shell:${NC}"
echo "  source ~/.devflow/config.sh"
