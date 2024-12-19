#!/bin/bash

# Configuration flags
declare -A INSTALL_FLAGS=(
    [SYSTEM_UPDATES]=false
    [DEV_TOOLS]=true
    [AWS_CLI]=false
    [ANSIBLE]=false
    [DOCKER]=true
    [NODEJS]=true
    [GO]=false
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
    sudo -u postgres psql << EOF
    SELECT pg_sleep(1);
    
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '${DB_CONFIG[USER]}') THEN
            CREATE USER ${DB_CONFIG[USER]} WITH PASSWORD '${DB_CONFIG[PASSWORD]}';
        ELSE
            ALTER USER ${DB_CONFIG[USER]} WITH PASSWORD '${DB_CONFIG[PASSWORD]}';
        END IF;
    END
    \$\$;
    
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_CONFIG[DB]}') THEN
            CREATE DATABASE ${DB_CONFIG[DB]} OWNER ${DB_CONFIG[USER]};
        END IF;
    END
    \$\$;
    
    ALTER DATABASE ${DB_CONFIG[DB]} OWNER TO ${DB_CONFIG[USER]};
EOF

    systemctl restart postgresql
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

# メイン実行関数
main() {
    log "Beginning setup..."

    setup_swap

    if [[ "${INSTALL_FLAGS[DEV_TOOLS]}" = true ]]; then
        install_dev_tools
    fi

    if [[ "${INSTALL_FLAGS[POSTGRESQL]}" = true ]]; then
        install_postgresql
    fi

    if [[ "${INSTALL_FLAGS[DOCKER]}" = true ]]; then
        install_docker
    fi

    if [[ "${INSTALL_FLAGS[NODEJS]}" = true ]]; then
        install_nodejs
    fi

    if [[ "${INSTALL_FLAGS[GO]}" = true ]]; then
        install_go
    fi

    log "Installation complete. Checking versions..."
    check_installed_versions
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
