#!/bin/bash
# setup-init-md.sh
# Sets up the vim.pack bootstrap from init.md

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${HOME}/.config/nvim"
CACHE_DIR="${HOME}/.cache/nvim/init-md-gen"
MODULES_DIR="${CONFIG_DIR}/init-modules"

echo "Setting up init.md vim.pack bootstrap..."

# Create directories
mkdir -p "${MODULES_DIR}"
mkdir -p "${CACHE_DIR}"
mkdir -p "${HOME}/.local/share/nvim/site/pack/core/start"
mkdir -p "${HOME}/.local/share/nvim/site/pack/core/opt"

# Copy modules
echo "Installing modules..."
cp "${PROJECT_ROOT}/runtime/markdown_parser.lua" "${MODULES_DIR}/"
cp "${PROJECT_ROOT}/runtime/cache_generator.lua" "${MODULES_DIR}/"
cp "${PROJECT_ROOT}/runtime/manifest_manager.lua" "${MODULES_DIR}/"

# Generated files depend on the runtime module versions as well as init.md.
# Force one regeneration after an installer upgrade so stale generated modules
# cannot outlive the runtime that produced them.
rm -f "${CACHE_DIR}/manifest.txt"

# Copy bootstrap as init.lua
echo "Installing bootstrap..."
if [ -f "${CONFIG_DIR}/init.lua" ] && ! grep -q '^-- init-pack-gen.lua$' "${CONFIG_DIR}/init.lua"; then
    echo "Refusing to replace existing ${CONFIG_DIR}/init.lua. Back it up or merge the bootstrap manually." >&2
    exit 1
fi
cp "${PROJECT_ROOT}/runtime/init-pack-gen.lua" "${CONFIG_DIR}/init.lua"

# Copy init.md if it doesn't exist
if [ ! -f "${CONFIG_DIR}/init.md" ]; then
    echo "Copying init.md..."
    cp "${PROJECT_ROOT}/nvim-config-template.md" "${CONFIG_DIR}/init.md"
fi

echo "Setup complete!"
echo ""
echo "Test it with: nvim"
echo "Or enable dev mode: NVIM_DEV=1 nvim"
