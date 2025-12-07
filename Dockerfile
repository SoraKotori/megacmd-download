# Dockerfile
FROM debian:13-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8

WORKDIR /root

# 安裝必要工具與 MEGAcmd（Debian 13 官方包）
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        bash && \
    wget https://mega.nz/linux/repo/Debian_13/amd64/megacmd-Debian_13_amd64.deb && \
    apt-get install -y ./megacmd-Debian_13_amd64.deb && \
    rm megacmd-Debian_13_amd64.deb && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 複製 entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
