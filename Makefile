.PHONY: install uninstall play off test lint

# `make play <URL>` 形式の位置引数。URL= 指定があればそちらを優先する
PLAY_ARG := $(firstword $(filter-out install uninstall play off test lint,$(MAKECMDGOALS)))

# xcode-select が Command Line Tools を指していると SPM が Package.swift を
# ビルドできない環境があるため、Xcode があればそちらのツールチェーンを使う
ifeq ($(origin DEVELOPER_DIR), undefined)
ifneq ($(findstring CommandLineTools,$(shell xcode-select -p 2>/dev/null)),)
ifneq ($(wildcard /Applications/Xcode.app/Contents/Developer),)
export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
endif
endif
endif

install:
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

test:
	swift test

lint:
	swiftlint --strict

play:
	@if [ -n "$(URL)" ]; then \
		./youtube-wallpaper "$(URL)"; \
	elif [ -n "$(PLAY_ARG)" ]; then \
		./youtube-wallpaper "$(PLAY_ARG)"; \
	else \
		./youtube-wallpaper; \
	fi

off:
	./youtube-wallpaper off

# play 実行時のみ: 位置引数の URL がターゲットとして解釈されてもエラーにしない
# (他のターゲットではタイプミスを従来どおりエラーにする)
ifneq (,$(filter play,$(MAKECMDGOALS)))
.DEFAULT:
	@:
endif
