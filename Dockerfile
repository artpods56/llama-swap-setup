ARG LLAMA_SWAP_IMAGE

FROM $LLAMA_SWAP_IMAGE

RUN apt-get update && \
    apt-get install -y ca-certificates curl && \
    mkdir -m 0755 -p /etc/apt/keyrings

RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc

RUN chmod a+r /etc/apt/keyrings/docker.asc

RUN echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

RUN apt-get update && \
    apt-get install -y docker-ce-cli rsync

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]