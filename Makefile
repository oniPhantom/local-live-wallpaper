.PHONY: install uninstall play off

install:
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

play:
	@if [ -n "$(URL)" ]; then \
		./youtube-wallpaper "$(URL)"; \
	else \
		./youtube-wallpaper; \
	fi

off:
	./youtube-wallpaper off
