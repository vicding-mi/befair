DEPLOY_DIR=$(dir $(filter %common.mk,$(MAKEFILE_LIST)))

# Run all unknown target in deploy-active/ directory
ifeq ($(DEPLOY_DIR),./)
#$(guile (chdir "deploy-active"))
$(chdir "deploy-active")
.DEFAULT_GOAL := all
.PHONY: ${MAKECMDGOALS}
$(filter-out all,${MAKECMDGOALS}) all: .forward-all ; @:
.forward-all:
	${MAKE} -C build ${MAKECMDGOALS}
# Never try to remake this makefile.
${MAKEFILE_LIST}: ;
.SUFFIXES:
endif
#else

# add default enviroment file if available
-include .env

# find all *.yaml file in deploy directory and set COMPOSE_FILE for docker-compose
export COMPOSE_FILE=$(call join-with,:,$(wildcard *.yaml))

# FIXME: find a proper way to find dataverse container name
export DATAVERSE_CONTAINER_NAME=$(COMPOSE_PROJECT_NAME)_dataverse_1

## NOTE: trick to run docker-compose with any command (with completed COMPOSE_FILE variable). Can take only one parameter
#%: DOCKER_COMPOSE_COMMAND := $(MAKECMDGOALS)
#%: MAKECMDGOALS := $(firstword MAKECMDGOALS)
#%:
#	docker-compose $(DOCKER_COMPOSE_COMMAND)
#

# help: show all targets with tag 'help'
help:
	@$(call generate-help,$(MAKEFILE_LIST))
.PHONY: help

var-show-all:
	$(foreach var,$(.VARIABLES),$(info $(var) = $($(var))))
	echo $(DEPLOY_DIR)

# Find all *.mk files which corrspond to *.yaml files.
# For example if solr.yaml exist in deploy directory, search for
# services-available/solr.yaml and include it
$(foreach mk,$(addsuffix .mk,$(basename $(wildcard *.yaml))), \
    $(eval SERVICE_INCLUDE_MK += $(call search-parent-mk,services-available/$(mk))) \
)
$(foreach mk,$(SERVICE_INCLUDE_MK), \
    $(eval include $(mk))\
)

OK   := $(shell printf "\"\e[1;32mok\e[0m\"")
FAIL := $(shell printf "\"\e[1;31mfail\e[0m\"")

# help: checking consistency of deploy
check:
	@printf "Checking 'docker-compose config -q' syntax - "
	@useremail=dummy traefikhost=dummy docker-compose config -q && echo $(OK) || { echo $(FAIL); $(CHECK_EXIT) }

	@printf 'Checking existing .env file - '
	@[ -e .env ] && echo $(OK) || { echo $(FAIL); $(CHECK_EXIT) }

	@printf 'Checking existing not only .override.yaml file - '
	@ls *.yaml | grep -qv '\.override.yaml' > /dev/null && echo $(OK) \
		|| { echo $(FAIL)'. Need at least one not override.yaml'; $(CHECK_EXIT) }

	@printf 'Checking not existing *.yml files - '
	@ls *.yml 2> /dev/null >&2 && { echo $(FAIL)'. Please rename or move out *.yml from deployment'; $(CHECK_EXIT) } || echo $(OK)

	@printf 'Checking links point to files with same name - '
	@for YAML in *.yaml; do \
		if [ -L $$YAML ]; then \
            FILE=$$(readlink $$YAML); \
            if [ "$$(basename $$FILE)" != "$$(basename $$YAML)" ]; then \
				[ -z "$$TEST_FAIL" ] && echo $(FAIL); \
				echo "Link $$YAML point to file $$FILE with different name"; \
				TEST_FAIL=1; \
			fi; \
        fi; \
    done; \
	[ -z "$$TEST_FAIL" ] && echo $(OK) || { true; $(CHECK_EXIT) }

.PHONY: check

docker-compose compose:
	docker-compose $(P)

# help: 'docker-compose up' with proper parameters
up: CHECK_EXIT=exit 1;
up: check
	docker-compose up -d
.PHONY: up

debug:
	docker-compose up
.PHONY: debug

airflow:
	docker-compose run webserver db init
	# not secure, just for dev
	chmod -R 777 ./var/airflow
	docker-compose run webserver users create -r Admin -u admin -e team@coronawhy.org -f admin -l user -p admin
.PHONY: airflow

superset:
        # clone latest version ready for deployment
	git clone http://github.com/apache/superset
.PHONY: superset

# init and start everything
init:
	docker-compose run webserver db init
	docker-compose run webserver users create -r Admin -u admin -e team@coronawhy.org -f admin -l user -p admin
	docker-compose up
.PHONY: init

# help: 'docker-compose up' with dummy override entrypoint for dataverse. dataverse need to be run manual
up-manual:: COMPOSE_FILE=$(COMPOSE_FILE):/tmp/entrypoint.override.yaml
up-manual::
	@echo '/bin/sh -c '\''while :; do echo "============= im dataverse ==========="; set; set > /tmp/env; sleep 30; done'\'' > /tmp/entrypoint.override.yaml
	docker-compose up -d


# help: 'docker-compose down'
down:
	docker-compose down
.PHONY: down

# help: 'docker-compose ps'
ps:
	docker-compose ps
.PHONY: ps

# help: run shell inside ${DATAVERSE_CONTAINER_NAME} container
shell devshell:
	docker-compose exec $(DATAVERSE_CONTAINER_NAME) bash
.PHONY: shell devshell

# help: 'docker volume prune' - cleanup data for current deployment
volume-prune:
	docker volume prune --filter 'name=$(COMPOSE_PROJECT_NAME)'
.PHONY: volume-prune

# help: 'docker volume -y prune' - cleanup data for current deployment without prompt
volume-prune-force:
	docker volume -y prune --filter 'name=$(COMPOSE_PROJECT_NAME)'
.PHONY: volume-prune-force

# help: 'docker-compose down' and 'docker volume prune'
reset: down volume-prune
.PHONY: reset

# help: generate enviroment variables for current deployment. Can be user in shell as: eval \$(make env)
env: .env
	@echo export COMPOSE_FILE=$(COMPOSE_FILE)
	@cat .env | sed '/^ *$$\|^#/d;s/^[^#]/export &/'
	@#env --ignore-environment sh -c "set -x;eval $$(/bin/cat .env); echo 123; export -p"
.PHONY: env

# help: bash with enviroment variables for current deployment to allow operate docker-compose directly
bash: .env
	@. ./.env; \
		printf "\nbash with enviroment variables for current deployment. Try to run 'docker-compose config' for example\n\n"; \
		bash -li || true
.PHONY: bash

.env:
	@echo "You need to create .env file"
#endif # ($(DEPLOY_DIR),./)
