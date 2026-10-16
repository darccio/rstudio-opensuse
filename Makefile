SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := build

JOBS ?= 4
WORK_DIR ?= $(CURDIR)/work
OUTPUT_DIR ?= $(CURDIR)/artifacts
RPM ?=
OBS_DIR ?= $(WORK_DIR)/obs
export JOBS WORK_DIR OUTPUT_DIR RPM
export OBS_DIR

.PHONY: build validate test lint check clean help obs-prepare obs-build obs-validate

build:
	./build.sh build

test:
	./build.sh test

lint:
	reuse lint

check: lint test

obs-prepare:
	./build.sh obs-prepare

obs-build:
	./build.sh obs-build

# RPM must name the RPM produced by OBS, whose Release is managed by OBS.
obs-validate: test
	@if [[ -z "$$RPM" || ! -f "$$RPM" ]]; then \
		printf 'Select an OBS RPM with make obs-validate RPM=path/to/package.rpm\n' >&2; exit 1; \
	fi
	./build.sh verify-obs "$$RPM"

validate: test
	@if [[ -z "$$RPM" ]]; then \
		set -- "$$OUTPUT_DIR"/*.rpm; \
		if [[ $$# != 1 || ! -f $$1 ]]; then \
			printf 'Expected one RPM in %s; select one with make validate RPM=path/to/package.rpm\n' "$$OUTPUT_DIR" >&2; \
			exit 1; \
		fi; \
		RPM=$$1; \
	fi; \
	if [[ ! -f "$$RPM" ]]; then \
		printf 'No RPM at %s\n' "$$RPM" >&2; exit 1; \
	fi; \
	./build.sh verify "$$RPM"

clean:
	@project=$$(pwd -P); \
	for directory in "$$WORK_DIR" "$$OUTPUT_DIR" "$$OBS_DIR"; do \
		resolved=$$(realpath -m -- "$$directory"); \
		case "$$project/" in "$${resolved%/}/"*) \
			printf 'Refusing to clean the project directory or an ancestor: %s\n' "$$directory" >&2; \
			exit 1 ;; \
		esac; \
	done; \
	rm -rf -- "$$WORK_DIR" "$$OUTPUT_DIR" "$$OBS_DIR" tests/__pycache__ scripts/__pycache__

help:
	@printf '%s\n' \
		'make build                  Build and verify using build.sh (default).' \
		'make validate [RPM=path]     Run tests and verify an existing RPM in a clean container.' \
		'make test                   Run offline recipe tests.' \
		'make lint                   Check repository licensing with REUSE.' \
		'make check                  Run licensing checks and offline recipe tests.' \
		'make obs-prepare            Prepare offline OBS inputs from a verified RPM.' \
		'make obs-build              Build prepared inputs with osc for Tumbleweed x86_64.' \
		'make obs-validate RPM=path   Run tests and verify an OBS-produced RPM.' \
		'make clean                  Remove WORK_DIR, OUTPUT_DIR, OBS_DIR, and Python caches.' \
		'Overrides: JOBS, CONTAINER_ENGINE, BASE_IMAGE, WORK_DIR, OUTPUT_DIR, RPM, OBS_DIR.'
