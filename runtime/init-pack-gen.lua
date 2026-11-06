-- init-pack-gen.lua
-- Minimal bootstrap that:
-- 1. Checks cache freshness
-- 2. Regenerates if needed
-- 3. Loads everything

local vim = assert(_G["vim"])

local function get_cache_dir()
    return vim.fn.stdpath("cache") .. "/init-md-gen"
end

local function get_markdown_path()
    return vim.fn.stdpath("config") .. "/init.md"
end

local function get_modules_dir()
    return vim.fn.stdpath("config") .. "/init-modules"
end

local function load_module(name)
    local modules_dir = get_modules_dir()
    local module_path = modules_dir .. "/" .. name .. ".lua"
    local chunk, err = loadfile(module_path)
    if not chunk then
        error("Cannot load module " .. name .. ": " .. (err or "file not found"))
    end
    return chunk()
end

local function regenerate_cache()
    local cache_dir = get_cache_dir()
    local markdown_path = get_markdown_path()

    local parser = load_module("markdown_parser")
    local generator = load_module("cache_generator")

    local plugins, plugin_configs = parser.parse(markdown_path)
    if not plugins or #plugins == 0 then
        vim.notify("Error: No plugins found in markdown", vim.log.levels.ERROR)
        return false
    end

    local setup_blocks = parser.extract_executable_setups(markdown_path)
    generator.generate(cache_dir, plugins, plugin_configs, markdown_path, setup_blocks)
    return true
end

local function load_cache()
    local cache_dir = get_cache_dir()
    local init_path = cache_dir .. "/00_init.lua"

    if vim.fn.filereadable(init_path) ~= 1 then
        vim.notify("Cache not found, generating...", vim.log.levels.INFO)
        if not regenerate_cache() then
            return false
        end
    end

    -- Add cache lua directory to package path for lazyload/merge/setup modules
    local lua_dir = cache_dir .. "/lua/?.lua"
    package.path = lua_dir .. ";" .. package.path

    loadfile(init_path)()
    return true
end

-- On first run, check if cache exists and is fresh
local function init()
    local cache_dir = get_cache_dir()
    local markdown_path = get_markdown_path()
    local manifest = load_module("manifest_manager")

    -- Always regenerate on dev/testing (optional: can be gated with env var)
    local dev_mode = os.getenv("NVIM_DEV") == "1"

    if dev_mode or not manifest.is_cache_valid(cache_dir, markdown_path) then
        vim.notify("Regenerating cache from init.md...", vim.log.levels.INFO)
        if not regenerate_cache() then
            error("Failed to regenerate cache")
        end
    end

    load_cache()

    -- Load main config from markdown
    local parser = load_module("markdown_parser")
    for index, main_lua in ipairs(parser.extract_main_lua_blocks(markdown_path)) do
        local chunk, err = load(main_lua, "init.md main config #" .. index)
        if not chunk then
            error(err)
        end
        chunk()
    end

    local setup_path = cache_dir .. "/lua/setup.lua"
    if vim.fn.filereadable(setup_path) == 1 then
        local setup = loadfile(setup_path)()
        if setup and setup.run then
            setup.run()
        end
    end
end

init()
