SCRIPTS := bin/vramon $(wildcard lib/*.sh) $(wildcard tests/*.sh) install.sh uninstall.sh
TESTS := $(wildcard tests/test_*.sh)

.PHONY: all install uninstall test lint fmt run watch tmux json

all: test

install:
	bash ./install.sh

uninstall:
	bash ./uninstall.sh

test:
	@status=0; \
	for t in $(TESTS); do \
		bash "$$t" || status=1; \
	done; \
	exit $$status

lint:
	shellcheck $(SCRIPTS)

fmt:
	shfmt -i 4 -ci -w bin/vramon lib tests install.sh uninstall.sh

run:
	bash ./bin/vramon --once

watch:
	bash ./bin/vramon --watch

tmux:
	bash ./bin/vramon --tmux

json:
	bash ./bin/vramon --json
