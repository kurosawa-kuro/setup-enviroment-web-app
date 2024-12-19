#!/bin/bash

# Configuration flags
INSTALL_SYSTEM_UPDATES=false
INSTALL_DEV_TOOLS=true
INSTALL_POSTGRESQL=true
INSTALL_PGADMIN=true

# Database configuration
DATABASE_DB=dev_db
DATABASE_USER=postgres
DATABASE_PASSWORD=postgres
PGADMIN_EMAIL="admin@example.com"
PGADMIN_PASSWORD="adminpassword"

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

# PostgreSQLのインストールと設定
if [ "$INSTALL_POSTGRESQL" = true ]; then
    if ! command -v psql &>/dev/null; then
        echo "Installing PostgreSQL..."
        
        # PostgreSQL公式リポジトリの追加
        dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
        
        # デフォルトのPostgreSQLモジュールを無効化
        dnf -qy module disable postgresql
        
        # PostgreSQL 15のインストール
        dnf install -y postgresql15-server postgresql15
        
        # PostgreSQLの初期化
        /usr/pgsql-15/bin/postgresql-15-setup initdb
        
        # PostgreSQL設定の変更
        PG_HBA_CONF="/var/lib/pgsql/15/data/pg_hba.conf"
        POSTGRESQL_CONF="/var/lib/pgsql/15/data/postgresql.conf"
        
        # リッスンアドレスの設定
        sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" $POSTGRESQL_CONF
        
        # 認証方式の変更
        sed -i 's/ident/md5/g' $PG_HBA_CONF
        echo "host    all             all             0.0.0.0/0               md5" >> $PG_HBA_CONF
        
        # postgresユーザーのパスワード設定
        echo "postgres:$DATABASE_PASSWORD" | sudo chpasswd

        # PostgreSQLの起動
        systemctl enable postgresql-15
        systemctl start postgresql-15
        
        # データベースの存在確認と作成
        if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DATABASE_DB"; then
            echo "Creating database $DATABASE_DB..."
            sudo -u postgres psql -c "CREATE DATABASE $DATABASE_DB;"
        else
            echo "Database $DATABASE_DB already exists."
        fi
        
        # PostgreSQLユーザーのパスワード設定
        sudo -u postgres psql -c "ALTER USER $DATABASE_USER WITH PASSWORD '$DATABASE_PASSWORD';"
        
        echo "PostgreSQL installation and setup completed."
    else
        echo "PostgreSQL is already installed."
    fi
fi

# pgAdminのインストール
if [ "$INSTALL_PGADMIN" = true ]; then
    if ! rpm -q pgadmin4-web &>/dev/null; then
        echo "Installing pgAdmin..."
        
        # 必要なリポジトリの有効化
        dnf install -y dnf-utils
        dnf config-manager --set-enabled crb
        
        # 依存関係のインストール
        dnf install -y httpd python3-mod_wsgi python3-pip
        
        # pgAdmin4のインストール
        dnf install -y pgadmin4-web
        
        # Apacheの設定
        if [ ! -f "/etc/httpd/conf.d/pgadmin4.conf" ]; then
            cat > /etc/httpd/conf.d/pgadmin4.conf << 'EOL'
LoadModule wsgi_module modules/mod_wsgi.so
WSGIDaemonProcess pgadmin processes=1 threads=25 python-home=/usr/local
WSGIScriptAlias /pgadmin4 /usr/lib/python3.9/site-packages/pgadmin4/pgAdmin4.wsgi

<Directory /usr/lib/python3.9/site-packages/pgadmin4>
    WSGIProcessGroup pgadmin
    WSGIApplicationGroup %{GLOBAL}
    Require all granted
</Directory>
EOL
        fi

        # SELinuxの設定
        setsebool -P httpd_can_network_connect on
        
        # 必要なディレクトリの作成と権限設定
        mkdir -p /var/lib/pgadmin
        mkdir -p /var/log/pgadmin
        chown -R apache:apache /var/lib/pgadmin
        chown -R apache:apache /var/log/pgadmin
        
        # pgAdmin4の初期セットアップ
        if [ ! -f "/var/lib/pgadmin/pgadmin4.db" ]; then
            echo "PGADMIN_SETUP_EMAIL=$PGADMIN_EMAIL" > /etc/pgadmin4/pgadmin4.conf
            echo "PGADMIN_SETUP_PASSWORD=$PGADMIN_PASSWORD" >> /etc/pgadmin4/pgadmin4.conf
            python3 /usr/lib/python3.9/site-packages/pgadmin4-web/setup.py
        fi
        
        # Apacheの起動
        systemctl enable httpd
        systemctl restart httpd
        
        echo "pgAdmin installation completed. Please access http://your-server-ip/pgadmin4"
        echo "Login with email: $PGADMIN_EMAIL and password: $PGADMIN_PASSWORD"
    else
        echo "pgAdmin is already installed."
    fi
fi

# インストールされたバージョンの確認
echo "Checking installed versions..."
[ "$INSTALL_POSTGRESQL" = true ] && [ -x "$(command -v psql)" ] && echo "PostgreSQL version: $(psql --version)"

# メタデータの確認
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/region)

echo "Instance ID: $INSTANCE_ID"
echo "Region: $REGION"
echo "End: User data script execution - $(date)"
