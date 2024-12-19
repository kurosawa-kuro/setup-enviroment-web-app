```bash
#!/bin/bash

# Configuration flags
INSTALL_SYSTEM_UPDATES=false
INSTALL_DEV_TOOLS=true
INSTALL_AWS_CLI=false
INSTALL_ANSIBLE=false
INSTALL_DOCKER=true
INSTALL_NODEJS=true
INSTALL_GO=false
INSTALL_POSTGRESQL=true
INSTALL_PGADMIN=true

# Database configuration
DATABASE_DB=dev_db
DATABASE_USER=postgres
DATABASE_PASSWORD=postgres

# エラー発生時にスクリプトを停止
set -e
echo "Begin: User data script execution - $(date)"

# システムアップデート
if [ "$INSTALL_SYSTEM_UPDATES" = true ]; then
    echo "Checking for system updates..."
    dnf check-update > /dev/null 2>&1 || UPDATE_NEEDED=$?
    if [ "$UPDATE_NEEDED" == "100" ]; then
        echo "Updates available. Updating system packages..."
        dnf update -y
    else
        echo "System is up to date."
    fi
fi

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
setup_swap

# 開発ツールとその他の必要なパッケージのインストール
if [ "$INSTALL_DEV_TOOLS" = true ]; then
    echo "Checking development tools and required packages..."
    
    # Development Toolsグループのチェック
    if ! dnf group list installed "Development Tools" &>/dev/null; then
        echo "Installing Development Tools group..."
        dnf groupinstall "Development Tools" -y
    else
        echo "Development Tools already installed."
    fi
    
    # 個別パッケージのチェックとインストール
    PACKAGES=("git" "make" "jq" "which" "python3-pip" "python3-devel" "libffi-devel" "openssl-devel")
    for pkg in "${PACKAGES[@]}"; do
        if ! rpm -q "$pkg" &>/dev/null; then
            echo "Installing $pkg..."
            dnf install -y "$pkg"
        else
            echo "$pkg already installed."
        fi
    done
fi

# PostgreSQLのインストール
if [ "$INSTALL_POSTGRESQL" = true ]; then
    if ! command -v psql &>/dev/null; then
        echo "Installing PostgreSQL..."
        
        # PostgreSQLのインストール
        dnf install -y postgresql15-server
        
        # PostgreSQLの初期化
        if [ ! -d "/var/lib/pgsql/data/base" ]; then
            postgresql-setup --initdb
            
            # PostgreSQL設定ファイルのパス
            PG_HBA_CONF="/var/lib/pgsql/data/pg_hba.conf"
            POSTGRESQL_CONF="/var/lib/pgsql/data/postgresql.conf"
            
            # PostgreSQLの設定変更（rootユーザーとして実行）
            sudo -u postgres bash -c "
                # リッスンアドレスの設定
                sed -i \"s/#listen_addresses = 'localhost'/listen_addresses = '*'/\" $POSTGRESQL_CONF
                
                # pg_hba.confのバックアップ
                cp $PG_HBA_CONF ${PG_HBA_CONF}.bak
                
                # 認証方式の変更とリモートアクセスの設定
                sed -i 's/ident/md5/g' $PG_HBA_CONF
                echo 'host    all             all             0.0.0.0/0               md5' >> $PG_HBA_CONF
            "
            
            # 設定ファイルの権限確認
            chown postgres:postgres $PG_HBA_CONF ${PG_HBA_CONF}.bak $POSTGRESQL_CONF
            chmod 600 $PG_HBA_CONF ${PG_HBA_CONF}.bak $POSTGRESQL_CONF
        fi
        
        # PostgreSQLの起動
        systemctl enable postgresql
        systemctl start postgresql
        
        # データベースとユーザーの設定
        sudo -u postgres psql << EOF
        -- パスワード設定前の待機
        SELECT pg_sleep(1);
        
        -- ユーザーが存在しない場合は作成
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '$DATABASE_USER') THEN
                CREATE USER $DATABASE_USER WITH PASSWORD '$DATABASE_PASSWORD';
            ELSE
                ALTER USER $DATABASE_USER WITH PASSWORD '$DATABASE_PASSWORD';
            END IF;
        END
        \$\$;
        
        -- データベースが存在しない場合は作成
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DATABASE_DB') THEN
                CREATE DATABASE $DATABASE_DB OWNER $DATABASE_USER;
            END IF;
        END
        \$\$;
        
        -- 所有者の変更
        ALTER DATABASE $DATABASE_DB OWNER TO $DATABASE_USER;
EOF
        
        # 設定の反映のためPostgreSQLを再起動
        systemctl restart postgresql
        
        echo "PostgreSQL installation and setup completed successfully."
        echo "Database: $DATABASE_DB"
        echo "User: $DATABASE_USER"
        echo "Please make sure to update your security group rules if needed."
    else
        echo "PostgreSQL is already installed."
    fi
fi

# AWS CLIのインストール
if [ "$INSTALL_AWS_CLI" = true ]; then
    if ! command -v aws &>/dev/null; then
        echo "Installing AWS CLI..."
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        ./aws/install
        rm -rf aws awscliv2.zip
    else
        echo "AWS CLI is already installed."
    fi
fi

# Ansibleのインストール
if [ "$INSTALL_ANSIBLE" = true ]; then
    if ! command -v ansible &>/dev/null; then
        echo "Installing Ansible..."
        python3 -m pip install ansible
    else
        echo "Ansible is already installed."
    fi
fi

# Dockerのインストール
if [ "$INSTALL_DOCKER" = true ]; then
    if ! command -v docker &>/dev/null; then
        echo "Installing Docker..."
        dnf install -y docker
        systemctl enable docker
        systemctl start docker
        
        echo "Installing Docker Compose..."
        if ! command -v docker-compose &>/dev/null; then
            DOCKER_COMPOSE_VERSION="v2.21.0"
            curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
        fi
        
        # ec2-userをdockerグループに追加（まだ追加されていない場合）
        if ! groups ec2-user | grep -q docker; then
            usermod -a -G docker ec2-user
        fi
    else
        echo "Docker is already installed."
    fi
fi

# Node.jsのインストール
if [ "$INSTALL_NODEJS" = true ]; then
    if ! command -v node &>/dev/null; then
        echo "Installing Node.js..."
        dnf install -y nodejs npm
    else
        echo "Node.js is already installed."
    fi
fi

# Go言語のインストール
if [ "$INSTALL_GO" = true ]; then
    if ! command -v go &>/dev/null; then
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
    else
        echo "Go is already installed."
    fi
fi

# インストールされたバージョンの確認
echo "Checking installed versions..."
echo "System packages updated: $(date)"
[ "$INSTALL_DEV_TOOLS" = true ] && [ -x "$(command -v git)" ] && echo "Git version: $(git --version)"
[ "$INSTALL_DEV_TOOLS" = true ] && [ -x "$(command -v make)" ] && echo "Make version: $(make --version | head -n1)"
[ "$INSTALL_AWS_CLI" = true ] && [ -x "$(command -v aws)" ] && echo "AWS CLI version: $(aws --version)"
[ "$INSTALL_ANSIBLE" = true ] && [ -x "$(command -v ansible)" ] && echo "Ansible version: $(ansible --version | head -n1)"
[ "$INSTALL_DOCKER" = true ] && [ -x "$(command -v docker)" ] && echo "Docker version: $(docker --version)"
[ "$INSTALL_DOCKER" = true ] && [ -x "$(command -v docker-compose)" ] && echo "Docker Compose version: $(docker-compose --version)"
[ "$INSTALL_NODEJS" = true ] && [ -x "$(command -v node)" ] && echo "Node version: $(node -v)"
[ "$INSTALL_GO" = true ] && [ -x "$(command -v go)" ] && echo "Go version: $(go version)"
[ "$INSTALL_POSTGRESQL" = true ] && [ -x "$(command -v psql)" ] && echo "PostgreSQL version: $(psql --version)"

# メタデータの確認
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/region)

echo "Instance ID: $INSTANCE_ID"
echo "Region: $REGION"
echo "End: User data script execution - $(date)"
```
