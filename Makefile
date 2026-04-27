SWIFT ?= swift
CONFIG_EXAMPLE ?= config/swarm-cadence.config.example.json
APP_SUPPORT_DIR ?= $(HOME)/Library/Application Support/swarm-cadence
PREFIX ?= $(HOME)
BINDIR ?= $(PREFIX)/bin
PRODUCT ?= swarm-cadence

.PHONY: build release test clean show-defaults install install-config-example

build:
	$(SWIFT) build

release:
	$(SWIFT) build -c release

test:
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
