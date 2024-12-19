#!/bin/bash

# Database configuration
DATABASE_DB=dev_db
DATABASE_USER=postgres
DATABASE_PASSWORD=postgres

# エラー発生時にスクリプトを停止
set -e
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# システムの更新
log "システムを更新しています..."
dnf update -y

# PostgreSQLのインストール
log "PostgreSQLをインストールしています..."
dnf install -y postgresql15.x86_64 postgresql15-server

# PostgreSQLの初期化
log "PostgreSQLデータベースを初期化しています..."
postgresql-setup --initdb

# PostgreSQLの設定
log "PostgreSQLを設定しています..."
# 設定ファイルのバックアップ
cp /var/lib/pgsql/data/postgresql.conf /var/lib/pgsql/data/postgresql.conf.bak
cp /var/lib/pgsql/data/pg_hba.conf /var/lib/pgsql/data/pg_hba.conf.bak

# リッスンアドレスの設定
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /var/lib/pgsql/data/postgresql.conf

# 認証設定の変更
sed -i 's/ident/md5/g' /var/lib/pgsql/data/pg_hba.conf
echo "host    all             all             0.0.0.0/0               md5" >> /var/lib/pgsql/data/pg_hba.conf

# PostgreSQLの起動と有効化
log "PostgreSQLサービスを起動しています..."
systemctl start postgresql
systemctl enable postgresql

# postgresユーザーのパスワード設定
log "データベースユーザーを設定しています..."
# システムユーザーのパスワード設定
echo "postgres:${DATABASE_PASSWORD}" | chpasswd

# データベース管理者のパスワード設定
su - postgres -c "psql -c \"ALTER USER postgres WITH PASSWORD '${DATABASE_PASSWORD}';\""

# データベースの作成
log "データベースを作成しています..."
su - postgres -c "createdb ${DATABASE_DB}"

log "PostgreSQLのインストールが完了しました"
log "Database: ${DATABASE_DB}"
log "User: ${DATABASE_USER}"
log "Password: ${DATABASE_PASSWORD}"
log "注意: セキュリティグループで5432ポートを開放してください" 
