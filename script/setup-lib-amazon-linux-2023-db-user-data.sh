#!/bin/bash

# Configuration flags
INSTALL_SYSTEM_UPDATES=false
INSTALL_DEV_TOOLS=true
INSTALL_AWS_CLI=false
INSTALL_ANSIBLE=false
INSTALL_DOCKER=false
INSTALL_NODEJS=false
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
        sudo -u postgres psql -c "
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
            SELECT 'CREATE DATABASE $DATABASE_DB OWNER $DATABASE_USER'
            WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DATABASE_DB')
            \\gexec
            
            -- 所有者の変更
            ALTER DATABASE $DATABASE_DB OWNER TO $DATABASE_USER;
        "
        
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

# pgAdminのインストール
# pgAdminのインストール
if [ "$INSTALL_PGADMIN" = true ]; then
    if ! rpm -q pgadmin4-web &>/dev/null; then
        echo "Installing pgAdmin..."
        
        # 必要なリポジトリの有効化
        dnf install -y dnf-utils
        dnf config-manager --set-enabled crb

        # 必要なパッケージのインストール
        dnf install -y python3-pip httpd python3-mod_wsgi

        # PostgreSQLリポジトリからpgAdmin4をインストール
        dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
        dnf -qy module disable postgresql
        dnf install -y pgadmin4-web
        
        # Apacheの設定
        if [ ! -f "/etc/httpd/conf.d/pgadmin4.conf" ]; then
            cat > /etc/httpd/conf.d/pgadmin4.conf << 'EOL'
LoadModule wsgi_module modules/mod_wsgi.so
WSGIDaemonProcess pgadmin processes=1 threads=25
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
            python3 /usr/lib/python3.9/site-packages/pgadmin4-web/setup.py
        fi

        # Apacheの起動
        systemctl enable httpd
        systemctl restart httpd
        
        echo "pgAdmin installation completed. Please access http://your-server-ip/pgadmin4 to set up initial admin account."
    else
        echo "pgAdmin is already installed."
    fi
fi


# インストールされたバージョンの確認
echo "Checking installed versions..."
echo "System packages updated: $(date)"
[ "$INSTALL_POSTGRESQL" = true ] && [ -x "$(command -v psql)" ] && echo "PostgreSQL version: $(psql --version)"

# メタデータの確認
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/region)

echo "Instance ID: $INSTANCE_ID"
echo "Region: $REGION"
echo "End: User data script execution - $(date)"
