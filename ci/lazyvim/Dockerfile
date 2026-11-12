FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/nvim/bin:${PATH}"
ENV XDG_CONFIG_HOME=/tmp/nvim-config
ENV XDG_DATA_HOME=/tmp/nvim-data
ENV XDG_STATE_HOME=/tmp/nvim-state
ENV XDG_CACHE_HOME=/tmp/nvim-cache

WORKDIR /workspace

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates curl git shfmt tar \
    && rm -rf /var/lib/apt/lists/*

COPY ci/lazyvim/versions.env /tmp/versions.env

RUN set -eu; \
    . /tmp/versions.env; \
    mkdir -p /opt/nvim /opt/nvim-plugins; \
    curl --fail --location --silent --show-error \
      "https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-linux-x86_64.tar.gz" \
      | tar -xz --strip-components=1 -C /opt/nvim; \
    clone_at() { \
      repo="$1"; name="$2"; revision="$3"; \
      git clone --filter=blob:none --no-checkout \
        "https://github.com/${repo}.git" "/opt/nvim-plugins/${name}"; \
      git -C "/opt/nvim-plugins/${name}" checkout --detach "${revision}"; \
      test "$(git -C "/opt/nvim-plugins/${name}" rev-parse HEAD)" = "${revision}"; \
    }; \
    clone_at folke/lazy.nvim lazy.nvim "${LAZY_NVIM_SHA}"; \
    clone_at LazyVim/LazyVim LazyVim "${LAZYVIM_SHA}"; \
    clone_at nvim-mini/mini.pairs mini.pairs "${MINI_PAIRS_SHA}"; \
    clone_at saghen/blink.cmp blink.cmp "${BLINK_CMP_SHA}"; \
    clone_at stevearc/conform.nvim conform.nvim "${CONFORM_SHA}"; \
    /opt/nvim/bin/nvim --version | head -n 1; \
    git -C /opt/nvim-plugins/LazyVim rev-parse HEAD; \
    git -C /opt/nvim-plugins/mini.pairs rev-parse HEAD; \
    git -C /opt/nvim-plugins/blink.cmp rev-parse HEAD; \
    git -C /opt/nvim-plugins/conform.nvim rev-parse HEAD; \
    git -C /opt/nvim-plugins/lazy.nvim rev-parse HEAD; \
    shfmt --version

COPY . /workspace

CMD ["bash", "tests/run-lazyvim.sh"]
