--------------------------------------------------------------------------------
-- init.lua : Single-file Neovim config from a Markdown file.
--
-- This script assumes your Markdown file(s) contain valid Lua code in each
-- ```lua ... ``` block. Blocks under "# Plugins" are assumed to be plugin
-- specifications (i.e. they return a table or a list of tables as in a normal Lua
-- plugin file). All blocks are cached as separate Lua files and then loaded via
-- Lua’s module system.
--
-- Plugins returned in these plugin blocks (including any dependencies specified)
-- are passed to lazy.nvim, which handles dependency installation automatically.
--
-- Your Markdown file (for example, init.md) should be organized like this:
--
-- # Plugins
--
-- ```lua
-- return { "folke/which-key.nvim", config = function() require("which-key").setup {} end }
-- ```
--
-- # Main
--
-- ```lua
-- vim.opt.number = true
-- vim.cmd("colorscheme nightfly")
-- ```
--
-- Logs are written to ~/.cache/nvim/plugin_manager.log.
--------------------------------------------------------------------------------

local vim = vim
_G.LOG_LEVEL = vim.log.levels.INFO
-- If _G.config_markdown_file is nonempty, that file will be used; otherwise, all *.md files are scanned.
_G.config_markdown_file = ""

--------------------------------------------------
-- Helpers
--------------------------------------------------

local function ensure_directory_exists(path)
  local uv = vim.loop
  local sep = package.config:sub(1,1)
  local segments = {}
  for segment in string.gmatch(path, "[^" .. sep .. "]+") do
    table.insert(segments, segment)
  end
  local current = (sep == "/" and "/" or "")
  for _, part in ipairs(segments) do
    current = current .. part .. sep
    if not uv.fs_stat(current) then
      local ok, err = uv.fs_mkdir(current, 448) -- 0700 permissions
      if not ok then
        vim.notify("Failed to create dir: " .. current .. "\n" .. err, vim.log.levels.ERROR)
        return false
      end
    end
  end
  return true
end

local function log(msg, level)
  level = level or vim.log.levels.INFO
  if level >= (_G.LOG_LEVEL or vim.log.levels.INFO) then
    local log_dir = vim.fn.stdpath("cache")
    ensure_directory_exists(log_dir)
    local logfile = log_dir .. "/plugin_manager.log"
    local labels = {
      [vim.log.levels.DEBUG] = "DEBUG",
      [vim.log.levels.INFO]  = "INFO",
      [vim.log.levels.ERROR] = "ERROR",
    }
    local label = labels[level] or ("LVL_" .. tostring(level))
    local line = string.format("[%s] %s: %s\n", os.date("%Y-%m-%d %H:%M:%S"), label, msg)
    vim.fn.writefile({ line }, logfile, "a")
    vim.notify(msg, level)
  end
end

--------------------------------------------------
-- Markdown Extraction & Caching
--------------------------------------------------

local function read_markdown_files()
  local config_dir = vim.fn.stdpath("config") .. "/"
  ensure_directory_exists(config_dir)
  local md_files = {}
  if _G.config_markdown_file and #_G.config_markdown_file > 0 then
    md_files = { config_dir .. _G.config_markdown_file }
  else
    md_files = vim.fn.glob(config_dir .. "*.md", true, true)
  end
  if #md_files == 0 then error("No markdown config files found in " .. config_dir) end
  local combined_lines = {}
  for _, file in ipairs(md_files) do
    local lines = vim.fn.readfile(file)
    if lines then
      for _, line in ipairs(lines) do
        table.insert(combined_lines, line)
      end
    end
  end
  if #combined_lines == 0 then error("Markdown config files are empty.") end
  return combined_lines, md_files
end

-- Extract code blocks, splitting by section header.
local function extract_lua_blocks(lines)
  local main_blocks = {}
  local plugin_blocks = {}
  local current_section = "main"  -- default bucket
  local inside = false
  local current_block = {}

  for _, line in ipairs(lines) do
    if line:match("^%s*#%s*Main%s*$") then
      current_section = "main"
    elseif line:match("^%s*#%s*Plugins%s*$") then
      current_section = "plugins"
    elseif line:match("^```lua") then
      inside = true
      current_block = {}
    elseif line:match("^```") and inside then
      inside = false
      local block = table.concat(current_block, "\n")
      if current_section == "plugins" then
        table.insert(plugin_blocks, block)
      else
        table.insert(main_blocks, block)
      end
    elseif inside then
      table.insert(current_block, line)
    end
  end

  return main_blocks, plugin_blocks
end

-- Write each Lua block to a separate file.
local function cache_lua_blocks(main_blocks, plugin_blocks)
  local cache_dir = vim.fn.stdpath("cache") .. "/mdcache/"
  ensure_directory_exists(cache_dir)
  for i, block in ipairs(main_blocks) do
    local filename = cache_dir .. "main_block_" .. i .. ".lua"
    vim.fn.writefile(vim.split(block, "\n"), filename)
  end
  for i, block in ipairs(plugin_blocks) do
    local filename = cache_dir .. "plugin_block_" .. i .. ".lua"
    vim.fn.writefile(vim.split(block, "\n"), filename)
  end
  return cache_dir, #main_blocks, #plugin_blocks
end

--------------------------------------------------
-- Build Plugin Specs from Cached Plugin Blocks
--------------------------------------------------
-- We iterate over the cached plugin files and require() them,
-- collecting their return values into one list. Lazy.nvim will then
-- automatically handle dependencies if your plugin spec tables include them.
local function build_plugin_specs(plugin_count, cache_dir)
  local plugin_specs = {}
  package.path = package.path .. ";" .. cache_dir .. "?.lua"
  for i = 1, plugin_count do
    local module_name = "plugin_block_" .. i
    local ok, result = pcall(require, module_name)
    if ok and type(result) == "table" then
      -- If the result is a single plugin spec (i.e. table with a repo string as first element)
      if type(result[1]) == "string" and result[1]:find("/") then
        table.insert(plugin_specs, result)
      else
        -- If result is a list of plugin specs, iterate over them.
        for _, spec in ipairs(result) do
          if type(spec) == "table" and spec[1] and type(spec[1]) == "string" and spec[1]:find("/") then
            table.insert(plugin_specs, spec)
          end
        end
      end
    else
      local file_path = cache_dir .. module_name .. ".lua"
      local code = vim.fn.readfile(file_path)
      log("Plugin block module " .. module_name .. " did not return a valid plugin spec.\nCode:\n" .. table.concat(code, "\n"), vim.log.levels.ERROR)
    end
  end
  return plugin_specs
end

--------------------------------------------------
-- Lazy.nvim Setup
--------------------------------------------------

local function ensure_lazy_nvim()
  log("Ensuring lazy.nvim is installed...", vim.log.levels.DEBUG)
  local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
  if not vim.loop.fs_stat(lazypath) then
    os.execute("git clone --filter=blob:none https://github.com/folke/lazy.nvim.git --branch=stable " .. lazypath)
  end
  vim.opt.rtp:prepend(lazypath)
end

local function setup_lazy_nvim(plugin_specs)
  ensure_lazy_nvim()
  package.loaded["lazy"] = nil
  local ok_lazy, lazy = pcall(require, "lazy")
  if not ok_lazy then error("lazy.nvim not found!") end
  lazy.setup(plugin_specs, {
    defaults = { lazy = false, version = false },
    performance = { cache = { enabled = true } },
  })
end

--------------------------------------------------
-- Load Cached Main Blocks
--------------------------------------------------
local function load_main_blocks(main_count, cache_dir)
  package.path = package.path .. ";" .. cache_dir .. "?.lua"
  for i = 1, main_count do
    local module_name = "main_block_" .. i
    local ok, result = pcall(require, module_name)
    if not ok then
      log("Error requiring main module " .. module_name .. ": " .. result, vim.log.levels.ERROR)
    else
      log("Successfully loaded main module " .. module_name, vim.log.levels.DEBUG)
    end
  end
end

--------------------------------------------------
-- Order of Operations: Main Function
--------------------------------------------------
local function main()
  -- 1. Read markdown file(s) and combine lines.
  local combined_lines, md_files = read_markdown_files()
  log("Found markdown file(s): " .. table.concat(md_files, ", "), vim.log.levels.DEBUG)

  -- 2. Extract Lua blocks into two buckets: Main and Plugins.
  local main_blocks, plugin_blocks = extract_lua_blocks(combined_lines)
  log("Extracted " .. #main_blocks .. " Main blocks and " .. #plugin_blocks .. " Plugin blocks.", vim.log.levels.DEBUG)

  -- 3. Cache the blocks into separate Lua files.
  local cache_dir, main_count, plugin_count = cache_lua_blocks(main_blocks, plugin_blocks)

  -- 4. Build plugin specs from the cached Plugin blocks.
  local plugin_specs = build_plugin_specs(plugin_count, cache_dir)

  -- 5. Set up lazy.nvim with the plugin specs.
  setup_lazy_nvim(plugin_specs)

  -- 6. Load the Main blocks. (They run after plugins load.)
  load_main_blocks(main_count, cache_dir)

  log("=== Config loading complete ===", vim.log.levels.DEBUG)
end

--------------------------------------------------
-- Run Main
--------------------------------------------------
main()
