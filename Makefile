.PHONY: install uninstall play off

# `make play <URL>` 形式の位置引数。URL= 指定があればそちらを優先する
PLAY_ARG := $(firstword $(filter-out install uninstall play off,$(MAKECMDGOALS)))

install:
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

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
