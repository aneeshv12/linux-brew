#!/bin/bash
#
# Linuxbrew Installation Script for Ubuntu 24.04 EC2 DCV Instances
# Run as: ssm-user (with sudo privileges)
# Purpose: Install Homebrew system-wide for all users including DCV users
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

log_info "Starting Linuxbrew installation for Ubuntu 24.04 EC2 DCV instance..."

# Install required dependencies
log_info "Installing required dependencies..."
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    procps \
    curl \
    file \
    git \
    locales

# Generate locale if needed
log_info "Ensuring locale is set..."
sudo locale-gen en_US.UTF-8 || true

# Create the linuxbrew user and group for shared installation
BREW_USER="linuxbrew"
BREW_GROUP="linuxbrew"
BREW_HOME="/home/linuxbrew"
BREW_PREFIX="/home/linuxbrew/.linuxbrew"

log_info "Setting up linuxbrew user and group..."

# Create linuxbrew group if it doesn't exist
if ! getent group "$BREW_GROUP" > /dev/null 2>&1; then
    sudo groupadd "$BREW_GROUP"
    log_info "Created group: $BREW_GROUP"
else
    log_info "Group $BREW_GROUP already exists"
fi

# Create linuxbrew user if it doesn't exist
if ! id "$BREW_USER" > /dev/null 2>&1; then
    sudo useradd -r -g "$BREW_GROUP" -d "$BREW_HOME" -s /bin/bash "$BREW_USER"
    log_info "Created user: $BREW_USER"
else
    log_info "User $BREW_USER already exists"
fi

# Create homebrew directory structure
log_info "Creating Homebrew directory structure..."
sudo mkdir -p "$BREW_PREFIX"
sudo chown -R "$BREW_USER:$BREW_GROUP" "$BREW_HOME"
# Make home directory traversable by all users
sudo chmod 755 "$BREW_HOME"

# Add all existing users to the linuxbrew group
log_info "Adding existing users to linuxbrew group..."
for user_home in /home/*; do
    if [ -d "$user_home" ]; then
        username=$(basename "$user_home")
        # Skip the linuxbrew user itself
        if [ "$username" != "$BREW_USER" ] && id "$username" > /dev/null 2>&1; then
            sudo usermod -aG "$BREW_GROUP" "$username"
            log_info "Added $username to $BREW_GROUP group"
        fi
    fi
done

# Also add ssm-user if it exists
if id "ssm-user" > /dev/null 2>&1; then
    sudo usermod -aG "$BREW_GROUP" "ssm-user"
    log_info "Added ssm-user to $BREW_GROUP group"
fi

# Also add root to the group
sudo usermod -aG "$BREW_GROUP" "root" 2>/dev/null || true

# Download and install Homebrew
log_info "Downloading and installing Homebrew..."

# Clone Homebrew (check if it's a valid git repo, not just if directory exists)
if [ -d "$BREW_PREFIX/Homebrew/.git" ]; then
    log_info "Homebrew already cloned, updating..."
    sudo -u "$BREW_USER" git -C "$BREW_PREFIX/Homebrew" pull || true
else
    # Remove directory if it exists but isn't a valid git repo
    if [ -d "$BREW_PREFIX/Homebrew" ]; then
        log_warn "Removing invalid Homebrew directory..."
        sudo rm -rf "$BREW_PREFIX/Homebrew"
    fi
    log_info "Cloning Homebrew..."
    sudo -u "$BREW_USER" git clone https://github.com/Homebrew/brew "$BREW_PREFIX/Homebrew"
fi

# Create the bin directory and symlink
sudo -u "$BREW_USER" mkdir -p "$BREW_PREFIX/bin"
sudo -u "$BREW_USER" ln -sf "$BREW_PREFIX/Homebrew/bin/brew" "$BREW_PREFIX/bin/brew"

# Set proper permissions for group access
log_info "Setting permissions for shared access..."
sudo chown -R "$BREW_USER:$BREW_GROUP" "$BREW_PREFIX"
sudo chmod -R g+rwX "$BREW_PREFIX"

# Set SGID bit so new files inherit the group
sudo find "$BREW_PREFIX" -type d -exec chmod g+s {} \;

# Create the shell profile configuration
BREW_PROFILE_SCRIPT="/etc/profile.d/homebrew.sh"
log_info "Creating system-wide shell profile at $BREW_PROFILE_SCRIPT..."

sudo tee "$BREW_PROFILE_SCRIPT" > /dev/null << 'EOF'
# Homebrew/Linuxbrew configuration
# This file is sourced by /etc/profile for login shells

BREW_PREFIX="/home/linuxbrew/.linuxbrew"

if [ -d "$BREW_PREFIX" ]; then
    export HOMEBREW_PREFIX="$BREW_PREFIX"
    export HOMEBREW_CELLAR="$BREW_PREFIX/Cellar"
    export HOMEBREW_REPOSITORY="$BREW_PREFIX/Homebrew"
    export PATH="$BREW_PREFIX/bin:$BREW_PREFIX/sbin${PATH:+:$PATH}"
    export MANPATH="$BREW_PREFIX/share/man${MANPATH:+:$MANPATH}:"
    export INFOPATH="$BREW_PREFIX/share/info:${INFOPATH:-}"
fi
EOF

sudo chmod 644 "$BREW_PROFILE_SCRIPT"

# Also add to /etc/bash.bashrc for interactive non-login shells
BASHRC_MARKER="# Homebrew/Linuxbrew configuration"
if ! grep -q "$BASHRC_MARKER" /etc/bash.bashrc 2>/dev/null; then
    log_info "Adding Homebrew configuration to /etc/bash.bashrc..."
    sudo tee -a /etc/bash.bashrc > /dev/null << 'EOF'

# Homebrew/Linuxbrew configuration
BREW_PREFIX="/home/linuxbrew/.linuxbrew"
if [ -d "$BREW_PREFIX" ]; then
    export HOMEBREW_PREFIX="$BREW_PREFIX"
    export HOMEBREW_CELLAR="$BREW_PREFIX/Cellar"
    export HOMEBREW_REPOSITORY="$BREW_PREFIX/Homebrew"
    export PATH="$BREW_PREFIX/bin:$BREW_PREFIX/sbin${PATH:+:$PATH}"
    export MANPATH="$BREW_PREFIX/share/man${MANPATH:+:$MANPATH}:"
    export INFOPATH="$BREW_PREFIX/share/info:${INFOPATH:-}"
fi
EOF
fi

# Create configuration for zsh users as well
if [ -d /etc/zsh ]; then
    ZSHRC_GLOBAL="/etc/zsh/zshrc"
    if [ -f "$ZSHRC_GLOBAL" ] && ! grep -q "$BASHRC_MARKER" "$ZSHRC_GLOBAL" 2>/dev/null; then
        log_info "Adding Homebrew configuration to $ZSHRC_GLOBAL..."
        sudo tee -a "$ZSHRC_GLOBAL" > /dev/null << 'EOF'

# Homebrew/Linuxbrew configuration
BREW_PREFIX="/home/linuxbrew/.linuxbrew"
if [ -d "$BREW_PREFIX" ]; then
    export HOMEBREW_PREFIX="$BREW_PREFIX"
    export HOMEBREW_CELLAR="$BREW_PREFIX/Cellar"
    export HOMEBREW_REPOSITORY="$BREW_PREFIX/Homebrew"
    export PATH="$BREW_PREFIX/bin:$BREW_PREFIX/sbin${PATH:+:$PATH}"
    export MANPATH="$BREW_PREFIX/share/man${MANPATH:+:$MANPATH}:"
    export INFOPATH="$BREW_PREFIX/share/info:${INFOPATH:-}"
fi
EOF
    fi
fi

# Add configuration to each existing user's shell rc files
log_info "Updating individual user shell configurations..."
for user_home in /home/*; do
    if [ -d "$user_home" ]; then
        username=$(basename "$user_home")
        if [ "$username" != "$BREW_USER" ] && id "$username" > /dev/null 2>&1; then
            # Update .bashrc
            if [ -f "$user_home/.bashrc" ]; then
                if ! grep -q "$BASHRC_MARKER" "$user_home/.bashrc" 2>/dev/null; then
                    log_info "Updating $user_home/.bashrc..."
                    sudo tee -a "$user_home/.bashrc" > /dev/null << 'EOF'

# Homebrew/Linuxbrew configuration
BREW_PREFIX="/home/linuxbrew/.linuxbrew"
if [ -d "$BREW_PREFIX" ]; then
    eval "$($BREW_PREFIX/bin/brew shellenv)"
fi
EOF
                    sudo chown "$username:$username" "$user_home/.bashrc" 2>/dev/null || true
                fi
            fi

            # Update .zshrc if it exists
            if [ -f "$user_home/.zshrc" ]; then
                if ! grep -q "$BASHRC_MARKER" "$user_home/.zshrc" 2>/dev/null; then
                    log_info "Updating $user_home/.zshrc..."
                    sudo tee -a "$user_home/.zshrc" > /dev/null << 'EOF'

# Homebrew/Linuxbrew configuration
BREW_PREFIX="/home/linuxbrew/.linuxbrew"
if [ -d "$BREW_PREFIX" ]; then
    eval "$($BREW_PREFIX/bin/brew shellenv)"
fi
EOF
                    sudo chown "$username:$username" "$user_home/.zshrc" 2>/dev/null || true
                fi
            fi

            # Update .profile for login shells (DCV often uses this)
            if [ -f "$user_home/.profile" ]; then
                if ! grep -q "$BASHRC_MARKER" "$user_home/.profile" 2>/dev/null; then
                    log_info "Updating $user_home/.profile..."
                    sudo tee -a "$user_home/.profile" > /dev/null << 'EOF'

# Homebrew/Linuxbrew configuration
BREW_PREFIX="/home/linuxbrew/.linuxbrew"
if [ -d "$BREW_PREFIX" ]; then
    export HOMEBREW_PREFIX="$BREW_PREFIX"
    export HOMEBREW_CELLAR="$BREW_PREFIX/Cellar"
    export HOMEBREW_REPOSITORY="$BREW_PREFIX/Homebrew"
    export PATH="$BREW_PREFIX/bin:$BREW_PREFIX/sbin${PATH:+:$PATH}"
    export MANPATH="$BREW_PREFIX/share/man${MANPATH:+:$MANPATH}:"
    export INFOPATH="$BREW_PREFIX/share/info:${INFOPATH:-}"
fi
EOF
                    sudo chown "$username:$username" "$user_home/.profile" 2>/dev/null || true
                fi
            fi
        fi
    fi
done

# Create a skeleton file for new users
SKEL_BASHRC="/etc/skel/.bashrc"
if [ -f "$SKEL_BASHRC" ] && ! grep -q "$BASHRC_MARKER" "$SKEL_BASHRC" 2>/dev/null; then
    log_info "Updating skeleton .bashrc for new users..."
    sudo tee -a "$SKEL_BASHRC" > /dev/null << 'EOF'

# Homebrew/Linuxbrew configuration
BREW_PREFIX="/home/linuxbrew/.linuxbrew"
if [ -d "$BREW_PREFIX" ]; then
    eval "$($BREW_PREFIX/bin/brew shellenv)"
fi
EOF
fi

# Create a script to add new users to the linuxbrew group automatically
log_info "Creating helper script for adding new users to linuxbrew group..."
sudo tee /usr/local/bin/add-user-to-brew > /dev/null << 'EOF'
#!/bin/bash
# Helper script to add a user to the linuxbrew group
# Usage: sudo add-user-to-brew <username>

if [ $# -ne 1 ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

USERNAME="$1"

if ! id "$USERNAME" > /dev/null 2>&1; then
    echo "Error: User $USERNAME does not exist"
    exit 1
fi

usermod -aG linuxbrew "$USERNAME"
echo "Added $USERNAME to linuxbrew group"
echo "User needs to log out and back in for group changes to take effect"
EOF

sudo chmod 755 /usr/local/bin/add-user-to-brew

# Run brew update to initialize
log_info "Initializing Homebrew (this may take a few minutes)..."
sudo -u "$BREW_USER" "$BREW_PREFIX/bin/brew" update --force || true

# Final permission fix
log_info "Final permission adjustments..."
sudo chown -R "$BREW_USER:$BREW_GROUP" "$BREW_PREFIX"
sudo chmod -R g+rwX "$BREW_PREFIX"
sudo find "$BREW_PREFIX" -type d -exec chmod g+s {} \;

# Verify installation
log_info "Verifying installation..."
if sudo -u "$BREW_USER" "$BREW_PREFIX/bin/brew" --version; then
    log_info "Homebrew installed successfully!"
else
    log_error "Homebrew installation verification failed"
    exit 1
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Installation Complete!${NC}"
echo "=========================================="
echo ""
echo "Important notes:"
echo "1. Users need to LOG OUT and LOG BACK IN for group membership to take effect"
echo "2. For DCV users: They must reconnect their DCV session"
echo "3. After re-login, verify with: brew --version"
echo ""
echo "To add future users to brew access, run:"
echo "  sudo add-user-to-brew <username>"
echo ""
echo "To install packages (as any authorized user):"
echo "  brew install <package>"
echo ""
echo "If you encounter permission issues, run:"
echo "  sudo chown -R linuxbrew:linuxbrew /home/linuxbrew/.linuxbrew"
echo "  sudo chmod -R g+rwX /home/linuxbrew/.linuxbrew"
echo ""
