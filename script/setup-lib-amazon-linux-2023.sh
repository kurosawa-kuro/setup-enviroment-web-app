#!/bin/bash

# Amazon Linux 2023用セットアップスクリプト
# 使用方法: ./setup-lib-amazon-linux-2023.sh [tool-name]
# 
# 利用可能なツール:
#   - nodejs:   Node.js と npm
#   - docker:   Docker と Docker Compose
#   - ansible:  Ansible
#   - aws-cli:  AWS CLI v2
#   - git:      Git
#   - go:       Go言語
#   - swap:     Swapファイルの設定 (要root権限)
#
# 例: ./setup-lib-amazon-linux-2023.sh nodejs

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

# 開発ツールのインストール関数
install_nodejs() {
    echo "Node.jsをインストールしています..."
    sudo dnf install -y nodejs npm
    print_version node --version
    print_version npm --version
}

install_docker() {
    echo "Docker & Docker Composeをインストールしています..."
    sudo dnf install -y docker
    sudo systemctl enable docker
    sudo systemctl start docker
    
    sudo dnf install -y docker-compose-plugin
    
    sudo usermod -aG docker $USER
}

install_ansible() {
    echo "Ansibleをインストールしています..."
    sudo dnf install -y ansible
    print_version ansible --version
}

install_aws_cli() {
    echo "AWS CLIをインストールしています..."
    sudo dnf install -y unzip
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
    print_version aws --version
}

install_git() {
    echo "Gitをインストールしています..."
    sudo dnf install -y git
    print_version git --version
}

install_go() {
    echo "Go言語をインストールしています..."
    local GO_VERSION="1.22.0"
    wget "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
    rm "go${GO_VERSION}.linux-amd64.tar.gz"
    
    # PATH設定
    if ! grep -q "/usr/local/go/bin" ~/.bashrc; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    fi
    source ~/.bashrc
    print_version go version
}

clear_cache() {
    echo "システムキャッシュをクリアしています..."
    sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches'
}

# 基本開発ツールのインストール
install_base_tools() {
    echo "基本開発ツールをインストールしています..."
    sudo dnf groupinstall -y "Development Tools"
    sudo dnf install -y \
        vim \
        wget \
        curl \
        tar \
        zip \
        unzip \
        jq \
        tree \
        htop \
        tmux \
        git-lfs \
        python3-pip \
        python3-devel
    
    print_version gcc --version
    print_version python3 --version
}

# セキュリティツールのインストール
install_security_tools() {
    echo "セキュリティツールをインストールしています..."
    sudo dnf install -y \
        openssl \
        openssh-clients \
        ca-certificates \
        gnupg2 \
        fail2ban
        
    # fail2banの有効化
    sudo systemctl enable fail2ban
    sudo systemctl start fail2ban
}

# システム監視ツールのインストール
install_monitoring_tools() {
    echo "システム監視ツールをインストールしています..."
    sudo dnf install -y \
        sysstat \
        iotop \
        nmon \
        net-tools \
        tcpdump \
        lsof
}

# メイン処理
main() {
    case "$1" in
        "nodejs")   check_root && install_nodejs ;;
        "docker")   check_root && install_docker ;;
        "ansible")  check_root && install_ansible ;;
        "aws-cli")  check_root && install_aws_cli ;;
        "git")      check_root && install_git ;;
        "go")       check_root && install_go ;;
        "swap")     setup_swap ;;
        "base")     check_root && install_base_tools ;;
        "security") check_root && install_security_tools ;;
        "monitor")  check_root && install_monitoring_tools ;;
        "all")      
            check_root && \
            install_base_tools && \
            install_security_tools && \
            install_monitoring_tools ;;
        *)
            echo "使用法: $0 [nodejs|docker|ansible|aws-cli|git|go|swap|base|security|monitor|all]"
            exit 1
            ;;
    esac

    clear_cache
    echo "インストールが完了しました"
}

main "$@"
