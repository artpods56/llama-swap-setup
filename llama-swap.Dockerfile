ARG LLAMA_SERVER_IMAGE

FROM ${LLAMA_SERVER_IMAGE}

ARG LLAMA_SWAP_VERSION

WORKDIR /app

RUN echo "Building with LLAMA_SWAP_VERSION=${LLAMA_SWAP_VERSION}" && \
    curl -fLO https://github.com/mostlygeek/llama-swap/releases/download/${LLAMA_SWAP_VERSION}/llama-swap_${LLAMA_SWAP_VERSION#v}_linux_arm64.tar.gz && \
    tar -zxf llama-swap_${LLAMA_SWAP_VERSION#v}_linux_arm64.tar.gz && \
    rm llama-swap_${LLAMA_SWAP_VERSION#v}_linux_arm64.tar.gz && \
    chmod +x /app/llama-swap

COPY vendors/llama-swap/docker/config.example.yaml /app/config.yaml

HEALTHCHECK CMD curl -f http://localhost:8080/ || exit 1
ENTRYPOINT [ "/app/llama-swap", "-config", "/app/config.yaml" ]
