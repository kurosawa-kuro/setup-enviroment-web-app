include makefiles/Makefile.al2023
include makefiles/Makefile.wsl
include makefiles/Makefile.webapp

.PHONY: setup setup-swap chmod-scripts setup-key

# デフォルトのセットアップ（Amazon Linux 2023用）
setup: setup-al2023

# 共通のターゲット
chmod-scripts:
	@chmod u+x script/*.sh

setup-swap: chmod-scripts
	@sudo ./script/setup-swap.sh

setup-key: chmod-scripts
	@./script/setup-key.sh