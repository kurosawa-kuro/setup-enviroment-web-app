#!/bin/bash

# Configuration flags
INSTALL_SYSTEM_UPDATES=false
INSTALL_DEV_TOOLS=true
INSTALL_AWS_CLI=false
INSTALL_ANSIBLE=true
INSTALL_DOCKER=true
INSTALL_NODEJS=true
INSTALL_GO=true

# エラー発生時にスクリプトを停止
set -e
echo "Begin: User data script execution - $(date)"

# システムアップデート
if [ "$INSTALL_SYSTEM_UPDATES" = true ]; then
    echo "Updating system packages..."
    dnf update -y
fi

# 開発ツールとその他の必要なパッケージのインストール
if [ "$INSTALL_DEV_TOOLS" = true ]; then
    echo "Installing development tools and required packages..."
    dnf groupinstall "Development Tools" -y
    dnf install -y \
        git \
        make \
        jq \
        which \
        python3-pip \
        python3-devel \
        libffi-devel \
        openssl-devel
fi

# AWS CLIのインストール
if [ "$INSTALL_AWS_CLI" = true ]; then
    echo "Installing AWS CLI..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
fi

# Ansibleのインストール
if [ "$INSTALL_ANSIBLE" = true ]; then
    echo "Installing Ansible..."
    python3 -m pip install ansible
fi

# Dockerのインストール
if [ "$INSTALL_DOCKER" = true ]; then
    echo "Installing Docker..."
    dnf install -y docker
    systemctl enable docker
    systemctl start docker
    
    echo "Installing Docker Compose..."
    DOCKER_COMPOSE_VERSION="v2.21.0"
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # ec2-userをdockerグループに追加
    usermod -a -G docker ec2-user
fi

# Node.jsのインストール
if [ "$INSTALL_NODEJS" = true ]; then
    echo "Installing Node.js..."
    dnf install -y nodejs npm
fi

# Go言語のインストール
if [ "$INSTALL_GO" = true ]; then
    echo "Installing Go language..."
    wget "https://go.dev/dl/go1.22.0.linux-amd64.tar.gz"
    rm -rf /usr/local/go
    tar -C /usr/local -xzf "go1.22.0.linux-amd64.tar.gz"
    rm "go1.22.0.linux-amd64.tar.gz"
    
    # PATH設定
    if ! grep -q "/usr/local/go/bin" /home/ec2-user/.bashrc; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /home/ec2-user/.bashrc
        echo 'export GOPATH=$HOME/go' >> /home/ec2-user/.bashrc
        echo 'export PATH=$PATH:$GOPATH/bin' >> /home/ec2-user/.bashrc
    fi
    
    # GOROOTとGOPATHの設定
    export GOROOT=/usr/local/go
    export GOPATH=$HOME/go
    export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
fi

# インストールされたバージョンの確認
echo "Checking installed versions..."
echo "System packages updated: $(date)"
[ "$INSTALL_DEV_TOOLS" = true ] && echo "Git version: $(git --version)"
[ "$INSTALL_DEV_TOOLS" = true ] && echo "Make version: $(make --version | head -n1)"
[ "$INSTALL_AWS_CLI" = true ] && echo "AWS CLI version: $(aws --version)"
[ "$INSTALL_ANSIBLE" = true ] && echo "Ansible version: $(ansible --version | head -n1)"
[ "$INSTALL_DOCKER" = true ] && echo "Docker version: $(docker --version)"
[ "$INSTALL_DOCKER" = true ] && echo "Docker Compose version: $(docker-compose --version)"
[ "$INSTALL_NODEJS" = true ] && echo "Node version: $(node -v)"
[ "$INSTALL_GO" = true ] && echo "Go version: $(go version)"

# メタデータの確認
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/region)

echo "Instance ID: $INSTANCE_ID"
echo "Region: $REGION"
echo "End: User data script execution - $(date)"
