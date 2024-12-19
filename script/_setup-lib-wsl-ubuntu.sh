#!/bin/bash

# WSL Ubuntu用セットアップスクリプト
# 使用方法: ./setup-lib-wsl-ubuntu.sh [tool-name]
# 
# 利用可能なツール:
#   - nodejs:   Node.js と npm
#   - docker:   Docker と Docker Compose
#   - ansible:  Ansible
#   - aws-cli:  AWS CLI v2
#   - git:      Git (WSL用)
#   - go:       Go言語 (WSL用)
#   - swap:     Swapファイルの設定 (要root権限)
#
# 例: ./setup-lib-wsl-ubuntu.sh nodejs

# 共通の関数
check_root() {
    if [ "$EUID" -eq 0 ]; then 
        echo "rootユーザーでの実行は推奨されません"
        exit 1
    fi
}

print_version() {
    echo "インストールされたバージョン:"
    $@
}

# Swap設定関数
setup_swap() {
    if [ "$EUID" -ne 0 ]; then
        echo "Swap設定にはroot権限が必要です"
        exit 1
    fi

    local SWAP_FILE="/swapfile"
    local SWAP_SIZE="4096"  # 4GB in MB

    echo "Swapファイルのセットアップを開始します..."

    # 既存のswapファイルの確認と削除
    if [ -f "$SWAP_FILE" ]; then
        echo "既存のSwapファイルを削除します..."
        swapoff "$SWAP_FILE" 2>/dev/null || true
        rm "$SWAP_FILE" 2>/dev/null || true
    fi

    # swapファイル作成
    echo "${SWAP_SIZE}MBのSwapファイルを作成中..."
    dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE" status=progress || {
        echo "Swapファイルの作成に失敗しました"
        exit 1
    }

    # 権限設定
    chmod 600 "$SWAP_FILE" || {
        echo "権限設定に失敗しました"
        exit 1
    }

    # swap初期化と有効化
    mkswap "$SWAP_FILE" && swapon "$SWAP_FILE" || {
        echo "Swapの設定に失敗しました"
        exit 1
    }

    # 永続化設定
    if ! grep -q "$SWAP_FILE" /etc/fstab; then
        echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
    fi

    echo "Swap設定の確認:"
    swapon -s
}

# WSL特有の開発ツールのインストール関数
install_git_wsl() {
    echo "Git (WSL)をインストールしています..."
    sudo apt-get update
    sudo apt-get install -y git
    
    # WSL特有の設定
    git config --global core.autocrlf input
    git config --global core.eol lf
    
    print_version git --version
}

install_go_wsl() {
    echo "Go言語 (WSL)をインストールしています..."
    local GO_VERSION="1.22.0"
    wget "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
    rm "go${GO_VERSION}.linux-amd64.tar.gz"
    
    # WSL用のPATH設定
    if ! grep -q "/usr/local/go/bin" ~/.profile; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
        echo 'export GOPATH=$HOME/go' >> ~/.profile
        echo 'export PATH=$PATH:$GOPATH/bin' >> ~/.profile
    fi
    source ~/.profile
    
    # WSL特有の設定
    go env -w GOOS=linux
    
    print_version go version
}

# その他のインストール関数はUbuntu用に修正
install_nodejs() {
    echo "Node.jsをインストールしています..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
    print_version node --version
    print_version npm --version
}

install_docker() {
    echo "Docker & Docker Composeをインストールしています..."
    # WSL2用Dockerインストール
    sudo apt-get update
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Dockerの公式GPGキーを追加
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Dockerリポジトリの追加
    echo \
        "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Dockerインストール
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # 現在のユーザーをdockerグループに追加
    sudo usermod -aG docker $USER
}

install_ansible() {
    echo "Ansibleをインストールしています..."
    sudo apt-get update
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository --yes --update ppa:ansible/ansible
    sudo apt-get install -y ansible
    print_version ansible --version
}

install_aws_cli() {
    echo "AWS CLIをインストールしています..."
    sudo apt-get update
    sudo apt-get install -y unzip
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
    print_version aws --version
}

clear_cache() {
    echo "システムキャッシュをクリアしています..."
    sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches'
}

# メイン処理
main() {
    case "$1" in
        "nodejs")   check_root && install_nodejs ;;
        "docker")   check_root && install_docker ;;
        "ansible")  check_root && install_ansible ;;
        "aws-cli")  check_root && install_aws_cli ;;
        "git")      check_root && install_git_wsl ;;  # WSL用を使用
        "go")       check_root && install_go_wsl ;;   # WSL用を使用
        "swap")     setup_swap ;;
        *)
            echo "使用法: $0 [nodejs|docker|ansible|aws-cli|git|go|swap]"
            exit 1
            ;;
    esac

    clear_cache
    echo "インストールが完了しました"
}

main "$@"
