#!/bin/bash

#===============================================================================
# Claude Code Router Installation Script
#===============================================================================
# Installs and configures @musistudio/claude-code-router for use with local
# LLM servers on Strix Halo.
#
# Prerequisites:
#   - Node.js 18+ installed
#   - npm configured with global prefix (optional but recommended)
#
# Usage:
#   ./install.sh
#===============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo -e "\n${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}\n"
}

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

#===============================================================================
# Check Prerequisites
#===============================================================================

print_header "Checking Prerequisites"

# Check Node.js
if ! command -v node &> /dev/null; then
    print_error "Node.js is not installed. Please install Node.js 18+ first."
    echo "  Ubuntu/Debian: sudo apt install nodejs npm"
    echo "  Or use nvm: https://github.com/nvm-sh/nvm"
    exit 1
fi

NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [[ "$NODE_VERSION" -lt 18 ]]; then
    print_error "Node.js version 18+ required. Current version: $(node -v)"
    exit 1
fi
print_success "Node.js $(node -v) found"

# Check npm
if ! command -v npm &> /dev/null; then
    print_error "npm is not installed."
    exit 1
fi
print_success "npm $(npm -v) found"

#===============================================================================
# Setup npm global prefix (if not already configured)
#===============================================================================

print_header "Configuring npm"

NPM_PREFIX=$(npm config get prefix 2>/dev/null || echo "")

if [[ -z "$NPM_PREFIX" || "$NPM_PREFIX" == "/usr" || "$NPM_PREFIX" == "/usr/local" ]]; then
    print_info "Setting up npm global directory in home folder..."

    mkdir -p "$HOME/.npm-global"
    npm config set prefix "$HOME/.npm-global"

    # Add to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/.npm-global/bin:"* ]]; then
        echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.bashrc"
        export PATH="$HOME/.npm-global/bin:$PATH"
        print_info "Added ~/.npm-global/bin to PATH in .bashrc"
    fi

    NPM_PREFIX="$HOME/.npm-global"
fi

print_success "npm prefix: $NPM_PREFIX"

#===============================================================================
# Install Claude Code Router
#===============================================================================

print_header "Installing Claude Code Router"

print_info "Installing @musistudio/claude-code-router globally..."
npm install -g @musistudio/claude-code-router

if ! command -v ccr &> /dev/null; then
    # Try to find it in npm prefix
    if [[ -f "$NPM_PREFIX/bin/ccr" ]]; then
        print_warning "ccr not in PATH, but found at $NPM_PREFIX/bin/ccr"
        print_info "Please run: source ~/.bashrc"
    else
        print_error "Installation may have failed. Check npm output above."
        exit 1
    fi
else
    print_success "Claude Code Router installed"
    print_info "Version: $(ccr --version 2>/dev/null || echo 'unknown')"
fi

#===============================================================================
# Configure Router
#===============================================================================

print_header "Configuring Router"

CONFIG_DIR="$HOME/.claude-code-router"
CONFIG_FILE="$CONFIG_DIR/config.json"

mkdir -p "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR/logs"

# Copy config from repo
if [[ -f "$SCRIPT_DIR/config.json" ]]; then
    cp "$SCRIPT_DIR/config.json" "$CONFIG_FILE"
    print_success "Copied config.json to $CONFIG_FILE"
else
    print_error "config.json not found in $SCRIPT_DIR"
    exit 1
fi

#===============================================================================
# Create systemd service (optional)
#===============================================================================

print_header "Creating Systemd Service (Optional)"

SERVICE_FILE="$HOME/.config/systemd/user/claude-code-router.service"
mkdir -p "$(dirname "$SERVICE_FILE")"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Claude Code Router - Local LLM Proxy
After=network.target

[Service]
Type=simple
ExecStart=$NPM_PREFIX/bin/node $NPM_PREFIX/lib/node_modules/@musistudio/claude-code-router/dist/cli.js start
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=default.target
EOF

print_success "Created systemd service: $SERVICE_FILE"
print_info "To enable auto-start on boot:"
echo "  systemctl --user enable claude-code-router"
echo "  systemctl --user start claude-code-router"

#===============================================================================
# Summary
#===============================================================================

print_header "Installation Complete"

echo "Claude Code Router has been installed and configured."
echo ""
echo "Configuration file: $CONFIG_FILE"
echo ""
echo "To start the router manually:"
echo "  ccr start"
echo ""
echo "To start the router as a service:"
echo "  systemctl --user start claude-code-router"
echo ""
echo "Before using, make sure to start the LLM servers:"
echo "  cd $REPO_DIR"
echo "  ./start-claude-code-models.sh"
echo ""
echo "Then configure Claude Code to use the router:"
echo "  export ANTHROPIC_BASE_URL=http://localhost:3456"
echo ""
