#!/bin/bash
# Set default AI CLI for devflow

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${HOME}/.devflow"
CONFIG_FILE="${CONFIG_DIR}/config.sh"

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

mkdir -p "$CONFIG_DIR"

show_help() {
    echo "Usage: devflow set-ai [claude|codex|gemini]"
    echo ""
    echo "Set the default AI CLI to use for fixing SonarQube issues."
    echo ""
    echo "Options:"
    echo "  claude   Use Claude Code (default fallback: codex → gemini)"
    echo "  codex    Use Codex (default fallback: gemini → claude)"
    echo "  gemini   Use Gemini CLI (default fallback: claude → codex)"
    echo ""
    echo "If the selected AI hits a limit, devflow will automatically"
    echo "try the next available AI in the fallback chain."
    echo ""
    echo "Examples:"
    echo "  devflow set-ai claude"
    echo "  devflow set-ai codex"
    echo "  devflow set-ai gemini"
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

AI_choice="$1"

if [ -z "$AI_choice" ]; then
    echo -e "${YELLOW}Error: Please specify an AI CLI${NC}"
    show_help
    exit 1
fi

case "$AI_choice" in
    claude|codex|gemini)
        ;;
    *)
        echo -e "${YELLOW}Error: Invalid AI choice: $AI_choice${NC}"
        echo "Valid options: claude, codex, gemini"
        exit 1
        ;;
esac

echo "export DEVFLOW_DEFAULT_AI_CLI='$AI_choice'" > "$CONFIG_FILE"

echo -e "${GREEN}✓ Default AI set to: $AI_choice${NC}"
echo ""
echo "Fallback order when $AI_choice hits a limit:"
case "$AI_choice" in
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

if [ -n "$BASH_VERSION" ]; then
    echo ""
    echo -e "${YELLOW}To apply immediately in current shell:${NC}"
    echo "  source ~/.devflow/config.sh"
fi
