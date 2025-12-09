# Dockerfile
FROM debian:13-slim AS base

ENV DEBIAN_FRONTEND=noninteractive \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
    && wget https://mega.nz/linux/repo/Debian_13/amd64/megacmd-Debian_13_amd64.deb \
    && apt-get install -y ./megacmd-Debian_13_amd64.deb \
    && rm megacmd-Debian_13_amd64.deb \
    && rm -rf /var/lib/apt/lists/*

FROM base AS development

# 多裝開發會用到的工具：git 等
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git

FROM base AS runtime

# 複製 entrypoint
COPY entrypoint.sh entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]
