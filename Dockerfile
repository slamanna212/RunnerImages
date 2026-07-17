# syntax=docker/dockerfile:1.7

# Keep toolchains in image stages so Dependabot can update them.
FROM node:24.18.0-bookworm-slim AS node-toolchain
FROM golang:1.26.5-bookworm AS go-toolchain
FROM rust:1.97.0-bookworm AS rust-toolchain

FROM go-toolchain AS hugo-toolchain
WORKDIR /tmp/hugo-toolchain
COPY hugo/go.mod hugo/go.sum ./
RUN CGO_ENABLED=1 go install -tags extended github.com/gohugoio/hugo \
    && /go/bin/hugo version

# GitHub's supported ARC image supplies the runner, container hooks, Docker CLI,
# Buildx, runner user (UID 1001), and /home/runner/run.sh contract.
FROM ghcr.io/actions/actions-runner:2.335.1@sha256:08c30b0a7105f64bddfc485d2487a22aa03932a791402393352fdf674bda2c29 AS runner-base

USER root

LABEL org.opencontainers.image.source="https://github.com/slamanna212/RunnerImages" \
      org.opencontainers.image.documentation="https://github.com/slamanna212/RunnerImages" \
      org.opencontainers.image.licenses="MIT"

# The upstream static Docker bundle includes a local daemon and runtime. ARC
# uses only the client; DinD runs in a separate sidecar when enabled.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      file \
      gh \
      jq \
      unzip \
      xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f \
      /usr/bin/containerd \
      /usr/bin/containerd-shim-runc-v2 \
      /usr/bin/ctr \
      /usr/bin/docker-proxy \
      /usr/bin/dockerd \
      /usr/bin/runc \
    && gh --version \
    && docker --version \
    && docker buildx version

FROM runner-base AS node-runner

USER root
COPY --from=node-toolchain /usr/local/ /usr/local/
ENV RUNNER_TOOL_CACHE=/home/runner/_tool \
    AGENT_TOOLSDIRECTORY=/home/runner/_tool
RUN NODE_VERSION="$(node --version | sed 's/^v//')" \
    && mkdir -p "/home/runner/_tool/node/${NODE_VERSION}" \
    && ln -s /usr/local "/home/runner/_tool/node/${NODE_VERSION}/x64" \
    && touch "/home/runner/_tool/node/${NODE_VERSION}/x64.complete" \
    && chown -R runner:docker /home/runner/_tool \
    && chmod -R u+rwX,go+rX /home/runner/_tool \
    && node --version \
    && npm --version
USER runner

FROM node-runner AS apogee

USER root
COPY --from=rust-toolchain /usr/local/cargo/ /usr/local/cargo/
COPY --from=rust-toolchain /usr/local/rustup/ /usr/local/rustup/
ENV CARGO_HOME=/usr/local/cargo \
    RUSTUP_HOME=/usr/local/rustup \
    PATH=/usr/local/cargo/bin:${PATH}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential \
      desktop-file-utils \
      libayatana-appindicator3-dev \
      libfuse2 \
      libgdk-pixbuf2.0-bin \
      libglib2.0-bin \
      libgtk-3-bin \
      librsvg2-dev \
      libssl-dev \
      libwebkit2gtk-4.1-dev \
      libxdo-dev \
      patchelf \
      perl \
      pkg-config \
      rpm \
      wget \
      xdg-utils \
      zsync \
    && rm -rf /var/lib/apt/lists/* \
    && rustc --version \
    && cargo --version

USER runner

FROM node-runner AS matchexec

USER runner

FROM node-runner AS tonysofwestreading

USER root
ENV PLAYWRIGHT_BROWSERS_PATH=/home/runner/.cache/ms-playwright
COPY package.json /tmp/runner-images/package.json
RUN PLAYWRIGHT_VERSION="$(node -p "require('/tmp/runner-images/package.json').devDependencies.playwright")" \
    && npx --yes "playwright@${PLAYWRIGHT_VERSION}" install --with-deps chromium \
    && chown -R runner:docker /home/runner/.cache \
    && rm -rf /root/.npm /tmp/runner-images
USER runner

FROM runner-base AS slamanna-com

USER root
COPY --from=go-toolchain /usr/local/go/ /usr/local/go/
COPY --from=hugo-toolchain /go/bin/hugo /usr/local/bin/hugo
ENV RUNNER_TOOL_CACHE=/home/runner/_tool \
    AGENT_TOOLSDIRECTORY=/home/runner/_tool \
    PATH=/usr/local/go/bin:${PATH}
RUN apt-get update \
    && apt-get install -y --no-install-recommends tidy \
    && rm -rf /var/lib/apt/lists/* \
    && GO_VERSION="$(go env GOVERSION | sed 's/^go//')" \
    && mkdir -p "/home/runner/_tool/go/${GO_VERSION}" \
    && ln -s /usr/local/go "/home/runner/_tool/go/${GO_VERSION}/x64" \
    && touch "/home/runner/_tool/go/${GO_VERSION}/x64.complete" \
    && chown -R runner:docker /home/runner/_tool \
    && chmod -R u+rwX,go+rX /home/runner/_tool \
    && go version \
    && hugo version \
    && tidy -version
USER runner

FROM node-runner AS slamanna-food

USER runner
