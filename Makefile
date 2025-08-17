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

# --- Environment variables export ---

.PHONY: help
help:
	@echo "Llama-Swap Server Setup"
	@echo "======================"
	@echo "Available commands:"
	@echo "  make setup   - Download prerequisites and prepare directories"
	@echo "  make run     - Start the llama-swap server in the foreground"
	@echo "  make stop    - Find and stop the running llama-swap process"
	@echo "  make logs    - Stream logs from the running server"
	@echo "  make clean   - Stop the server and running Docker containers"
	@echo "  make help    - Show this help message"

# Setup target - create directories and download necessary files
.PHONY: setup
setup:
	@echo "Setting up llama-swap server..."
	@mkdir -p bin models config
	@echo "Directories created."
	@echo "Note: You still need to provide your own llama-server executable in the bin/ directory."
	@echo "For best performance (e.g., with GPU support), compile it yourself from the llama.cpp repository."

# Run target - start the server
.PHONY: run
run:
	@echo "Starting llama-swap server..."
	@echo "Make sure you have compiled llama-server and placed it in the bin/ directory."
	@echo "Server will be running on http://localhost:8080"
	@echo "To stop the server, use: make stop"
	# This will be updated when we have the actual server executable
	@echo "For now, please run your llama-server binary manually"

# Stop target - find and stop the running process
.PHONY: stop
stop:
	@echo "Stopping llama-swap server..."
	@pkill -f llama-swap 2>/dev/null || echo "No llama-swap process found"

# Logs target - stream logs from the running server
.PHONY: logs
logs:
	@echo "Streaming logs from llama-swap server..."
	@echo "Logs would be shown here if the server were running"

# Clean target - stop server and running Docker containers
.PHONY: clean
clean:
	@echo "Cleaning up..."
	@make stop
	@echo "Cleanup complete."

# Default target
.PHONY: all
all: help

generate-config:
	@echo "Generating llama-swap config..."
	@envsubst < $(CONFIGS_DIRECTORY)/config.base.yaml \
	         > $(CONFIGS_DIRECTORY)/$(CONFIG_FILE)
	@echo "Config generated at $(CONFIGS_DIRECTORY)/$(CONFIG_FILE)"

clone-llama:
	@mkdir -p $(dir $(VENDOR_DIRECTORY))
	@if [ ! -d $(VENDOR_DIRECTORY)/llama.cpp ]; then \
		echo "Cloning llama.cpp repo into $(VENDOR_DIRECTORY)..."; \
		git clone https://github.com/ggerganov/llama.cpp $(VENDOR_DIRECTORY)/llama.cpp; \
	else \
		echo "llama.cpp repo already exists in $(VENDOR_DIRECTORY)/llama.cpp; skipping clone."; \
		cd $(VENDOR_DIRECTORY)/llama.cpp && git pull; \
	fi

# Build the ARM64 image for Apple Silicon (depends on clone)
build-llama-arm64: clone-llama
	@cd $(VENDOR_DIRECTORY)/llama.cpp && \
	docker build -f .devops/cpu.Dockerfile \
		--build-arg TARGETARCH=arm64 \
		--tag $(LLAMA_SERVER_IMAGE) \
		--platform linux/arm64 .  # Explicit platform for safety

docker-llama-swap: build-llama-arm64
	docker run -it --rm --runtime nvidia -p 9292:8080 \
  		-v ${MODELS_DIRECTORY}:/models \
  		-v ${CONFIGS_DIRECTORY}/llama-swap-config.yaml:/app/config.yaml \
  		ghcr.io/mostlygeek/llama-swap:${LLAMA-SWAP-PLATFORM}

run-llama-server:
ifeq ($(LLAMA-SWAP-PLATFORM),cpu)
	docker run --rm -d --name llama-server-$(PORT) \
		-p $(PORT):8080 \
		-v $(MODELS_DIRECTORY):/models \
		$(LLAMA_ARM64_IMAGE_NAME) \
		--model /models/$(MODEL)
else ifeq ($(LLAMA-SWAP-PLATFORM),cuda)
	docker run --rm -d --gpus all --name llama-server-$(PORT) \
		-p $(PORT):8080 \
		-v $(MODELS_DIRECTORY):/models \
		ghcr.io/ggml-org/llama.cpp:server \
		--model /models/$(MODEL)
endif

stop-llama-server:
	docker rm -f llama-server-$(PORT) || true