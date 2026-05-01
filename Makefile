SWIFT ?= swift
CONFIG_EXAMPLE ?= config/swarm-cadence.config.example.json
APP_SUPPORT_DIR ?= $(HOME)/Library/Application Support/swarm-cadence
PREFIX ?= $(HOME)
BINDIR ?= $(PREFIX)/bin
PRODUCT ?= swarm-cadence
SKILL_NAME := swarm-cadence
SKILL_DIR := skills/$(SKILL_NAME)
OPENCLAW_HOME ?= $(HOME)/.openclaw
OPENCLAW_SKILLS_DIR ?= $(OPENCLAW_HOME)/skills
SKILL_DEST := $(OPENCLAW_SKILLS_DIR)/$(SKILL_NAME)
VERSION_FILE := VERSION
VERSION_SYNC_FILE := Sources/SwarmCadenceCore/SwarmCadenceVersion.swift
VERSION := $(shell tr -d '\n' < $(VERSION_FILE))

.PHONY: build release test clean show-defaults install install-skill install-config-example sync-version

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
	@printf 'config:      %s\n' '$(APP_SUPPORT_DIR)/config.json'
	@printf 'raw dir:     %s\n' '$(APP_SUPPORT_DIR)/accounts/<account>/raw/v2/checkins'
	@printf 'sqlite db:   %s\n' '$(APP_SUPPORT_DIR)/accounts/<account>/swarm-cadence.sqlite'

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


install-skill:
	@test -f "$(SKILL_DIR)/SKILL.md" || (echo "Missing $(SKILL_DIR)/SKILL.md" && exit 1)
	@test -f "$(VERSION_FILE)" || (echo "Missing $(VERSION_FILE)" && exit 1)
	@if [ -z "$(ACCOUNTS)" ]; then \
		echo 'Usage: make install-skill ACCOUNTS="single-account"'; \
		echo '   or: make install-skill ACCOUNTS="account1 account2"'; \
		exit 1; \
	fi
	python3 scripts/install_skill.py --validate-accounts "$(ACCOUNTS)"
	mkdir -p "$(OPENCLAW_SKILLS_DIR)"
	rm -rf "$(SKILL_DEST)"
	cp -R "$(SKILL_DIR)" "$(SKILL_DEST)"
	python3 scripts/install_skill.py \
		--source-root "$(CURDIR)" \
		--dest "$(SKILL_DEST)" \
		--version-file "$(VERSION_FILE)" \
		--skill-name "$(SKILL_NAME)" \
		--accounts "$(ACCOUNTS)"
	@echo "Installed skill $(SKILL_NAME) to $(SKILL_DEST)"
