FROM ubuntu:24.04

# `uv` is installed to a fixed prefix rather than $HOME/.local/bin (its default), so later stages
# find it without hunting. `/app/.venv/bin` first on PATH makes `pastalean` and `python` resolve to
# the project environment.
ENV DEBIAN_FRONTEND=noninteractive \
    ELAN_HOME=/root/.elan \
    UV_INSTALL_DIR=/usr/local/bin \
    UV_PROJECT_ENVIRONMENT=/app/.venv \
    UV_LINK_MODE=copy \
    PATH=/app/.venv/bin:/root/.elan/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /app

# No `python3`: the project needs >= 3.13 and Ubuntu 24.04 ships 3.12, so uv fetches its own below.
# `curl` stays for the healthcheck; `git` is how lake materialises the dependencies in the manifest.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        build-essential \
        zstd \
    && rm -rf /var/lib/apt/lists/*

# `--default-toolchain none`: elan installs the version pinned by ./lean-toolchain on first use.
RUN curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
    | sh -s -- -y --default-toolchain none --no-modify-path

RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# ---------------------------------------------------------------------------------------------
# Lean. Split from the source copy so a code change does not re-download Mathlib's build cache.
# ---------------------------------------------------------------------------------------------
COPY lean-toolchain lakefile.toml lake-manifest.json ./

RUN lean --version \
    && lake --version \
    && lake exe cache get

COPY PastaLean ./PastaLean
COPY Libraries ./Libraries
COPY PastaLean.lean Libraries.lean py2lean.lean ./

# `Libraries` is named explicitly: lakefile.toml's `defaultTargets` is only `PastaLean` + `py2lean`,
# but every generated program opens with `import Libraries`, and `lake env lean` needs its `.olean`
# files. A bare `lake build` leaves them absent and every compile-check fails at runtime with
# "object file '...Libraries/collections/CollectionsDef.olean' ... does not exist".
RUN lake build PastaLean Libraries py2lean

# ---------------------------------------------------------------------------------------------
# Python. `uv sync` installs the project *editable*, which is required, not a preference:
# `paths.py` derives REPO_ROOT from the package's own location (`src/` -> `/app`), and a copy under
# site-packages would point `lake` at the wrong working directory.
# ---------------------------------------------------------------------------------------------
COPY pyproject.toml uv.lock README.md ./
COPY src ./src
COPY docs ./docs

# `--locked` fails the build if uv.lock has drifted from pyproject.toml, rather than silently
# resolving something else. `--extra server` pulls in fastapi/uvicorn, which `pastalean serve` needs.
RUN uv sync --locked --no-dev --extra server

# Importing Mathlib on a cold page cache can exceed the 300s default.
ENV PASTALEAN_STARTUP_TIMEOUT=600

EXPOSE 6789

# The backend imports Mathlib at boot, so give it room before the first probe counts.
HEALTHCHECK --interval=30s --timeout=10s --start-period=6m --retries=3 \
    CMD curl -fsS http://localhost:6789/health || exit 1

# Binds every interface, as a container must. There is no authentication and `/run` executes the
# caller's program: publish this port only to a network you trust.
CMD ["pastalean", "serve", "--port", "6789"]
