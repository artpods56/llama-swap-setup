# llama-swap-setup

## Quick start

1) Choose a platform (default: `cpu`). Create `.env.cpu` with required vars:

```
# .env.cpu (example)
PORT=8081
LLAMA_CONTAINER_NAME=llama_server
LLAMA_SERVER_IMAGE=ghcr.io/ggml-org/llama.cpp:server
MODELS_DIRECTORY=./models
```

2) Generate configs:

```
make config
```

This renders `configs/config.base.yaml` from `models.json` then produces `configs/config.cpu.yaml`.

3) Build and run llama-swap:

```
make build-docker-llama-swap
make run
```

The container is named `llama-swap` and listens on `localhost:9292`. It mounts your Docker socket and `./models`.

## Download model files

- Put model URLs into `models.json` under `ggufs[].url` and projector URL in `ggufs[].mmproj`.
- Download to `./models`:

```
make download-models
```

This fetches `<name>.gguf` and `mmproj_<name>.gguf` into the models directory. For safetensors, `llama.cpp` will use `--hf` at runtime.

## Commands

- `make inject-models`: render `configs/config.base.yaml` from `models.json`.
- `make generate-config`: envsubst -> `configs/config.$(PLATFORM).yaml`.
- `make config`: both of the above.
- `make run`: run llama-swap container.
- `make stop`: stop llama-swap and model server container for `$PORT`.
- `make logs`: follow logs from llama-swap.

## Notes

- Update `models.json` to add GGUF or HF models. `inject-models` will include them in the base config.
- Ensure `LLAMA_SERVER_IMAGE` is a valid `llama.cpp` server image for your platform.