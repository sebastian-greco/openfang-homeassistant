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
      file \
      tzdata \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    REPO="RightNow-AI/openfang"; \
    VERSION="$OPENFANG_VERSION"; \
    ARCH="${TARGETARCH:-${BUILD_ARCH:-}}"; \
    if [ -z "$ARCH" ]; then \
      echo "ERROR: Neither TARGETARCH nor BUILD_ARCH is set -- cannot determine architecture"; \
      exit 1; \
    fi; \
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
    # Reject archives with path-traversal members:
    #  - leading '../' or absolute '/' paths
    #  - bare '..' or '.' as a full member name (e.g. '..' or '.')
    #  - embedded '/../', terminal '/..' or '/.' components (e.g. a/.. or a/b/..).
    # Use pipefail so a tar failure is not silently masked by grep's exit status.
    if (set -o pipefail; tar -tzf /tmp/openfang.tar.gz | grep -qE '(^\.\./|^/|^\.\.$|^\.$|/\.\./|/\.\.$|/\.$)'); then \
      echo 'ERROR: archive contains path-traversal members -- rejecting'; exit 1; \
    fi; \
    # --no-dereference: prevents symlink-in-archive writing outside the extract dir.
    tar xzf /tmp/openfang.tar.gz -C /tmp/openfang-extract --no-same-owner --no-same-permissions --no-overwrite-dir --no-dereference; \
    # Verify extracted binary is a regular file, not a symlink.
    if [ ! -f /tmp/openfang-extract/openfang ] || [ -L /tmp/openfang-extract/openfang ]; then \
      echo "ERROR: 'openfang' binary missing or is a symlink -- rejecting archive"; \
      exit 1; \
    fi; \
    # Reject hardlinks: nlink > 1 means the inode is shared with another path in the image
    # (e.g. /bin/bash), which would allow installing the wrong ELF that still passes file check.
    NLINK=$(stat -c '%h' /tmp/openfang-extract/openfang); \
    if [ "$NLINK" -gt 1 ]; then \
      echo "ERROR: 'openfang' is a hardlink (nlink=${NLINK}) -- rejecting archive"; \
      exit 1; \
    fi; \
    # Confirm it is an ELF executable, not a shell script or other unexpected file type.
    if ! file /tmp/openfang-extract/openfang | grep -q 'ELF.*executable'; then \
      echo "ERROR: 'openfang' is not an ELF executable -- rejecting"; \
      exit 1; \
    fi; \
    install -m 0755 /tmp/openfang-extract/openfang /usr/local/bin/openfang; \
    rm -rf /tmp/openfang.tar.gz /tmp/openfang.sha256 /tmp/openfang-extract

COPY run.sh /run.sh
RUN chmod +x /run.sh

EXPOSE 4200 8099

CMD ["/run.sh"]
