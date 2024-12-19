#!/bin/bash

# Configuration flags
declare -A INSTALL_FLAGS=(
    [SYSTEM_UPDATES]=false
    [DEV_TOOLS]=true
    [AWS_CLI]=false
    [ANSIBLE]=false
    [DOCKER]=true
    [NODEJS]=true
    [GO]=true
    [POSTGRESQL]=true
)

# Database configuration
declare -A DB_CONFIG=(
    [DB]=dev_db
    [USER]=postgres
    [PASSWORD]=postgres
)

# Global constants
readonly SWAP_SIZE="4096"
readonly DOCKER_COMPOSE_VERSION="v2.21.0"
readonly GO_VERSION="1.22.0"

# エラーハンドリングの設定
set -euo pipefail
trap 'error_handler $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "::%s" ${FUNCNAME[@]:-})' ERR

# ユーティリティ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error_handler() {
    local exit_code=$1
    local line_no=$2
    local bash_lineno=$3
    local last_command=$4
    local func_trace=$5
    log "Error occurred in ${func_trace} at line ${line_no}"
    log "Last command: ${last_command}"
    log "Exit code: ${exit_code}"
}

check_command() {
    command -v "$1" &>/dev/null
}

# Swap設定関数
setup_swap() {
    local swap_file="/swapfile"
    
    log "Setting up swap file..."
    if [[ "$EUID" -ne 0 ]]; then
        log "Error: Root privileges required for swap setup"
        return 1
    fi

    if [[ -f "$swap_file" ]]; then
        log "Removing existing swap file..."
        swapoff "$swap_file" 2>/dev/null || true
        rm "$swap_file"
    fi

    log "Creating ${SWAP_SIZE}MB swap file..."
    dd if=/dev/zero of="$swap_file" bs=1M count="$SWAP_SIZE" status=progress
    chmod 600 "$swap_file"
    mkswap "$swap_file"
    swapon "$swap_file"

    if ! grep -q "$swap_file" /etc/fstab; then
        echo "$swap_file none swap sw 0 0" >> /etc/fstab
    fi
}

# 開発ツールのインストール
install_dev_tools() {
    log "Installing development tools..."
    if ! dnf group list installed "Development Tools" &>/dev/null; then
        dnf groupinstall "Development Tools" -y
    fi

    local packages=("git" "make" "jq" "which" "python3-pip" "python3-devel" "libffi-devel" "openssl-devel")
    for pkg in "${packages[@]}"; do
        if ! rpm -q "$pkg" &>/dev/null; then
            dnf install -y "$pkg"
        fi
    done
}

# PostgreSQLのインストール
install_postgresql() {
    if check_command psql; then
        log "PostgreSQL is already installed"
        return 0
    fi

    log "Installing PostgreSQL..."
    dnf install -y postgresql15-server

    if [[ ! -d "/var/lib/pgsql/data/base" ]]; then
        postgresql-setup --initdb
        configure_postgresql
    fi

    systemctl enable postgresql
    systemctl start postgresql

    setup_postgresql_db
}

configure_postgresql() {
    local pg_hba_conf="/var/lib/pgsql/data/pg_hba.conf"
    local postgresql_conf="/var/lib/pgsql/data/postgresql.conf"

    sudo -u postgres bash -c "
        sed -i \"s/#listen_addresses = 'localhost'/listen_addresses = '*'/\" $postgresql_conf
        cp $pg_hba_conf ${pg_hba_conf}.bak
        sed -i 's/ident/md5/g' $pg_hba_conf
        echo 'host    all    all    0.0.0.0/0    md5' >> $pg_hba_conf
    "

    chown postgres:postgres $pg_hba_conf ${pg_hba_conf}.bak $postgresql_conf
    chmod 600 $pg_hba_conf ${pg_hba_conf}.bak $postgresql_conf
}

setup_postgresql_db() {
    # postgresユーザーとしてコマンドを実行
    cd /var/lib/pgsql
    sudo -u postgres bash -c "
        psql -c \"ALTER USER postgres WITH PASSWORD '${DB_CONFIG[PASSWORD]}';\"
        createdb ${DB_CONFIG[DB]}
    "

    log "PostgreSQLのインストールが完了しました"
    log "Database: ${DB_CONFIG[DB]}"
    log "User: ${DB_CONFIG[USER]}"
    log "Password: ${DB_CONFIG[PASSWORD]}"
    log "注意: セ��ュリティグループで5432ポートを開放してください"
}

# Dockerのインストール
install_docker() {
    if check_command docker; then
        log "Docker is already installed"
        return 0
    fi

    log "Installing Docker..."
    dnf install -y docker
    systemctl enable docker
    systemctl start docker

    if ! check_command docker-compose; then
        log "Installing Docker Compose..."
        curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi

    if ! groups ec2-user | grep -q docker; then
        usermod -a -G docker ec2-user
    fi
}

# NodeJSのインストール
install_nodejs() {
    if check_command node; then
        log "NodeJS is already installed"
        return 0
    fi

    log "Installing NodeJS..."
    # Amazon Linux 2023用のNodeSourceリポジトリを追加
    curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
    dnf install -y nodejs

    # npmの最新バージョンをインストール
    npm install -g npm@latest
}

# Go言語のインストール
install_go() {
    if check_command go; then
        log "Go is already installed"
        return 0
    fi

    log "Installing Go language..."
    local go_archive="go${GO_VERSION}.linux-amd64.tar.gz"
    
    # 既存のGoインストールを削除
    rm -rf /usr/local/go
    
    # Goのダウンロードとインストール
    curl -LO "https://go.dev/dl/${go_archive}"
    tar -C /usr/local -xzf "${go_archive}"
    rm "${go_archive}"
    
    # システム全体のPATH設定
    if [ ! -f "/etc/profile.d/go.sh" ]; then
        cat > /etc/profile.d/go.sh << 'EOL'
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
EOL
        chmod 644 /etc/profile.d/go.sh
    fi
    
    # ec2-userのPATH設定
    if ! grep -q "GOROOT" /home/ec2-user/.bashrc; then
        cat >> /home/ec2-user/.bashrc << 'EOL'
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
EOL
    fi
    
    # 権限の設定
    chown -R root:root /usr/local/go
    mkdir -p /home/ec2-user/go
    chown -R ec2-user:ec2-user /home/ec2-user/go
    
    log "Go言語のインストールが完了しました"
    log "Version: $(go version)"
    log "GOROOT: /usr/local/go"
    log "GOPATH: /home/ec2-user/go"
    log "注意: 新しいシェルを開くか、source /etc/profile.d/go.shを実行してください"
}

# インストール情報を保持する配列
declare -A INSTALL_INFO

# メイン実行関数
main() {
    log "Beginning setup..."

    setup_swap

    if [[ "${INSTALL_FLAGS[DEV_TOOLS]}" = true ]]; then
        install_dev_tools
        INSTALL_INFO[DEV_TOOLS]="開発ツール: インストール済み"
    fi

    if [[ "${INSTALL_FLAGS[POSTGRESQL]}" = true ]]; then
        install_postgresql
        INSTALL_INFO[POSTGRESQL]=$(cat << EOF
PostgreSQL情報:
- Database: ${DB_CONFIG[DB]}
- User: ${DB_CONFIG[USER]}
- Password: ${DB_CONFIG[PASSWORD]}
- Port: 5432
- 注意: セキュリティグループで5432ポートを開放してください
EOF
)
    fi

    if [[ "${INSTALL_FLAGS[DOCKER]}" = true ]]; then
        install_docker
        INSTALL_INFO[DOCKER]="Docker: インストール済み"
    fi

    if [[ "${INSTALL_FLAGS[NODEJS]}" = true ]]; then
        install_nodejs
        INSTALL_INFO[NODEJS]="NodeJS: インストール済み ($(node -v))"
    fi

    if [[ "${INSTALL_FLAGS[GO]}" = true ]]; then
        install_go
        INSTALL_INFO[GO]=$(cat << EOF
Go言語情報:
- Version: $(go version)
- GOROOT: /usr/local/go
- GOPATH: /home/ec2-user/go
- 注意: 新しいシェルを開くか、source /etc/profile.d/go.shを実行してください
EOF
)
    fi

    log "Installation complete. Checking versions..."
    check_installed_versions

    # インストール情報のサマリーを表示
    log "============================================"
    log "インストール完了サマリー"
    log "============================================"
    for key in "${!INSTALL_INFO[@]}"; do
        log "${INSTALL_INFO[$key]}"
        log "--------------------------------------------"
    done
    
    log "注意事項:"
    log "1. 各コンポーネントの詳細な設定は上記のログを確認してください"
    log "2. 必要に応じてセキュリティグループの設定を行ってください"
    log "3. 環境変数を反映するには、新しいシェルを開くか、sourceコマンドを実行してください"
}

check_installed_versions() {
    local commands=(
        "git:${INSTALL_FLAGS[DEV_TOOLS]}"
        "make:${INSTALL_FLAGS[DEV_TOOLS]}"
        "docker:${INSTALL_FLAGS[DOCKER]}"
        "docker-compose:${INSTALL_FLAGS[DOCKER]}"
        "node:${INSTALL_FLAGS[NODEJS]}"
        "psql:${INSTALL_FLAGS[POSTGRESQL]}"
    )

    for cmd_pair in "${commands[@]}"; do
        IFS=: read -r cmd flag <<< "$cmd_pair"
        if [[ "$flag" = true ]] && check_command "$cmd"; then
            case "$cmd" in
                git) log "Git version: $(git --version)" ;;
                make) log "Make version: $(make --version | head -n1)" ;;
                docker) log "Docker version: $(docker --version)" ;;
                docker-compose) log "Docker Compose version: $(docker-compose --version)" ;;
                node) log "Node version: $(node -v)" ;;
                psql) log "PostgreSQL version: $(psql --version)" ;;
            esac
        fi
    done
}

# スクリプトの実行
main
log "Setup completed successfully"
