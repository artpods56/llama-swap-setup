# Makefile for Llama-Swap Server Setup

# Options: [cpu, cuda, intel, vulkan]
PLATFORM ?= cpu

include .env.$(PLATFORM)
export

# --- Makefile variables
MODELS_DIRECTORY ?= ./models
CONFIGS_DIRECTORY ?= ./configs
VENDOR_DIRECTORY ?= ./vendors
CONFIG_FILE ?= config.$(PLATFORM).yaml
LLAMA_CONTAINER_NAME ?= llama_server
ARCHITECTURE ?= arm64

DOCKER_PATH := $(shell ./get-docker-socket.sh)

LLAMA_SWAP_VERSION ?= v157
BASE_LLAMA_SWAP_IMAGE ?= ghcr.io/mostlygeek/llama-swap:$(PLATFORM)
LOCAL_LLAMA_SWAP_IMAGE ?= llama-swap:${PLATFORM}-${ARCHITECTURE}


.PHONY: help
help:
	@echo "Llama-Swap Server Setup"
	@echo "======================"
	@echo "Available commands:"
	@echo "  make setup   - Download prerequisites and prepare directories"
	@echo "  make run     - Start the llama-swap server with Docker Compose"
	@echo "  make stop    - Stop the llama-swap server"
	@echo "  make logs    - Stream logs from the running server"
	@echo "  make clean   - Stop the server and running Docker containers"
	@echo "  make create-volume     - Create the llamaswap_models named volume"
	@echo ""
	@echo "  make remove-volume     - Remove the llamaswap_models named volume"
	@echo "  make compose-up     - Start llama-swap with Docker Compose"
	@echo "  make compose-down   - Stop llama-swap with Docker Compose"
	@echo "  make compose-logs   - Stream logs from llama-swap container"
	@echo "  make compose-shell  - Open shell in llama-swap container"
	@echo "  make compose-clean  - Clean up Docker Compose resources"
	@echo "  make help    - Show this help message"

# Setup target - create directories and download necessary files
.PHONY: setup
setup:
	@echo "Setting up llama-swap server..."
	@mkdir -p bin models configs
	@echo "Directories created."
	@echo "Note: You still need to provide your own llama-server executable in the bin/ directory."
	@echo "For best performance (e.g., with GPU support), compile it yourself from the llama.cpp repository."

# Run target - start the server
.PHONY: run
run:
	@$(MAKE) compose-up

# Stop target - find and stop the running process
.PHONY: stop
stop:
	@echo "Stopping llama-swap containers..."
	@docker-compose --env-file compose.env down

# Logs target - stream logs from the running server
.PHONY: logs
logs:
	@echo "Streaming logs from llama-swap container..."
	@docker-compose --env-file compose.env logs -f llama-swap | cat

# Clean target - stop server and running Docker containers
.PHONY: clean
clean:
	@echo "Cleaning up..."
	@make stop
	@echo "Cleanup complete."

# Docker Compose targets

.PHONY: compose-up
compose-up: config
	@echo "Starting llama-swap with Docker Compose..."
	@docker-compose --env-file compose.env up -d --build

.PHONY: compose-down
compose-down:
	@echo "Stopping llama-swap with Docker Compose..."
	@docker-compose --env-file compose.env down

.PHONY: compose-logs
compose-logs:
	@echo "Streaming logs from llama-swap container..."
	@docker-compose --env-file compose.env logs -f llama-swap

.PHONY: compose-shell
compose-shell:
	@echo "Opening shell in llama-swap container..."
	@docker-compose --env-file compose.env exec llama-swap /bin/sh

.PHONY: compose-clean
compose-clean:
	@echo "Cleaning up Docker Compose resources..."
	@docker-compose --env-file compose.env down -v --remove-orphans

# Default target
.PHONY: all
all: help

generate-config:
	@echo "Generating llama-swap config..."
	@envsubst < $(CONFIGS_DIRECTORY)/config.base.yaml \
	         > $(CONFIGS_DIRECTORY)/$(CONFIG_FILE)
	@echo "Config generated at $(CONFIGS_DIRECTORY)/$(CONFIG_FILE)"

.PHONY: inject-models
inject-models:
	@echo "Injecting model entries into configs/config.base.yaml from models.json..."
	@uv run python -m cli inject-models --models-file models.json --template $(CONFIGS_DIRECTORY)/templates/config.base.yaml --output $(CONFIGS_DIRECTORY)/config.base.yaml --overwrite
	@echo "Model entries injected."

.PHONY: download-models
download-models:
	@echo "Downloading gguf and mmproj files to $(MODELS_DIRECTORY)..."
	@uv run python -m cli download-models --models-file models.json --models-dir $(MODELS_DIRECTORY)
	@echo "Downloads completed."

.PHONY: config
config: inject-models generate-config

clone-llama:
	@mkdir -p $(dir $(VENDOR_DIRECTORY))
	@if [ ! -d $(VENDOR_DIRECTORY)/llama.cpp ]; then \
		echo "Cloning llama.cpp repo into $(VENDOR_DIRECTORY)..."; \
		git clone https://github.com/ggerganov/llama.cpp $(VENDOR_DIRECTORY)/llama.cpp; \
	else \
		echo "llama.cpp repo already exists in $(VENDOR_DIRECTORY)/llama.cpp; skipping clone."; \
		cd $(VENDOR_DIRECTORY)/llama.cpp && git pull; \
	fi
clone-llama-swap:
	@mkdir -p $(dir $(VENDOR_DIRECTORY))
	@if [ ! -d $(VENDOR_DIRECTORY)/llama-swap ]; then \
		echo "Cloning llama-swap repo into $(VENDOR_DIRECTORY)..."; \
		git clone https://github.com/mostlygeek/llama-swap $(VENDOR_DIRECTORY)/llama-swap; \
	else \
		echo "llama-swap repo already exists in $(VENDOR_DIRECTORY)/llama-swap; skipping clone."; \
		cd $(VENDOR_DIRECTORY)/llama-swap && git pull; \
	fi

build-llama-server-arm64: clone-llama
	@cd $(VENDOR_DIRECTORY)/llama.cpp && \
	docker build -f .devops/cpu.Dockerfile \
		--build-arg TARGETARCH=arm64 \
		--tag $(LLAMA_SERVER_IMAGE) \
		--platform linux/arm64 .


.PHONY: build-llama-server-arm64
build-llama-swap-arm64: build-llama-server-arm64
	docker build -f llama-swap.Dockerfile \
		--build-arg LLAMA_SERVER_IMAGE=$(LLAMA_SERVER_IMAGE) \
		--build-arg LLAMA_SWAP_VERSION=$(LLAMA_SWAP_VERSION) \
		--tag ${LOCAL_LLAMA_SWAP_IMAGE} \
		--platform linux/arm64 .

build-docker-llama-swap-local:build-llama-swap-arm64
	docker build -f ./Dockerfile \
		--build-arg LLAMA_SWAP_IMAGE=${LOCAL_LLAMA_SWAP_IMAGE} \
		--tag docker-llama-swap-${PLATFORM}-${ARCHITECTURE} \
		--platform linux/${ARCHITECTURE} .

build-docker-llama-swap-base:
	docker build -f ./Dockerfile \
		--build-arg LLAMA_SWAP_IMAGE=${BASE_LLAMA_SWAP_IMAGE} \
		--tag docker-llama-swap-${PLATFORM}-${ARCHITECTURE} \
		--platform linux/${ARCHITECTURE} .

run-docker-llama-swap: build-docker-llama-swap-local
	docker run -it --rm --name llama-swap -p 9292:8080 \
		--network host \
		-v /var/run/docker.sock:/var/run/docker.sock \
 		-v llamaswap_models:/models \
 		-v ${CONFIGS_DIRECTORY}/config.$(PLATFORM).yaml:/app/config.yaml \
 		docker-llama-swap-${PLATFORM}-${ARCHITECTURE}

run-docker-llama-swap-shell: build-docker-llama-swap-local
	docker run -it --rm --name llama-swap-shell -p 9292:8080 \
		-v /var/run/docker.sock:/var/run/docker.sock \
 		-v llamaswap_models:/models \
 		-v ${CONFIGS_DIRECTORY}/config.$(PLATFORM).yaml:/app/config.yaml \
 		docker-llama-swap-${PLATFORM}-${ARCHITECTURE}

run_from_compose: config
	LLAMA_SWAP_IMAGE=docker-llama-swap-${PLATFORM}-${ARCHITECTURE} \
	CONFIGS_DIRECTORY=${CONFIGS_DIRECTORY} \
	PLATFORM=${PLATFORM} \
	 docker compose -f docker-compose.yml up --build


run_llama:
	docker run --name gemma-3-27b-it-Q4_K_M  \
  	--init --rm -p 8888:8080 -v models:/models llama-server:cpu-arm64 \
  	--model "/models/gguf/gemma-3-27b-it-Q4_K_M/gemma-3-27b-it-Q4_K_M.gguf" \
  	--mmproj "/models/gguf/gemma-3-27b-it-Q4_K_M/mmproj_gemma-3-27b-it-Q4_K_M.gguf" \