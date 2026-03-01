ARG BUILD_FROM
FROM ${BUILD_FROM}

ARG OPENFANG_VERSION="latest"
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
    if [ "$OPENFANG_VERSION" = "latest" ]; then \
      VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
                  | grep '"tag_name"' | head -1 | cut -d'"' -f4); \
    else \
      VERSION="$OPENFANG_VERSION"; \
    fi; \
    echo "Installing OpenFang ${VERSION}"; \
    case "${TARGETARCH}" in \
      amd64)  PLATFORM="x86_64-unknown-linux-gnu"  ;; \
      arm64)  PLATFORM="aarch64-unknown-linux-gnu" ;; \
      aarch64) PLATFORM="aarch64-unknown-linux-gnu" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    URL="https://github.com/${REPO}/releases/download/${VERSION}/openfang-${PLATFORM}.tar.gz"; \
    curl -fsSL "${URL}" -o /tmp/openfang.tar.gz; \
    if curl -fsSL "${URL}.sha256" -o /tmp/openfang.sha256 2>/dev/null; then \
      EXPECTED=$(cut -d' ' -f1 < /tmp/openfang.sha256); \
      ACTUAL=$(sha256sum /tmp/openfang.tar.gz | cut -d' ' -f1); \
      if [ "$EXPECTED" != "$ACTUAL" ]; then \
        echo "Checksum mismatch! expected=$EXPECTED got=$ACTUAL"; exit 1; \
      fi; \
    fi; \
    tar xzf /tmp/openfang.tar.gz -C /usr/local/bin; \
    chmod +x /usr/local/bin/openfang; \
    rm -f /tmp/openfang.tar.gz /tmp/openfang.sha256; \
    openfang --version

COPY run.sh /run.sh
RUN chmod +x /run.sh

EXPOSE 4200

CMD ["/run.sh"]
