#!/bin/bash

setup_ssh_key() {
    echo "Setting up SSH key..."

    if [ -f ~/.ssh/id_rsa ]; then
        mv ~/.ssh/id_rsa ~/.ssh/id_rsa_$(date +%Y%m%d%H%M%S)
    fi
    
    cp config/id_rsa.sample ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa
}

setup_git_config() {
    echo "Configuring Git settings..."
    git config --global user.name "Toshifumi Kurosawa"
    git config --global user.email "kuromailserver@gmail.com"
    
    echo "Checking Git configuration..."
    git config --list
}

test_github_connection() {
    echo "Testing GitHub connection..."
    ssh -T git@github.com
}

clear_cache() {
    echo "Clearing system cache..."
    sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches'
}

# メイン処理を実行
setup_ssh_key
setup_git_config
test_github_connection
clear_cache

echo "Key setup completed!"