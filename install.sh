#!/bin/bash

temp_dir=$(mktemp -d)
git clone --depth 1 https://github.com/Ujstor/tmux-config.git "$temp_dir"

cd "$temp_dir"

if ! command -v tmux &> /dev/null
then
    sudo apt update
    sudo apt install tmux -y
    echo "tmux installed successfully."
else
    echo "tmux is already installed."
fi

if [ -f ~/.tmux.conf ]; then
    rm ~/.tmux.conf
fi

cp .tmux.conf ~/.tmux.conf

if [ -d ~/.tmux/plugins/tpm ]; then
    rm -rf ~/.tmux/plugins/tpm
fi

git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

echo "Tmux setup complete."

rm -rf "$temp_dir"

