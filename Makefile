SWIFT ?= swift
CONFIG_EXAMPLE ?= config/swarm-cadence.config.example.json
APP_SUPPORT_DIR ?= $(HOME)/Library/Application Support/swarm-cadence
PREFIX ?= $(HOME)
BINDIR ?= $(PREFIX)/bin
PRODUCT ?= swarm-cadence
VERSION_FILE := VERSION
VERSION_SYNC_FILE := Sources/SwarmCadenceCore/SwarmCadenceVersion.swift
VERSION := $(shell tr -d '\n' < $(VERSION_FILE))

.PHONY: build release test clean show-defaults install install-config-example sync-version

sync-version:
	@test -f "$(VERSION_FILE)" || (echo "Missing $(VERSION_FILE)" && exit 1)
	python3 -c 'from pathlib import Path; import re; version = Path("$(VERSION_FILE)").read_text().strip() or "0.0.0"; path = Path("$(VERSION_SYNC_FILE)"); text = path.read_text(); text, count = re.subn(r"// VERSION-SYNC-START\n.*?\n    // VERSION-SYNC-END", "// VERSION-SYNC-START\n    public static let current = \"%s\"\n    // VERSION-SYNC-END" % version, text, count=1, flags=re.S); assert count == 1, "version marker not found"; path.write_text(text)'

build: sync-version
	$(SWIFT) build

release: sync-version
	$(SWIFT) build -c release

test: sync-version
	$(SWIFT) test

clean:
	$(SWIFT) package clean

show-defaults:
	@printf 'config:        %s\n' '$(APP_SUPPORT_DIR)/config.json'
	@printf 'julian raw:    %s\n' '$(APP_SUPPORT_DIR)/accounts/julian/raw/v2/checkins'
	@printf 'julian sqlite: %s\n' '$(APP_SUPPORT_DIR)/accounts/julian/swarm-cadence.sqlite'
	@printf 'alice raw:     %s\n' '$(APP_SUPPORT_DIR)/accounts/alice/raw/v2/checkins'
	@printf 'alice sqlite:  %s\n' '$(APP_SUPPORT_DIR)/accounts/alice/swarm-cadence.sqlite'

install: release
	install -d '$(BINDIR)'
	install -m 0755 '.build/release/$(PRODUCT)' '$(BINDIR)/$(PRODUCT)'
	@printf 'installed %s\n' '$(BINDIR)/$(PRODUCT)'

install-config-example:
	install -d '$(APP_SUPPORT_DIR)'
	@if [ -e '$(APP_SUPPORT_DIR)/config.json' ]; then \
		echo 'refusing to overwrite $(APP_SUPPORT_DIR)/config.json'; \
		exit 1; \
	fi
	install -m 0600 '$(CONFIG_EXAMPLE)' '$(APP_SUPPORT_DIR)/config.json'
