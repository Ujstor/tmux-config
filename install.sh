#!/bin/bash

# Remove existing tmux installations
if [ -x "$(command -v tmux)" ]; then
    sudo rm -rf /usr/local/bin/tmux
    sudo rm -rf /usr/bin/tmux
    sudo rm -rf /usr/local/share/tmux
    sudo rm -rf /usr/share/tmux
fi

# Remove existing tmux config
if [ -f ~/.tmux.conf ]; then
    rm ~/.tmux.conf
fi

# Install build dependencies
sudo apt update
sudo apt install -y libevent-dev ncurses-dev build-essential bison pkg-config

# Create temporary directory for config
temp_dir=$(mktemp -d)
git clone --depth 1 https://github.com/Ujstor/tmux-config.git "$temp_dir"
cd "$temp_dir"

# Download and build tmux from official source
curl -sSL https://github.com/tmux/tmux/releases/latest/download/tmux-3.5a.tar.gz | tar -xz
cd tmux-3.5a
./configure --prefix=/usr/local
make
sudo make install

sudo ln -sf /usr/local/bin/tmux /usr/bin/tmux

cd "$temp_dir"

# Copy configuration files
cp .tmux.conf ~/.tmux.conf
cp tmux.sh ~/tmux.sh

# Remove existing TPM and install fresh
if [ -d ~/.tmux/plugins/tpm ]; then
    rm -rf ~/.tmux/plugins/tpm
fi

git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

echo "Tmux setup complete."
echo "Install plugins with prefix+I"

rm -rf "$temp_dir"
