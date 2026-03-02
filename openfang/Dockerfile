ARG BUILD_FROM
FROM ${BUILD_FROM}
ARG OPENFANG_VERSION="v0.2.6"
ARG TTYD_VERSION="1.7.7"
ARG TARGETARCH

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      jq \
      nginx \
      tzdata \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    REPO="RightNow-AI/openfang"; \
    VERSION="$OPENFANG_VERSION"; \
    echo "Installing OpenFang ${VERSION}"; \
    case "${TARGETARCH}" in \
      amd64)   PLATFORM="x86_64-unknown-linux-gnu"  ;; \
      arm64|aarch64) PLATFORM="aarch64-unknown-linux-gnu" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    URL="https://github.com/${REPO}/releases/download/${VERSION}/openfang-${PLATFORM}.tar.gz"; \
    curl -fsSL --retry 3 "${URL}" -o /tmp/openfang.tar.gz; \
    if curl -fsSL --retry 3 "${URL}.sha256" -o /tmp/openfang.sha256 2>/dev/null; then \
      EXPECTED=$(cut -d' ' -f1 < /tmp/openfang.sha256); \
      ACTUAL=$(sha256sum /tmp/openfang.tar.gz | cut -d' ' -f1); \
      if [ "$EXPECTED" != "$ACTUAL" ]; then \
        echo "Checksum mismatch! expected=$EXPECTED got=$ACTUAL"; exit 1; \
      fi; \
    fi; \
    tar xzf /tmp/openfang.tar.gz -C /usr/local/bin; \
    chmod +x /usr/local/bin/openfang; \
    rm -f /tmp/openfang.tar.gz /tmp/openfang.sha256

# Install ttyd (web-based terminal) — arch-aware single static binary
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64)        TTYD_ARCH="x86_64"   ;; \
      arm64|aarch64) TTYD_ARCH="aarch64" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    curl -fsSL --retry 3 \
      "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${TTYD_ARCH}" \
      -o /usr/local/bin/ttyd; \
    chmod +x /usr/local/bin/ttyd

COPY rootfs /

EXPOSE 4200 8099

ENTRYPOINT ["/init"]
