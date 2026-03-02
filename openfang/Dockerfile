ARG BUILD_FROM
FROM ${BUILD_FROM}

ARG OPENFANG_VERSION="v0.2.5"
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

COPY rootfs /

EXPOSE 4200 8099

CMD ["/init"]
