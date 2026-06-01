Camp CI build container for keep microVM
Reproduces tools from .github/workflows/ci.yml

Usage:
  podman build -t ghcr.io/camp-language/camp-ci:latest .
  podman push ghcr.io/camp-language/camp-ci:latest

FROM debian:bookworm-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

# System deps: LLVM 18 for Odin, node for tree-sitter generate
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    xz-utils \
    gnupg \
    lsb-release \
    && curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key | gpg --dearmor -o /usr/share/keyrings/llvm.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/llvm.gpg] http://apt.llvm.org/bookworm/ llvm-toolchain-bookworm-18 main" \
        > /etc/apt/sources.list.d/llvm.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        llvm-18-dev \
        clang-18 \
        lld-18 \
        llvm-18-linker-tools \
        nodejs \
        npm \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/lib/llvm-18/bin:${PATH}"

# --- Odin compiler (dev release) ---
RUN ODIR_URL="https://github.com/odin-lang/Odin/releases/download/dev-2026-05/odin-linux-amd64-dev-2026-05.tar.gz" \
    && curl -fsSL "$ODIR_URL" | tar -xzf - -C /usr/local/lib \
    && ln -s /usr/local/lib/odin-linux-amd64-nightly+2026-05-03 /usr/local/lib/odin \
    && ln -s /usr/local/lib/odin/odin /usr/local/bin/odin

# --- odinfmt (from OLS release) ---
RUN OLS_VER="dev-2026-05" \
    && curl -fsSL "https://github.com/DanielGavin/ols/releases/download/${OLS_VER}/ols-x86_64-unknown-linux-gnu.zip" \
        -o /tmp/ols.zip \
    && unzip -o /tmp/ols.zip "odinfmt*" -d /usr/local/bin \
    && mv /usr/local/bin/odinfmt-x86_64-unknown-linux-gnu /usr/local/bin/odinfmt \
    && chmod +x /usr/local/bin/odinfmt \
    && rm /tmp/ols.zip

# --- wasmtime ---
RUN curl -fsSL "https://github.com/bytecodealliance/wasmtime/releases/download/v45.0.0/wasmtime-v45.0.0-x86_64-linux.tar.xz" \
        | tar -xJf - -C /usr/local/lib \
    && ln -s /usr/local/lib/wasmtime-v45.0.0-x86_64-linux/wasmtime /usr/local/bin/wasmtime

# --- just ---
RUN curl -fsSL "https://github.com/casey/just/releases/download/1.51.0/just-1.51.0-x86_64-unknown-linux-musl.tar.gz" \
        | tar -xzf - -C /usr/local/bin just

# --- tree-sitter CLI ---
RUN TS_VER="v0.26.8" \
    && curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/download/${TS_VER}/tree-sitter-linux-x64.gz" \
        | gunzip > /usr/local/bin/tree-sitter \
    && chmod +x /usr/local/bin/tree-sitter

# --- runtime image ---
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        unzip \
        xz-utils \
        gnupg \
        lsb-release \
        nodejs \
        npm \
        git \
    && curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key | gpg --dearmor -o /usr/share/keyrings/llvm.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/llvm.gpg] http://apt.llvm.org/bookworm/ llvm-toolchain-bookworm-18 main" \
        > /etc/apt/sources.list.d/llvm.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        llvm-18-dev \
        lld-18 \
        clang-18 \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/lib/llvm-18/bin:${PATH}"

COPY --from=builder /usr/local/lib/odin-linux-amd64-nightly+2026-05-03 /usr/local/lib/odin-linux-amd64-nightly+2026-05-03
RUN ln -s /usr/local/lib/odin-linux-amd64-nightly+2026-05-03 /usr/local/lib/odin \
    && ln -s /usr/local/lib/odin/odin /usr/local/bin/odin

COPY --from=builder /usr/local/bin/odinfmt /usr/local/bin/odinfmt
COPY --from=builder /usr/local/lib/wasmtime-v45.0.0-x86_64-linux /usr/local/lib/wasmtime-v45.0.0-x86_64-linux
RUN ln -s /usr/local/lib/wasmtime-v45.0.0-x86_64-linux/wasmtime /usr/local/bin/wasmtime
COPY --from=builder /usr/local/bin/just /usr/local/bin/just
COPY --from=builder /usr/local/bin/tree-sitter /usr/local/bin/tree-sitter

WORKDIR /work
CMD ["just", "check"]
