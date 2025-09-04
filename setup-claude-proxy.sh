#!/bin/bash

# Setup script for Claude Code to use the Anthropic proxy

echo "Claude Code Proxy Setup"
echo "====================="
echo ""

# Check if proxy is running
if ! curl -s http://localhost:9001/health > /dev/null 2>&1; then
    echo "⚠️  Warning: The Anthropic proxy doesn't appear to be running on port 9001"
    echo "   Please start the proxy from the menu bar app first."
    echo ""
fi

# Create shell function
echo "Adding claude-tracked alias to your shell..."

SHELL_RC=""
if [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
else
    echo "⚠️  Could not find .zshrc or .bashrc"
    echo "   Please add this manually to your shell configuration:"
    echo ""
    echo "   export ANTHROPIC_BASE_URL=\"http://localhost:9001\""
    echo "   alias claude-tracked='ANTHROPIC_BASE_URL=\"http://localhost:9001\" claude'"
    exit 1
fi

# Check if alias already exists
if grep -q "claude-tracked" "$SHELL_RC"; then
    echo "✅ claude-tracked alias already exists in $SHELL_RC"
else
    echo "" >> "$SHELL_RC"
    echo "# Claude Code proxy configuration" >> "$SHELL_RC"
    echo "alias claude-tracked='ANTHROPIC_BASE_URL=\"http://localhost:9001\" claude'" >> "$SHELL_RC"
    echo "✅ Added claude-tracked alias to $SHELL_RC"
fi

echo ""
echo "Setup complete! 🎉"
echo ""
echo "Usage:"
echo "  claude-tracked    # Launch Claude Code with proxy tracking"
echo "  claude           # Launch Claude Code without tracking (normal)"
echo ""
echo "Note: Restart your terminal or run 'source $SHELL_RC' to use the new alias."
echo ""
echo "To configure other tools:"
echo "  export ANTHROPIC_BASE_URL=\"http://localhost:9001\""
echo ""