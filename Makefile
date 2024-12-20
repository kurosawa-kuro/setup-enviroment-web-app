.PHONY: setup setup-al2023 setup-swap chmod-scripts setup-key uninstall check-versions

# デフォルトのセットアップ（Amazon Linux 2023用）
setup: setup-al2023

# Amazon Linux 2023用セットアップ
setup-al2023: chmod-scripts setup-swap setup-key
	@sudo ./script/setup-amazon-linux-2023.sh

# 共通のターゲット
chmod-scripts:
	@chmod u+x script/*.sh

setup-key: chmod-scripts
	@./script/setup-key.sh

# アンインストール
uninstall: chmod-scripts
	@sudo ./script/uninstall-amazon-linux-2023.sh

# ヘージョン確認
check-versions: chmod-scripts
	@./script/check-versions.sh

# ヘルプ
help:
	@echo "利用可能なターゲット:"
	@echo "  setup         - デフォルトのセットアップを実行 (Amazon Linux 2023用)"
	@echo "  setup-key     - SSH鍵の生成"
	@echo "  uninstall     - インストールしたコンポーネントを削除"
	@echo "  check-versions - インストール済みコンポーネントのバージョンを確認"
