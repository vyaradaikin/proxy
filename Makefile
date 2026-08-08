SHELL := /bin/sh

-include .env

ANSIBLE_CONFIG ?= ansible/ansible.cfg
ANSIBLE_HOME ?= .ansible
VAULT_ARGS ?= --ask-vault-pass
VAULT_ENCRYPT_ARGS ?=
LIMIT ?=

ANSIBLE_ENV := ANSIBLE_CONFIG=$(ANSIBLE_CONFIG) ANSIBLE_HOME=$(ANSIBLE_HOME)
PLAYBOOK := $(ANSIBLE_ENV) ansible-playbook
VAULT := $(ANSIBLE_ENV) ansible-vault
LIMIT_ARGS := $(if $(LIMIT),--limit $(LIMIT),)

.PHONY: help init-local secrets secrets-remote check check-ru check-non-ru check-wg check-tools check-monitoring plan-ru plan-non-ru plan-monitoring apply-ru apply-non-ru apply-wg apply-monitoring verify-ru verify-non-ru speed-ru speed-non-ru clean-generated

help:
	@echo "Targets:"
	@echo "  init-local      Create ignored local config files from examples"
	@echo "  secrets         Generate missing WG/Xray secrets locally and encrypt vault"
	@echo "  secrets-remote  Generate missing WG/Xray secrets on RU/Non-RU and encrypt vault"
	@echo "  check           Syntax-check all playbooks"
	@echo "  plan-ru         Dry-run RU gateway"
	@echo "  plan-non-ru     Dry-run Non-RU exit"
	@echo "  plan-monitoring Dry-run monitoring"
	@echo "  apply-ru        Apply RU gateway"
	@echo "  apply-non-ru    Apply Non-RU exit"
	@echo "  apply-wg        Apply WireGuard only"
	@echo "  apply-monitoring Apply monitoring exporters/server"
	@echo "  verify-ru       Verify RU services and routing"
	@echo "  verify-non-ru   Verify Non-RU WireGuard and firewall"
	@echo "  speed-ru        Run WireGuard iperf3 speed test from RU to Non-RU"
	@echo "  speed-non-ru    Run WireGuard iperf3 speed test from Non-RU to RU"
	@echo ""
	@echo "Set local options in .env, for example:"
	@echo "  VAULT_ARGS=--vault-password-file ~/.ansible/vault_password"
	@echo "  LIMIT=ru-gateway"

init-local:
	@test -f .env || cp .env.example .env
	@test -f ansible/inventory/hosts.yml || cp ansible/inventory/hosts.yml.example ansible/inventory/hosts.yml
	@test -f ansible/group_vars/all/local.yml || cp ansible/group_vars/all/local.yml.example ansible/group_vars/all/local.yml
	@mkdir -p $(ANSIBLE_HOME)
	@echo "Local files are ready. Edit .env, ansible/inventory/hosts.yml, and ansible/group_vars/all/local.yml."

secrets:
	@mkdir -p $(ANSIBLE_HOME)
	$(PLAYBOOK) ansible/playbooks/generate-secrets.yml $(VAULT_ARGS)
	$(VAULT) encrypt --output $(ANSIBLE_HOME)/vault.yml.encrypted $(ANSIBLE_HOME)/generated-vault.yml $(VAULT_ARGS) $(VAULT_ENCRYPT_ARGS)
	mv $(ANSIBLE_HOME)/vault.yml.encrypted ansible/group_vars/all/vault.yml
	rm -f $(ANSIBLE_HOME)/generated-vault.yml
	@echo "Encrypted vault written to ansible/group_vars/all/vault.yml"

secrets-remote:
	@mkdir -p $(ANSIBLE_HOME)
	$(PLAYBOOK) ansible/playbooks/generate-secrets-remote.yml $(LIMIT_ARGS) $(VAULT_ARGS)
	$(VAULT) encrypt --output $(ANSIBLE_HOME)/vault.yml.encrypted $(ANSIBLE_HOME)/generated-vault.yml $(VAULT_ARGS) $(VAULT_ENCRYPT_ARGS)
	mv $(ANSIBLE_HOME)/vault.yml.encrypted ansible/group_vars/all/vault.yml
	rm -f $(ANSIBLE_HOME)/generated-vault.yml
	@echo "Encrypted vault written to ansible/group_vars/all/vault.yml"

check: check-ru check-non-ru check-wg check-tools check-monitoring

check-ru:
	$(PLAYBOOK) --syntax-check ansible/playbooks/ru-gateway.yml

check-non-ru:
	$(PLAYBOOK) --syntax-check ansible/playbooks/non-ru-exit.yml

check-wg:
	$(PLAYBOOK) --syntax-check ansible/playbooks/wireguard.yml

check-tools:
	$(PLAYBOOK) --syntax-check ansible/playbooks/generate-secrets.yml
	$(PLAYBOOK) --syntax-check ansible/playbooks/generate-secrets-remote.yml
	$(PLAYBOOK) --syntax-check ansible/playbooks/verify.yml
	$(PLAYBOOK) --syntax-check ansible/playbooks/speedtest.yml

check-monitoring:
	$(PLAYBOOK) --syntax-check ansible/playbooks/monitoring.yml

plan-ru:
	$(PLAYBOOK) ansible/playbooks/ru-gateway.yml $(LIMIT_ARGS) --check --diff $(VAULT_ARGS)

plan-non-ru:
	$(PLAYBOOK) ansible/playbooks/non-ru-exit.yml $(LIMIT_ARGS) --check --diff $(VAULT_ARGS)

plan-monitoring:
	$(PLAYBOOK) ansible/playbooks/monitoring.yml $(LIMIT_ARGS) --check --diff $(VAULT_ARGS)

apply-ru:
	$(PLAYBOOK) ansible/playbooks/ru-gateway.yml $(LIMIT_ARGS) $(VAULT_ARGS)

apply-non-ru:
	$(PLAYBOOK) ansible/playbooks/non-ru-exit.yml $(LIMIT_ARGS) $(VAULT_ARGS)

apply-wg:
	$(PLAYBOOK) ansible/playbooks/wireguard.yml $(LIMIT_ARGS) $(VAULT_ARGS)

apply-monitoring:
	$(PLAYBOOK) ansible/playbooks/monitoring.yml $(LIMIT_ARGS) $(VAULT_ARGS)

verify-ru:
	$(PLAYBOOK) ansible/playbooks/verify.yml --limit ru $(VAULT_ARGS)

verify-non-ru:
	$(PLAYBOOK) ansible/playbooks/verify.yml --limit non_ru $(VAULT_ARGS)

speed-ru:
	$(PLAYBOOK) ansible/playbooks/speedtest.yml --limit ru $(VAULT_ARGS)

speed-non-ru:
	$(PLAYBOOK) ansible/playbooks/speedtest.yml --limit non_ru $(VAULT_ARGS)

clean-generated:
	rm -f $(ANSIBLE_HOME)/generated-vault.yml
