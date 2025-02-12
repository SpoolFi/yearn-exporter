SHELL := /bin/bash

NETWORK ?= ethereum
export
BROWNIE_NETWORK ?= mainnet
export

.ONESHELL:
get-network-name:
ifneq ($(shell echo $(network) | egrep "^ethereum$$|^eth$$|^ETH$$|^mainnet$$"),)
	$(eval NETWORK = ethereum)
	$(eval BROWNIE_NETWORK = mainnet)
else ifneq ($(shell echo $(network) | egrep "^ftm$$|^FTM$$|^fantom$$"),)
	$(eval NETWORK = fantom)
	$(eval BROWNIE_NETWORK = ftm-main)
else ifneq ($(shell echo $(network) | egrep "^arrb$$|^ARRB$$|arbi$$|^arbitrum$$"),)
	$(eval NETWORK = arbitrum)
	$(eval BROWNIE_NETWORK = arbitrum-main)
else ifneq ($(shell echo $(network) | egrep "^op$$|^OPTI$$|^opti$$|^optimism$$"),)
	$(eval NETWORK = optimism)
	$(eval BROWNIE_NETWORK = optimism-main)
else ifneq ($(shell echo $(network) | egrep "^gno$$|^GNO$$|^gnosis$$"),)
	$(eval NETWORK = gnosis)
	$(eval BROWNIE_NETWORK = xdai-main)
else ifeq ($(network),)
		@echo "No valid network specified. You can specify a network by passing network=<NETWORK>. Supported networks: '$(supported_networks)'"
		$(eval undefine NETWORK)
		$(eval undefine BROWNIE_NETWORK)
endif
	if [[ $${NETWORK} != "" ]]; then
		@echo "Running on network '$(NETWORK)'"
	fi

flags := --remove-orphans --detach
ifdef FLAGS
	flags += $(FLAGS)
endif

#######################################
# specify all supported networks here #
#######################################
supported_networks := ethereum fantom arbitrum optimism gnosis

###############################################
# specify all supported exporter scripts here #
###############################################
exporter_scripts := exporters/vaults exporters/treasury exporters/treasury_transactions exporters/sms exporters/transactions exporters/wallets exporters/partners

# docker-compose commands
dashboards_command := docker-compose --file services/dashboard/docker-compose.yml --project-directory .
tvl_command 		   := docker-compose --file services/tvl/docker-compose.yml --project-directory .
test_command 		   := docker-compose --file services/dashboard/docker-compose.test.yml --project-directory .

# TODO integrate tvl exporters into BASE recipes below
# tvl recipes
tvl-up:
	$(tvl_command) up $(flags)
tvl: tvl-up

tvl-down:
	$(tvl_command) down

tvl-build:
	$(tvl_command) build $(BUILD_FLAGS)


##########################################
# BASE recipes for running all exporters #
##########################################

# postgres, grafana, victoria
infra:
	docker-compose --file services/dashboard/docker-compose.infra.yml --project-directory . -p infra up --detach

# exporter specifc scripts
single-network: infra
	NETWORK=$(network) COMMANDS="$(commands)" DEBUG=$(DEBUG) ./run.sh

.ONESHELL:
all-networks: infra
	for network in $(supported_networks); do
		network=$$network commands="$(commands)" DEBUG=$(DEBUG) make single-network
	done

down: get-network-name
	$(eval filter = $(if $(filter),$(filter),$(if $(NETWORK),$(NETWORK),exporter)))
	echo "stopping containers for filter: $(filter)"
	docker ps -a -q --filter="name=$(filter)" | xargs -L 1 docker rm -f 2> /dev/null || true
	echo "running containers:"
	docker ps

.PHONY: build
build:
	$(dashboards_command) build $(BUILD_FLAGS)

logs: get-network-name
	$(eval filter = $(if $(filter),$(filter),$(if $(NETWORK),$(NETWORK),exporter)))
	$(eval since = $(if $(since),$(since),30s))
	docker ps -a -q --filter="name=$(filter)"| xargs -L 1 -P $$(docker ps --filter="name=$(filter)" | wc -l) docker logs --since $(since) -ft


.ONESHELL:
.SILENT:
up: get-network-name
	$(eval commands = $(if $(commands),$(commands),$(exporter_scripts)))
	if [ "$(NETWORK)" != "" ]; then
		make single-network network=$(NETWORK) commands="$(commands)" logs
	else
		make all-networks commands="$(commands)" logs
	fi

console: get-network-name
	$(eval BROWNIE_NETWORK = $(if $(BROWNIE_NETWORK),$(BROWNIE_NETWORK),mainnet))
	docker-compose --file services/dashboard/docker-compose.yml --project-directory . run --rm --entrypoint "brownie console --network $(BROWNIE_NETWORK)" exporter

shell: get-network-name
	docker-compose --file services/dashboard/docker-compose.yml --project-directory . run --rm --entrypoint bash exporter

.ONESHELL:
debug-apy: get-network-name
	DEBUG=true docker-compose --file services/dashboard/docker-compose.yml --project-directory . run --rm --entrypoint "brownie run --network $(BROWNIE_NETWORK) debug_apy -I" exporter
	make logs filter=debug

list-networks:
	@echo "supported networks: $(networks)"

list-commands:
	@echo "supported exporter commands: $(exporter_scripts)"

# some convenience aliases
exporters:
	make up commands="$(exporter_scripts)"

exporters-up: exporters
exporters-down: down
logs-exporters: logs
exporters-logs: logs-exporters
dashboards: up
dashboards-up: up
dashboards-down: down
dashboards-build: build
logs-all: logs

# Maintenance
rebuild: down build up
all: rebuild
scratch: clean-volumes build up
clean-volumes: down
	$(eval filter = $(if $(filter),$(filter),$(if $(NETWORK),$(NETWORK),exporter)))
	docker volume ls -q --filter="name=$(filter)" | xargs -L 1 docker volume rm 2> /dev/null || true
clean-exporter-volumes: clean-volumes
dashboards-clean-volumes: clean-exporter-volumes

tvl-clean-volumes:
	$(tvl_ command) down -v

clean-cache:
	make clean-volumes filter=cache
dashboards-clean-cache: clean-cache


############################
# Network-specific recipes #
############################

# Ethereum
ethereum:
	make up logs network=ethereum

# Ethereum aliases
eth: ethereum
mainnet: ethereum

# Fantom
fantom:
	make up logs network=fantom

# Arbitrum Chain
arbitrum:
	make up logs network=arbitrum

# Optimism Chain
optimism:
	make up logs network=optimism

# Gnosis Chain
gnosis:
	make up logs network=gnosis

############################
# Exporter-specifc recipes #
############################

# Treasury Exporters
treasury:
	make up filter=treasury commands="exporters/treasury"

logs-treasury:
	make logs filter=treasury

# Treasury TX Exporters
treasury-tx:
	make up filter=treasury_transactions commands="exporters/treasury_transactions"

logs-treasury-tx:
	make logs filter=treasury_transactions

# apy scripts
apy: commands=s3
apy: up

# revenue scripts
revenues:
	make up network=eth commands=revenues

# partners scripts
partners-eth:
	make up network=eth commands="exporters/partners"

partners-ftm:
	make up network=ftm commands="exporters/partners"

partners-summary-eth:
	make up network=eth commands="partners_summary"

partners-summary-ftm:
	make up network=ftm commands="partners_summary"
