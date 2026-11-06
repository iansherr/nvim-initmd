#!/usr/bin/env bash
# test-pack-config.sh - Isolated real-session test for vim.pack config
#
# Usage:
#   ./scripts/test-pack-config.sh              # Full test (clean + install + load)
#   ./scripts/test-pack-config.sh --help       # Show usage
#
# Environment:
#   NVIM_PACK_MD   - Path to markdown config (default: nvim-config-template.md)
#   TEST_DIR       - Isolated test directory (default: a fresh temporary directory)

set -euo pipefail

# --- Configuration ---
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NVIM_PACK_MD="${NVIM_PACK_MD:-${PROJECT_ROOT}/nvim-config-template.md}"
TEST_DIR="${TEST_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/nvim-pack-session.XXXXXX")}"
NVIM_RUNTIME_DIR="${PROJECT_ROOT}/runtime"
cd "${PROJECT_ROOT}"

if [[ "${NVIM_PACK_MD}" != /* ]]; then
    NVIM_PACK_MD="${PROJECT_ROOT}/${NVIM_PACK_MD}"
fi

# Isolated XDG paths
export XDG_CONFIG_HOME="${TEST_DIR}/xdg/config"
export XDG_DATA_HOME="${TEST_DIR}/xdg/data"
export XDG_STATE_HOME="${TEST_DIR}/xdg/state"
export XDG_CACHE_HOME="${TEST_DIR}/xdg/cache"

NVIM_CONFIG_DIR="${XDG_CONFIG_HOME}/nvim"
NVIM_PACK_DIR="${XDG_DATA_HOME}/nvim/site/pack"
NVIM_CACHE_DIR="${XDG_CACHE_HOME}/nvim"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helper Functions ---
log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

setup_test_env() {
    log_info "Setting up isolated test environment"

    # Create XDG directory structure
    mkdir -p "${NVIM_CONFIG_DIR}"
    mkdir -p "${NVIM_PACK_DIR}/core/start"
    mkdir -p "${NVIM_PACK_DIR}/core/opt"
    mkdir -p "${NVIM_CACHE_DIR}/init-md-gen/lua"
    mkdir -p "${NVIM_CACHE_DIR}/init-modules"

    # Copy markdown config as init.md
    if [[ ! -f "${NVIM_PACK_MD}" ]]; then
        log_error "Markdown config not found: ${NVIM_PACK_MD}"
        exit 1
    fi
    cp "${NVIM_PACK_MD}" "${NVIM_CONFIG_DIR}/init.md"
    log_ok "Copied init.md"

    # Copy runtime modules to config directory (where init-pack-gen.lua expects them)
    local modules_target="${NVIM_CONFIG_DIR}/init-modules"
    mkdir -p "${modules_target}"
    for module in markdown_parser.lua cache_generator.lua manifest_manager.lua init-pack-gen.lua; do
        if [[ -f "${NVIM_RUNTIME_DIR}/${module}" ]]; then
            cp "${NVIM_RUNTIME_DIR}/${module}" "${modules_target}/"
        fi
    done
    log_ok "Copied modules"

    # Create minimal init.lua that loads init-pack-gen
    cat > "${NVIM_CONFIG_DIR}/init.lua" << 'EOF'
-- Minimal bootstrap for isolated testing
-- Loads init-pack-gen.lua from init-modules directory

local cache_dir = vim.fn.stdpath("cache") .. "/init-md-gen"

-- Load and run the pack-gen bootstrap (init-pack-gen.lua handles module loading internally)
local ok, err = pcall(function()
    dofile(vim.fn.stdpath("config") .. "/init-modules/init-pack-gen.lua")
end)

if not ok then
    vim.notify("Bootstrap error: " .. tostring(err), vim.log.levels.ERROR)
    -- Write error to file for script to detect
    local f = io.open(cache_dir .. "/test_error.txt", "w")
    if f then
        f:write(tostring(err) .. "\n")
        f:close()
    end
end

-- Write test result marker
    local result_file = cache_dir .. "/test_result.txt"
    local f = io.open(result_file, "w")
    if f then
    -- Check if plugins were loaded (nvim 0.12 installs to core/opt, not core/start)
    local pack_plugins = vim.fn.glob(vim.fn.stdpath("data") .. "/site/pack/core/opt/*", true, true)
        local count = #pack_plugins
        f:write("plugins_installed=" .. count .. "\n")
        f:write("runtime_ok=" .. (ok and "true" or "false") .. "\n")
        local setup_errors = vim.g.init_md_setup_errors or {}
        f:write("setup_errors=" .. #setup_errors .. "\n")
        f:write("main_config_loaded=" .. (vim.g.mapleader == " " and vim.o.number and "true" or "false") .. "\n")
        f:close()
end

-- Quit after test
vim.cmd("quitall!")
EOF
    log_ok "Created init.lua"
}

run_neovim_test() {
    log_info "Running Neovim headless test..."

    local nvim_output
    local nvim_exit_code=0

    # Run neovim headlessly with a timeout
    nvim_output=$(timeout 300 nvim --headless \
        -u "${NVIM_CONFIG_DIR}/init.lua" \
        +'"set nomore"' \
        2>&1) || nvim_exit_code=$?

    if [[ ${nvim_exit_code} -eq 124 ]]; then
        log_error "Neovim timed out (300s limit)"
        return 1
    fi
    if [[ ${nvim_exit_code} -ne 0 ]]; then
        log_error "Neovim exited with status ${nvim_exit_code}"
        echo "Neovim output (last 50 lines):"
        echo "${nvim_output}" | tail -50
        return 1
    fi

    # Check for test result file
    local result_file="${NVIM_CACHE_DIR}/init-md-gen/test_result.txt"
    local error_file="${NVIM_CACHE_DIR}/init-md-gen/test_error.txt"

    if [[ -f "${error_file}" ]]; then
        log_error "Bootstrap error detected:"
        cat "${error_file}"
        return 1
    fi

    if [[ -f "${result_file}" ]]; then
        log_ok "Test result file found"
        cat "${result_file}"
        if ! grep -q '^runtime_ok=true$' "${result_file}" \
            || ! grep -q '^setup_errors=0$' "${result_file}" \
            || ! grep -q '^main_config_loaded=true$' "${result_file}"; then
            log_error "Bootstrap, setup block, or main config acceptance check failed"
            return 1
        fi
        local installed_count
        installed_count=$(sed -n 's/^plugins_installed=//p' "${result_file}")
        if [[ ! "${installed_count}" =~ ^[0-9]+$ ]] || (( installed_count < 1 )); then
            log_error "Expected at least one installed plugin; got '${installed_count}'"
            return 1
        fi
        return 0
    else
        log_warn "No test result file found"
        echo "Neovim output (last 50 lines):"
        echo "${nvim_output}" | tail -50
        return 1
    fi
}

validate_markdown() {
    log_info "Validating markdown config..."

    nvim -l "${PROJECT_ROOT}/scripts/test-markdown-parser.lua"
    log_ok "Parser edge-case checks passed"

    if [[ ! -f "${NVIM_PACK_MD}" ]]; then
        log_error "Markdown not found: ${NVIM_PACK_MD}"
        exit 1
    fi

    # Count spec blocks
    local spec_count
    spec_count=$(grep -c '\*\*Spec:\*\*' "${NVIM_PACK_MD}" 2>/dev/null || echo "0")
    log_info "Found ${spec_count} **Spec:** blocks"

    # Count setup executable blocks
    local setup_count
    setup_count=$(grep -c '\*\*Setup: executable\*\*' "${NVIM_PACK_MD}" 2>/dev/null || echo "0")
    log_info "Found ${setup_count} **Setup: executable** blocks"

    # Count total lines
    local line_count
    line_count=$(wc -l < "${NVIM_PACK_MD}" | tr -d ' ')
    log_info "Total lines: ${line_count}"

    if [[ ${spec_count} -eq 0 ]]; then
        log_warn "No Spec blocks found - no plugins will be installed"
    fi
}

print_summary() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}       Test Environment Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "Test directory:    ${TEST_DIR}"
    echo "Config directory:  ${NVIM_CONFIG_DIR}"
    echo "Pack directory:    ${NVIM_PACK_DIR}"
    echo "Cache directory:   ${NVIM_CACHE_DIR}"
    echo "Markdown source:   ${NVIM_PACK_MD}"
    echo ""
    echo "To inspect manually:"
    echo "  ls -la ${NVIM_PACK_DIR}/core/opt/  # Installed plugins"
    echo "  cat ${NVIM_CACHE_DIR}/init-md-gen/00_init.lua  # Generated cache"
    echo ""
}

# --- Main ---
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--help]"
        echo ""
        echo "Options:"
        echo "  --help        Show this help"
        echo ""
        echo "Environment:"
        echo "  NVIM_PACK_MD  Path to markdown config"
        echo "  TEST_DIR      Isolated test directory"
        exit 0
        ;;
    "")
        # Full test: validate + setup + install + load
        validate_markdown
        echo ""
        setup_test_env
        echo ""
        run_neovim_test
        echo ""
        print_summary
        exit 0
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
