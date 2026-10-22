# ─────────────────────────────────────────────────────────────────────────────
# osint-toolbox — a single Docker image bundling three non-interactive OSINT
# tools behind one menu/batch launcher. Everything runs inside the container,
# so the host system stays clean.
#
# Bundled tools:
#   mosint        (Go)   — email OSINT
#   gosearch      (Go)   — username search across 300+ sites
#   user-scanner  (pip)  — username + email search across 1000+ platforms
# ─────────────────────────────────────────────────────────────────────────────

# Start from an image that already ships Go. gosearch requires Go >= 1.25, so
# the base version matters: an older Go makes the build fail.
FROM golang:1.25-bookworm

# Never let apt prompt interactively during the build (it would hang).
ENV DEBIAN_FRONTEND=noninteractive

# Safety net: if a future tool version requires a newer Go than the image has,
# 'auto' lets Go download the matching toolchain instead of stopping. (The base
# image sets GOTOOLCHAIN=local, which forbids that.)
ENV GOTOOLCHAIN=auto

# ── System dependencies ──────────────────────────────────────────────────────
# python3 + pip to run user-scanner and the batch script; git for Go module
# fetching; ca-certificates so the tools' HTTPS requests succeed. '2to3' is kept
# defensively: some transitive Python dependencies still invoke it at install
# time, and without it their build fails.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip git ca-certificates 2to3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/osint

# ── Go tools: mosint and gosearch ────────────────────────────────────────────
# 'go install' compiles each tool and drops the binary in /go/bin, which is
# already on PATH in this image. So 'mosint' and 'gosearch' become direct
# commands inside the container.
RUN go install github.com/alpkeskin/mosint/v3/cmd/mosint@latest \
    && go install github.com/ibnaleem/gosearch@latest

# ── Python tool: user-scanner ────────────────────────────────────────────────
# --break-system-packages is required on Debian 12+, where the system pip is
# "externally managed". It is safe here: the container is disposable, so there
# is no host Python to damage.
RUN pip install --no-cache-dir --break-system-packages user-scanner

# ── Launcher and batch runner ────────────────────────────────────────────────
COPY osint-launcher.sh /opt/osint/osint-launcher.sh
COPY osint-batch.py    /opt/osint/osint-batch.py
RUN chmod +x /opt/osint/osint-launcher.sh

# With no arguments the menu starts; `... osint-toolbox batch ...` runs headless.
ENTRYPOINT ["/opt/osint/osint-launcher.sh"]
