#!/bin/bash
#
# Yarn Installation Script for Ubuntu 24.04 EC2 DCV Instances
# Run as: ssm-user (with sudo privileges)
# Purpose: Install Yarn system-wide via Corepack (requires Node.js 16.10+)
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on Ubuntu
if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
    log_error "This script is designed for Ubuntu. Detected different OS."
    exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    log_error "Node.js is not installed. Please install Node.js 16.10+ first."
    exit 1
fi

NODE_VERSION=$(node --version | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VERSION" -lt 16 ]; then
    log_error "Node.js 16.10+ required for Corepack. Found: $(node --version)"
    exit 1
fi

log_info "Starting Yarn installation for Ubuntu 24.04..."
log_info "Found Node.js $(node --version)"

# Set up system-wide corepack home directory
COREPACK_HOME="/usr/local/share/corepack"
log_info "Creating system-wide Corepack directory at $COREPACK_HOME..."
sudo mkdir -p "$COREPACK_HOME"
sudo chmod 755 "$COREPACK_HOME"

# Enable corepack (built into Node.js 16.10+) for Yarn
log_info "Enabling Corepack for Yarn..."
sudo corepack enable

# Install/activate Yarn via corepack (use system-wide directory)
log_info "Activating Yarn..."
sudo COREPACK_HOME="$COREPACK_HOME" corepack prepare yarn@stable --activate

# Make corepack cache readable by all users
sudo chmod -R 755 "$COREPACK_HOME"

# Add COREPACK_HOME to system profile so all users can find yarn
log_info "Configuring system-wide COREPACK_HOME..."

# For login shells
sudo tee /etc/profile.d/corepack.sh > /dev/null << EOF
# Corepack configuration for Yarn
export COREPACK_HOME="$COREPACK_HOME"
EOF
sudo chmod 644 /etc/profile.d/corepack.sh

# For non-login interactive shells (e.g., byobu, new terminal tabs)
BASHRC_MARKER="# Corepack configuration for Yarn"
if ! grep -q "$BASHRC_MARKER" /etc/bash.bashrc 2>/dev/null; then
    log_info "Adding Corepack configuration to /etc/bash.bashrc..."
    sudo tee -a /etc/bash.bashrc > /dev/null << EOF

# Corepack configuration for Yarn
export COREPACK_HOME="$COREPACK_HOME"
EOF
fi

# Verify Yarn installation
log_info "Verifying installation..."
if yarn --version; then
    log_info "Yarn installed successfully!"
else
    log_error "Yarn installation verification failed"
    exit 1
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Installation Complete!${NC}"
echo "=========================================="
echo ""
echo "Installed versions:"
echo "  Node.js: $(node --version)"
echo "  Yarn:    $(yarn --version)"
echo ""
echo "All users can now use 'yarn' command."
echo ""
echo "Note: Users already logged in via DCV need to either:"
echo "  - Log out and back in, OR"
echo "  - Run: source /etc/profile.d/corepack.sh"
echo ""
