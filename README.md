# setup-web-app

コード規約

```
セットアップ
make setup

開発サーバー起動
make dev

テスト実行
make test

開発データベースリセット
make db-reset
```

```
touch setup-amazon-linux-2023-user-data.sh
chmod u+x setup-amazon-linux-2023-user-data.sh
vi setup-amazon-linux-2023-user-data.sh
```

```
sudo ./setup-amazon-linux-2023-user-data.sh
```

```
git --version
make --version
docker --version
docker-compose --version
node -v
psql --version
```

```
[2024-12-19 23:52:48] ============================================
[2024-12-19 23:52:48] インストール完了サマリー
[2024-12-19 23:52:48] ============================================
[2024-12-19 23:52:48] Go言語情報:
- Version: 
- GOROOT: /usr/local/go
- GOPATH: /home/ec2-user/go
- 注意: 新しいシェルを開くか、source /etc/profile.d/go.shを実行してください
[2024-12-19 23:52:48] --------------------------------------------
[2024-12-19 23:52:48] 開発ツール: インストール済み
[2024-12-19 23:52:48] --------------------------------------------
[2024-12-19 23:52:48] PostgreSQL情報:
- Database: dev_db
- User: postgres
- Password: postgres
- Port: 5432
- 注意: セキュリティグループで5432ポートを開放してください
[2024-12-19 23:52:48] --------------------------------------------
[2024-12-19 23:52:48] NodeJS: インストール済み (v20.18.1)
[2024-12-19 23:52:48] --------------------------------------------
[2024-12-19 23:52:48] Docker情報:
- Docker Version: Docker version 25.0.5, build 5dc9bcc
- Docker Compose Version: Docker Compose version v2.21.0
- Docker Service: active
- Docker Socket: /var/run/docker.sock
- Docker Group: docker (ec2-user added)
- 注意: 新しいシェルを開くとdockerコマンドがsudoなしで実行可能になります
[2024-12-19 23:52:48] --------------------------------------------
[2024-12-19 23:52:48] 注意事項:
[2024-12-19 23:52:48] 1. 各コンポーネントの詳細な設定は上記のログを確認してください
[2024-12-19 23:52:48] 2. 必要に応じてセキュリティグループの設定を行ってください
[2024-12-19 23:52:48] 3. 環境変数を反映するには、新しいシェルを開くか、sourceコマンドを実行してください
[2024-12-19 23:52:48] Setup completed successfully
```

```
Host AAA
    HostName AAA
    User ec2-user
    IdentityFile ~/.ssh/AAA.pem
    StrictHostKeyChecking no
    PubkeyAuthentication yes
    PasswordAuthentication no
```
