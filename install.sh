#!/bin/bash
set -euo pipefail

# Remove existing tmux installations
if [ -x "$(command -v tmux)" ]; then
    sudo rm -rf /usr/local/bin/tmux /usr/bin/tmux /usr/local/share/tmux /usr/share/tmux
fi

# Remove existing tmux config
[ -f ~/.tmux.conf ] && rm ~/.tmux.conf

# Install build dependencies
sudo apt update
sudo apt install -y libevent-dev libncurses-dev build-essential bison pkg-config

# Create temporary directory for config
temp_dir=$(mktemp -d)
git clone --depth 1 https://github.com/Ujstor/tmux-config.git "$temp_dir"
cd "$temp_dir"

# Resolve latest tmux version from GitHub API
TMUX_VERSION=$(curl -sSL https://api.github.com/repos/tmux/tmux/releases/latest \
    | grep -oP '"tag_name":\s*"\K[^"]+')
echo "Installing tmux ${TMUX_VERSION}"

# Download and build tmux from official source
curl -fsSL "https://github.com/tmux/tmux/releases/download/${TMUX_VERSION}/tmux-${TMUX_VERSION}.tar.gz" | tar -xz
cd "tmux-${TMUX_VERSION}"
./configure --prefix=/usr/local
make
sudo make install
sudo ln -sf /usr/local/bin/tmux /usr/bin/tmux

cd "$temp_dir"
cp .tmux.conf ~/.tmux.conf
cp tmux.sh ~/tmux.sh

# Remove existing TPM and install fresh
[ -d ~/.tmux/plugins/tpm ] && rm -rf ~/.tmux/plugins/tpm
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

echo "Tmux setup complete."
echo "Install plugins with prefix+I"
rm -rf "$temp_dir"
