-- markdown_parser.lua
-- Parses Markdown plugin specs and main config blocks.
-- Supports both formats:
--   1. Lazy.nvim style: "User/repo" shorthand → expanded to full GitHub URL
--   2. Pack-feeling style: full "https://github.com/..." URLs (preferred)
-- Extracts plugin specs and converts to vim.pack format

local M = {}

-- Read markdown file
local function read_markdown(filepath)
    local file = io.open(filepath, "r")
    if not file then
        error("Cannot read markdown file: " .. filepath)
    end
    local content = file:read("*a")
    file:close()
    return content
end

-- Extract all lua code blocks from markdown
local function extract_code_blocks(content)
    local blocks = {}
    local current_block = ""
    local in_code_block = false
    local pending_spec = false
    local current_is_spec = false
    local has_explicit_spec_blocks = content:match("%*%*Spec:%*%*") or content:match("<summary>Spec</summary>")

    for line in content:gmatch("[^\n]+") do
        -- Standalone label only: inline mentions of "**Spec:**" in prose must
        -- not mark the next lua block as a spec.
        if line:match("^%s*%*%*Spec:%*%*%s*$") or line:match("^%s*<summary>Spec</summary>%s*$") then
            pending_spec = true
        end

        if line:match("^```lua$") then
            in_code_block = true
            current_block = ""
            current_is_spec = pending_spec or not has_explicit_spec_blocks
            pending_spec = false
        elseif line:match("^```$") and in_code_block then
            in_code_block = false
            if current_is_spec and current_block:match("return%s*{") then
                table.insert(blocks, current_block)
            end
            current_is_spec = false
        elseif in_code_block then
            current_block = current_block .. line .. "\n"
        end
    end

    return blocks
end

-- Load a lua table from a return statement
local function load_spec(spec_code)
    local env = {}
    setmetatable(env, { __index = _G })

    local func, err = load(spec_code, "spec", "t", env)
    if not func then
        return nil, err
    end

    local ok, result = pcall(func)
    if not ok then
        return nil, result
    end

    return result
end

-- Convert short GitHub path to full URL
local function expand_github_url(src)
    if src:match("^https?://") then
        return src  -- Already full URL
    end
    if src:match("^[%w_.%-]+/[%w_.%-]+$") then
        return "https://github.com/" .. src
    end
    return src
end

-- Convert lazy.nvim plugin spec to vim.pack format
local function convert_to_pack_format(lazy_spec)
    if type(lazy_spec) ~= "table" then
        return nil
    end

    -- Unwrap nested specs such as { { "owner/repo", ... } }, but keep
    -- the common lazy.nvim form { "owner/repo", opts = ... } intact.
    if type(lazy_spec[1]) == "table" and not lazy_spec.src then
        lazy_spec = lazy_spec[1]
    end
    if type(lazy_spec) ~= "table" then
        return nil
    end

    -- Extract source URL
    local src = lazy_spec[1] or lazy_spec.src
    if not src then
        return nil
    end

    src = expand_github_url(src)

    local pack_spec = {
        src = src,
        load = lazy_spec.load or "start",  -- vim.pack default
        name = lazy_spec.name,
        branch = lazy_spec.branch,
    }

    -- Pass through lazy trigger fields for opt plugins
    if lazy_spec.event then pack_spec.event = lazy_spec.event end
    if lazy_spec.cmd then pack_spec.cmd = lazy_spec.cmd end
    if lazy_spec.keys then pack_spec.keys = lazy_spec.keys end
    if lazy_spec.ft then pack_spec.ft = lazy_spec.ft end

    -- Store additional lazy-loading config for post-load handling
    local lazy_config = {}

    if lazy_spec.opts then lazy_config.opts = lazy_spec.opts end
    if lazy_spec.config then lazy_config.config = lazy_spec.config end
    if lazy_spec.init then lazy_config.init = lazy_spec.init end
    if lazy_spec.dependencies then lazy_config.dependencies = lazy_spec.dependencies end

    return pack_spec, lazy_config
end

-- Parse markdown and extract all plugins
function M.parse(markdown_filepath)
    local content = read_markdown(markdown_filepath)
    local code_blocks = extract_code_blocks(content)

    local plugins = {}
    local plugin_configs = {}  -- Store lazy.nvim configs (opts, keys, etc.)

    local seen = {}

    for _, block in ipairs(code_blocks) do
        local spec = load_spec(block)
        if spec then
            -- Handle array of plugins (multiple plugins in one return block)
            local specs_list = type(spec[1]) == "table" and spec or { spec }

            for _, s in ipairs(specs_list) do
                local pack_spec, lazy_config = convert_to_pack_format(s)
                if pack_spec then
                    local key = (pack_spec.name or "") .. "\0" .. pack_spec.src
                    if not seen[key] then
                        seen[key] = true
                        table.insert(plugins, pack_spec)
                        if lazy_config and (lazy_config.opts or lazy_config.config or lazy_config.keys or lazy_config.cmd or lazy_config.event or lazy_config.ft) then
                            table.insert(plugin_configs, {
                                src = pack_spec.src,
                                name = pack_spec.name,
                                config = lazy_config
                            })
                        end
                    end
                end
            end
        end
    end

    return plugins, plugin_configs
end

-- Extract main config (before ## #Plugins section)
function M.extract_main_config(markdown_filepath)
    local file = io.open(markdown_filepath, "r")
    if not file then
        error("Cannot read markdown file: " .. markdown_filepath)
    end

    local content = ""
    local in_main = true

    for line in file:lines() do
        if line:match("^## #Plugins") or line:match("^# Plugins") then
            in_main = false
            break
        end
        if in_main then
            content = content .. line .. "\n"
        end
    end

    file:close()
    return content
end

-- Extract specific lua code from main config (between ``` lua ... ``` markers)
function M.extract_main_lua_blocks(markdown_filepath)
    local content = M.extract_main_config(markdown_filepath)
    local blocks = {}
    local current_block = ""
    local in_code_block = false

    for line in content:gmatch("[^\n]+") do
        if line:match("^```lua$") then
            in_code_block = true
            current_block = ""
        elseif line:match("^```$") and in_code_block then
            in_code_block = false
            if current_block:match("%S") then
                table.insert(blocks, current_block)
            end
        elseif in_code_block then
            current_block = current_block .. line .. "\n"
        end
    end

    return blocks
end

function M.extract_main_lua_code(markdown_filepath)
    return table.concat(M.extract_main_lua_blocks(markdown_filepath), "\n")
end

local function is_executable_setup_label(line)
    return line:match("^%s*%*%*Setup:%s*executable%*%*%s*$")
        or line:match("^%s*%*%*Setup:%s*executable:%*%*%s*$")
        or line:match("^%s*<summary>Setup:%s*executable</summary>%s*$")
end

function M.extract_executable_setups(markdown_filepath)
    local content = read_markdown(markdown_filepath)
    local blocks = {}
    local current_block = ""
    local in_code_block = false
    local pending_setup = false
    local current_is_setup = false

    for line in content:gmatch("[^\n]+") do
        if is_executable_setup_label(line) then
            pending_setup = true
        end

        if line:match("^```lua$") then
            in_code_block = true
            current_block = ""
            current_is_setup = pending_setup
            pending_setup = false
        elseif line:match("^```$") and in_code_block then
            in_code_block = false
            if current_is_setup and current_block:match("%S") then
                table.insert(blocks, current_block)
            end
            current_is_setup = false
        elseif in_code_block then
            current_block = current_block .. line .. "\n"
        end
    end

    return blocks
end

return M
