# syntax=docker/dockerfile:1
FROM fortress AS fortress-source

FROM debian:bookworm-slim AS build

RUN apt-get update && \
  apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git && \
  rm -rf /var/lib/apt/lists/*

RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
    curl -fsSL -o /usr/local/bin/nimby \
      https://github.com/treeform/nimby/releases/download/0.1.26/nimby-Linux-X64; \
  elif [ "$(dpkg --print-architecture)" = "arm64" ]; then \
    curl -fsSL -o /usr/local/bin/nimby \
      https://github.com/treeform/nimby/releases/download/0.1.26/nimby-Linux-ARM64; \
  else \
    echo "unsupported arch: $(dpkg --print-architecture)" && exit 1; \
  fi && \
  chmod +x /usr/local/bin/nimby && \
  nimby use 2.2.10

ENV PATH="/root/.nimby/nim/bin:$PATH"

WORKDIR /workspace
COPY --from=fortress-source / ./coworld-tribal-fortress

WORKDIR /workspace/coworld-tribal-fortress
RUN nimby sync -g nimby.lock

WORKDIR /workspace/coworld-tribal-quest
COPY tribal_quest.nimble .
RUN nimble refresh && nimble install -y --depsOnly
COPY . .

ARG NimFlags="-d:release -d:useMalloc --opt:speed --stackTrace:on"
RUN nim c \
  $NimFlags \
  --threads:on \
  --mm:orc \
  --path:src \
  --path:/workspace/coworld-tribal-fortress/src \
  --nimcache:/tmp/cogame-nimcache \
  --out:/bin/tribal_quest \
  src/tribal_quest.nim

FROM debian:bookworm-slim

RUN apt-get update && \
  apt-get install -y --no-install-recommends ca-certificates curl && \
  rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /bin/tribal_quest /bin/tribal_quest
COPY --from=build /workspace/coworld-tribal-fortress/data ./data

EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=2s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/healthz || exit 1
CMD ["/bin/tribal_quest", "--address:0.0.0.0", "--port:8080"]
