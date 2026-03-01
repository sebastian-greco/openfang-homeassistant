ARG BUILD_FROM
FROM ${BUILD_FROM}

ARG OPENFANG_VERSION="v0.1.0"
ARG TARGETARCH
ARG BUILD_ARCH

ENV DEBIAN_FRONTEND=noninteractive

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
    ARCH="${TARGETARCH:-$BUILD_ARCH}"; \
    echo "Installing OpenFang ${VERSION} for arch=${ARCH}"; \
    case "${ARCH}" in \
      amd64)   PLATFORM="x86_64-unknown-linux-gnu"  ;; \
      arm64|aarch64) PLATFORM="aarch64-unknown-linux-gnu" ;; \
      *) echo "Unsupported architecture: ${ARCH}"; exit 1 ;; \
    esac; \
    URL="https://github.com/${REPO}/releases/download/${VERSION}/openfang-${PLATFORM}.tar.gz"; \
    # Note: sha256 is fetched from the same upstream release as the binary. This detects
    # accidental corruption but not a fully-compromised release. Upstream release signing
    # (cosign/sigstore) is the long-term mitigation; accepted limitation for now.
    curl -fsSL --retry 3 --retry-connrefused "${URL}" -o /tmp/openfang.tar.gz; \
    if ! curl -fsSL --retry 3 --retry-connrefused "${URL}.sha256" -o /tmp/openfang.sha256; then \
      echo "ERROR: sha256 file not found for ${URL}.sha256 — refusing to install unverified binary"; \
      exit 1; \
    fi; \
    EXPECTED=$(awk '{print $1}' /tmp/openfang.sha256); \
    ACTUAL=$(sha256sum /tmp/openfang.tar.gz | awk '{print $1}'); \
    if [ "$EXPECTED" != "$ACTUAL" ]; then \
      echo "Checksum mismatch! expected=${EXPECTED} got=${ACTUAL}"; exit 1; \
    fi; \
    mkdir -p /tmp/openfang-extract; \
    tar xzf /tmp/openfang.tar.gz -C /tmp/openfang-extract --no-same-owner --no-same-permissions; \
    if [ ! -f /tmp/openfang-extract/openfang ] || [ -L /tmp/openfang-extract/openfang ]; then \
      echo "ERROR: 'openfang' binary missing or is a symlink — rejecting archive"; \
      exit 1; \
    fi; \
    install -m 0755 /tmp/openfang-extract/openfang /usr/local/bin/openfang; \
    rm -rf /tmp/openfang.tar.gz /tmp/openfang.sha256 /tmp/openfang-extract

COPY run.sh /run.sh
RUN chmod +x /run.sh

EXPOSE 4200 8099

CMD ["/run.sh"]
