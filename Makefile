# Enoki (朔と栞) — Swift Package Manager のみでビルドする
.PHONY: build app run test install clean

APP := build/Enoki.app
INSTALL_DIR := $(HOME)/Applications

## デバッグビルド
build:
	swift build

## .app を組み立てる（UNIVERSAL=1 でユニバーサルバイナリ、CODESIGN_IDENTITY で署名 ID 指定）
app:
	./scripts/build_app.sh

## .app を作って起動する
run: app
	open $(APP)

## テスト
test:
	swift test

## ~/Applications へインストール（既存は置き換え）
install: app
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/Enoki.app"
	cp -R "$(APP)" "$(INSTALL_DIR)/Enoki.app"
	@echo "インストールしました: $(INSTALL_DIR)/Enoki.app"

## 生成物を削除
clean:
	swift package clean
	rm -rf .build build
