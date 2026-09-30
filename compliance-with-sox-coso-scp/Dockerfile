# DuckDB CLI on a slim Debian base. Nothing else is needed: the whole
# example is SQL, with no extensions and no network access at run time.

# Where the DuckDB CLI comes from.
#
# The default fetches the official release from GitHub over a verified TLS
# connection. On a machine whose TLS is intercepted - a corporate proxy, or
# an antivirus HTTPS scanner - that download fails with "unable to get local
# issuer certificate". Rather than teaching the image to trust the
# interceptor, point this at an image that already carries the binary:
#
#   docker build --build-arg DUCKDB_IMAGE=datacatering/duckdb:v1.5.5 -t compliance-sox .
#
# The stage below uses whatever duckdb it finds in that image and downloads
# nothing.
ARG DUCKDB_IMAGE=debian:12-slim

FROM ${DUCKDB_IMAGE} AS duckdb
ARG DUCKDB_VERSION=1.5.5
# Set by buildx; amd64 or arm64, which is exactly how DuckDB names its assets.
ARG TARGETARCH=amd64
SHELL ["/bin/sh", "-c"]
RUN set -eu; \
    if [ -x /duckdb ]; then cp /duckdb /tmp/duckdb; \
    elif command -v duckdb >/dev/null 2>&1; then cp "$(command -v duckdb)" /tmp/duckdb; \
    else \
      apt-get update; \
      apt-get install -y --no-install-recommends ca-certificates curl unzip; \
      curl -fsSL -o /tmp/duckdb.zip \
        "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-linux-${TARGETARCH}.zip"; \
      unzip -q /tmp/duckdb.zip -d /tmp; \
      rm /tmp/duckdb.zip; \
    fi; \
    chmod +x /tmp/duckdb

FROM debian:12-slim
COPY --from=duckdb /tmp/duckdb /usr/local/bin/duckdb
RUN duckdb -c "SELECT version()"

WORKDIR /work
COPY sql/ ./sql/
COPY intercompany-validation.sql intercompany-at-scale.sql run.sh ./
RUN chmod +x run.sh

# Output lands here: mount a volume over it to keep the artefacts.
VOLUME ["/work/out"]

# TRADES sets the generated volume; see run.sh.
ENV TRADES=5000000

ENTRYPOINT ["./run.sh"]
CMD ["scale"]
