--------------------------------------------------------------------------------
-- init.lua : Single-file Neovim config with Markdown scanning, debug logging,
-- and an optional Init UI.
--
-- Logs are written to: ~/.cache/nvim/plugin_manager.log
-- Detected code blocks (in TRACE mode) are saved to:
-- ~/.cache/nvim/detected_blocks.json
--------------------------------------------------------------------------------

-- RESET LOCAL CACHES
-- (for testing, you might remove your lazy cache)
-- rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim ~/.config/nvim/lazy/

--------------------------------------------------------------------------------
-- GLOBAL VARIABLES & DEBUG SETTINGS
--------------------------------------------------------------------------------
_G.LOG_LEVEL = vim.log.levels.ERROR             -- Set log level here
_G.detected_code_blocks = {}                    -- For storing detected code blocks (TRACE mode)
_G.INIT_UI = _G.INIT_UI or false                -- Set this flag to true to launch the Init UI

local pending_commands = {}                     -- Commands that failed and need re-trying

--------------------------------------------------------------------------------
-- Helper: ensure_directory_exists(path)
--------------------------------------------------------------------------------
local function ensure_directory_exists(path)
  local uv = vim.loop
  if not uv.fs_stat(path) then
    local ok, err = uv.fs_mkdir(path, 448)     -- 0700 in octal
    if not ok then
      vim.notify("Error creating directory: " .. path .. "\n" .. err, vim.log.levels.ERROR)
    end
  end
end

--------------------------------------------------------------------------------
-- Helper: log(msg, level, context)
-- Writes messages to screen (if level>=ERROR) and to ~/.cache/nvim/plugin_manager.log.
--------------------------------------------------------------------------------
local LEVEL_LABELS = {
  [vim.log.levels.TRACE] = "TRACE",
  [vim.log.levels.DEBUG] = "DEBUG",
  [vim.log.levels.INFO]  = "INFO",
  [vim.log.levels.WARN]  = "WARN",
  [vim.log.levels.ERROR] = "ERROR",
}
local function log(msg, level, context)
  level = level or vim.log.levels.INFO
  local screen_log_level = vim.log.levels.ERROR
  if context then msg = msg .. "\nContext:\n" .. vim.inspect(context) end
  if level >= screen_log_level then vim.notify(msg, level) end
  if level >= _G.LOG_LEVEL then
    local log_dir = vim.fn.stdpath("cache")
    ensure_directory_exists(log_dir)
    local logfile = log_dir .. "/plugin_manager.log"
    local label = LEVEL_LABELS[level] or ("LVL_" .. tostring(level))
    local line = string.format("[%s] %s: %s\n", os.date("%Y-%m-%d %H:%M:%S"), label, msg)
    vim.fn.writefile({ line }, logfile, "a")
  end
end

--------------------------------------------------------------------------------
-- Helper: safe_cmd(cmd)
-- Wraps vim.cmd(cmd) in a pcall. If it fails, logs the error and stores the cmd.
--------------------------------------------------------------------------------
local function safe_cmd(cmd)
  local ok, err = pcall(vim.cmd, cmd)
  if not ok then
    log("Error running command: " .. cmd .. "\nError: " .. tostring(err), vim.log.levels.WARN)
    table.insert(pending_commands, cmd)
  end
end

--------------------------------------------------------------------------------
-- Section 1: Plugin Manager Setup
--------------------------------------------------------------------------------
local function detect_plugin_manager()
  local lazy_path = vim.fn.expand("~/.local/share/nvim/lazy/lazy.nvim")
  local packer_path = vim.fn.expand("~/.local/share/nvim/site/pack/packer/start/packer.nvim")
  if vim.loop.fs_stat(lazy_path) then
    log("Detected Lazy.nvim", vim.log.levels.INFO)
    return "lazy"
  elseif vim.loop.fs_stat(packer_path) then
    log("Detected Packer.nvim", vim.log.levels.INFO)
    return "packer"
  end
  log("No plugin manager detected.", vim.log.levels.WARN)
  return nil
end

local function ensure_lazy()
  local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
  if not vim.loop.fs_stat(lazypath) then
    log("Installing Lazy.nvim at: " .. lazypath, vim.log.levels.INFO)
    os.execute("git clone --filter=blob:none https://github.com/folke/lazy.nvim.git --branch=stable " .. lazypath)
  else
    log("Lazy.nvim already installed at: " .. lazypath, vim.log.levels.INFO)
  end
  vim.opt.rtp:prepend(lazypath)
  package.path = package.path .. ";" .. lazypath .. "/lua/?.lua;" .. lazypath .. "/lua/?/init.lua"
  package.cpath = package.cpath .. ";" .. vim.fn.stdpath("data") .. "/lazy/rsync.nvim/lua/?.so"
end

ensure_lazy()
package.loaded["lazy"] = nil
local ok_lazy, lazy = pcall(require, "lazy")
if not ok_lazy then
  log("Failed to require lazy.nvim after ensure_lazy()", vim.log.levels.ERROR)
  return
end
log("Successfully required lazy.nvim.", vim.log.levels.INFO)

--------------------------------------------------------------------------------
-- Section 2: Load Markdown Config Blocks
-- Scans for fenced Lua code blocks in *.md files in your config directory.
-- This version is careful to handle both multi-line and single-line code blocks.
-- In TRACE mode, saves the detected blocks to ~/.cache/nvim/detected_blocks.json.
--------------------------------------------------------------------------------

-- Scans for fenced Lua code blocks in all *.md files in your config directory.
-- It handles both multi-line and single-line blocks.
local function load_markdown_configs()
  local config_dir = vim.fn.stdpath("config") .. "/"
  ensure_directory_exists(config_dir)
  local files = vim.fn.glob(config_dir .. "/*.md", true, true)
  if #files == 0 then
    log("No .md config found in " .. config_dir, vim.log.levels.WARN)
    return {}
  end
  local all_blocks = {}
  for _, file in ipairs(files) do
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(file))
    local parser = vim.treesitter.get_parser(buf, "markdown", {})
    local root = parser:parse()[1]:root()
    local query = vim.treesitter.query.parse("markdown", [[ (fenced_code_block) @code ]])
    for _, node, _ in query:iter_captures(root, buf, 0, -1) do
      local txt = vim.treesitter.get_node_text(node, buf)
      -- Process only Lua code blocks
      if txt and txt:match("^```lua") then
        local lines = vim.split(txt, "\n")
        local code = nil
        if #lines == 1 then
          -- Attempt to extract single-line code using a pattern.
          code = lines[1]:match("^```lua%s*(.-)%s*```$")
          -- If pattern fails, then remove the opening fence and use the rest.
          if not code then
            code = lines[1]:gsub("^```lua%s*", "")
          end
        else
          -- Remove the first line (opening fence) and the last line (closing fence) if present.
          if lines[1]:match("^```lua") then table.remove(lines, 1) end
          if lines[#lines]:match("^```") then table.remove(lines, #lines) end
          code = table.concat(lines, "\n")
        end
        code = code:gsub("^%s+", ""):gsub("%s+$", "")
        table.insert(all_blocks, code)
      end
    end
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  if _G.LOG_LEVEL <= vim.log.levels.TRACE then
    local detected_file = vim.fn.stdpath("cache") .. "/detected_blocks.json"
    vim.fn.writefile({ vim.fn.json_encode(all_blocks) }, detected_file)
    log("Saved detected code blocks to: " .. detected_file, vim.log.levels.TRACE)
    _G.detected_code_blocks = all_blocks
  end
  log("Found " .. #all_blocks .. " code blocks across .md config files.", vim.log.levels.INFO)
  return all_blocks
end



--------------------------------------------------------------------------------
-- Section 3: Hash Detection for Code Blocks
-- Stores a hash for each block in ~/.cache/nvim/md_block_hashes.json.
--------------------------------------------------------------------------------
local function update_block_hashes(blocks)
  local hash_table = {}
  for i, block in ipairs(blocks) do
    hash_table[i] = vim.fn.sha256(block)
  end
  local hash_file = vim.fn.stdpath("cache") .. "/md_block_hashes.json"
  local old_hashes = {}
  local f = io.open(hash_file, "r")
  if f then
    local content = f:read("*a")
    f:close()
    if content and content ~= "" then
      old_hashes = vim.fn.json_decode(content) or {}
    end
  end
  local changed_blocks = {}
  for i, new_hash in ipairs(hash_table) do
    if old_hashes[i] ~= new_hash then
      log("Config block " .. i .. " has changed.", vim.log.levels.INFO)
      changed_blocks[i] = true
    end
  end
  if #old_hashes > #hash_table then
    for i = #hash_table + 1, #old_hashes do
      log("Config block " .. i .. " has been removed.", vim.log.levels.INFO)
      changed_blocks[i] = true
    end
  end
  local f_out = io.open(hash_file, "w")
  if f_out then
    f_out:write(vim.fn.json_encode(hash_table))
    f_out:close()
  else
    log("Unable to write code block hashes to " .. hash_file, vim.log.levels.ERROR)
  end
  _G.changed_blocks = changed_blocks
end

--------------------------------------------------------------------------------
-- Section 4: Classify Code Blocks into Plugin Specs or Standalone Configs
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Code Block Extraction Functions
--
-- These functions load fenced Lua code blocks from markdown files, then
-- classify them as either plugin specs or standalone configuration blocks.
-- They are made as flexible and forgiving as possible by:
--   • Normalizing code (trimming whitespace, removing BOM/CR).
--   • Attempting fallback wrappers (prepending "return" and wrapping in "do ... end")
--   • Allowing blocks to be marked with a "disable" comment so they’re skipped.
--          eg: OPENBLOCKBACKTICKSlua
--              @ disable
--              <rest of the code block here>
--              CLOSEBLOCKBACKTICKS
--   • Allowing plugin spec tables to include a "manual" flag to skip auto‐cleanup.
--          eg: OPENBLOCKBACKTICKSlua
--              @ manual
--              <rest of the code block here>
--              CLOSEBLOCKBACKTICKS
--------------------------------------------------------------------------------

-- Preprocess a code block:
-- • Trims whitespace.
-- • Removes any UTF‑8 BOM or CR characters.
-- • Returns the normalized code.
local function preprocess_code(code)
  -- Remove leading/trailing whitespace, BOM and carriage returns.
  return code:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\239\187\191", ""):gsub("\r", "")
end

-- Check for a disable marker.
-- If a block starts with a line like "@ disable", we skip it.
local function is_disabled_code(code)
  return code:match("^%s*@%s*disable")
end

-- Check for a manual marker.
-- If a block starts with a line like "@ manual", we want to mark it so that its plugin
-- will not be auto‑cleaned.
local function is_manual_code(code)
  return code:match("^%s*@%s*manual")
end


-- Check for a "bare plugin spec" (a single-line plugin identifier).
-- We consider a block “bare” if it:
--  • Contains no newline (i.e. is a single line),
--  • Does not start with common Lua keywords (return, local, function),
--  • And contains a forward slash.

-- Determines if a code string is a bare plugin spec.
local function is_bare_plugin_spec(code)
  code = preprocess_code(code)
  -- Must be a single line.
  if code:find("\n") then
    return false
  end
  -- If it already starts with 'return', 'local', or 'function', it is not bare.
  if code:match("^return%s+") or code:match("^local%s+") or code:match("^function%s+") then
    return false
  end
  -- If it contains a forward slash (common in GitHub repo strings), consider it bare.
  return code:find("/") ~= nil
end

-- Safe loadstring that attempts to wrap bare plugin specs.
local function safe_load(code)
  code = preprocess_code(code)
  if is_bare_plugin_spec(code) then
    log("Auto-wrapping bare plugin spec: " .. code, vim.log.levels.DEBUG)
    -- Wrap with an extra set of curly braces to create a list of plugin spec tables.
    code = 'return { { "' .. code .. '" } }'
  end
  local fn, err = loadstring(code)
  if not fn then
    -- Try prepending "return " in case it is an expression.
    local wrapped = "return " .. code
    fn, err = loadstring(wrapped)
    if fn then
      log("Pre-wrapped code block with 'return' as fallback.", vim.log.levels.DEBUG)
    end
  end
  if not fn then
    -- As a final fallback, wrap the code in a do ... end block.
    local wrapped = "do " .. code .. " end"
    fn, err = loadstring(wrapped)
    if fn then
      log("Wrapped code block in 'do ... end' as an extra fallback.", vim.log.levels.DEBUG)
    end
  end
  return fn, err
end


-- Check if a block appears to be a plugin spec by matching common patterns.
local function is_plugin_spec_code(code)
  -- The common patterns are:
  --   local M = { ... }   or   return { ... }
  return code:match("^return%s*{") or code:match("^local%s+M%s*=%s*{")
  -- Optionally, one might allow markers like "-- @plugin" here.
end

-- Check for an external configuration function (old style).
local function is_external_config_code(code)
  return code:match("^local%s+function%s+config")
end

--   Given a list of Lua code blocks (from Markdown), it returns two lists:
--   • plugin_specs: Blocks that are plugin specification tables.
--   • standalone_configs: Blocks that are standalone configuration functions or code.
--
--   The function is forgiving:
--     - It skips blocks marked with "@ disable".
--     - It auto-wraps bare plugin specs.
--     - If a block is marked with "@ manual", it sets a `manual` flag so that
--       cleanup does not remove that plugin.
local function extract_plugins_and_configs(lua_code_blocks)
  local plugin_specs = {}
  local standalone_configs = {}

  for i, code in ipairs(lua_code_blocks) do
    code = preprocess_code(code)
    if is_disabled_code(code) then
      log("Skipping disabled code block #" .. i, vim.log.levels.INFO)
    -- First, check for a bare plugin spec.
    elseif is_bare_plugin_spec(code) then
      -- Auto-wrap the bare plugin spec.
      local wrapped_code = 'return { "' .. code .. '" }'
      local fn, err_compile = safe_load(wrapped_code)
      if not fn then
        log("Error compiling bare plugin spec block #" .. i, vim.log.levels.ERROR, { error = err_compile, code = wrapped_code })
      else
        local ok, result = pcall(fn)
        if ok and type(result) == "table" then
          if is_manual_code(code) then result.manual = true end
          table.insert(plugin_specs, result)
          log("Bare plugin spec added from block #" .. i, vim.log.levels.INFO, { result = result })
        else
          log("Error running bare plugin spec block #" .. i, vim.log.levels.ERROR, { error = result, code = wrapped_code })
        end
      end
    elseif is_plugin_spec_code(code) then
      local fn, err_compile = safe_load(code)
      if not fn then
        log("Error compiling plugin spec block #" .. i, vim.log.levels.ERROR, { error = err_compile, code = code })
      else
        local ok, result = pcall(fn)
        if ok and type(result) == "table" then
          if vim.tbl_islist(result) then
            for _, item in ipairs(result) do
              if type(item) == "table" and ((item[1] and type(item[1]) == "string" and item[1] ~= "") or item.dir or item.import or item.config) then
                if is_manual_code(code) then item.manual = true end
                table.insert(plugin_specs, item)
                log("Plugin spec added from nested item in block #" .. i, vim.log.levels.INFO, { result = item })
              else
                table.insert(standalone_configs, item)
                log("Nested item in block #" .. i .. " treated as standalone config", vim.log.levels.DEBUG, { item = item })
              end
            end
          elseif result[1] and type(result[1]) == "string" and result[1] ~= "" then
            if is_manual_code(code) then result.manual = true end
            table.insert(plugin_specs, result)
            log("Plugin spec added from block #" .. i, vim.log.levels.INFO, { result = result })
          elseif result.dir or result.import or result.config then
            if is_manual_code(code) then result.manual = true end
            table.insert(plugin_specs, result)
            log("Plugin spec added from block #" .. i, vim.log.levels.INFO, { result = result })
          elseif type(result.setup) == "function" then
            table.insert(standalone_configs, function() result.setup() end)
            log("Extracted config function from block #" .. i, vim.log.levels.INFO)
          else
            log("Skipping unrecognized plugin spec block #" .. i, vim.log.levels.WARN, { result = result })
            table.insert(standalone_configs, result)
          end
        else
          log("Error running plugin spec block #" .. i, vim.log.levels.ERROR, { error = result, code = code })
        end
      end
    elseif is_external_config_code(code) then
      local fn, err_compile = safe_load(code)
      if not fn then
        log("Error compiling external config block #" .. i, vim.log.levels.ERROR, { error = err_compile, code = code })
      else
        local ok, config_fn = pcall(fn)
        if ok and type(config_fn) == "function" then
          table.insert(standalone_configs, config_fn)
          log("External config function added from block #" .. i, vim.log.levels.INFO)
        else
          log("Error processing external config block #" .. i, vim.log.levels.ERROR, { error = config_fn, code = code })
        end
      end
    else
      -- Fallback: treat the block as a standalone config block.
      table.insert(standalone_configs, code)
      log("Standalone config added from block #" .. i, vim.log.levels.DEBUG, { code = code })
    end
  end

  log("Extracted " .. #plugin_specs .. " plugin specs and " .. #standalone_configs .. " config blocks.", vim.log.levels.INFO)
  return plugin_specs, standalone_configs
end




--------------------------------------------------------------------------------
-- Section 5: Setup Plugins and Cleanup
-- Here we build a desired set from the scanned plugin specs and remove installed plugins not in that set.
--------------------------------------------------------------------------------
-- Cleanup plugins that are installed but not in our desired set.
local function cleanup_plugins(plugin_specs)
  local ok_conf, lazy_conf = pcall(require, "lazy.core.config")
  if not ok_conf or type(lazy_conf.plugins) ~= "table" then
    log("Could not load lazy.core.config – skipping plugin cleaning", vim.log.levels.WARN)
    return
  end

  local desired_set = {}
  for _, s in ipairs(plugin_specs) do
    if s.manual then
      log("Skipping cleanup for manual plugin spec: " .. (s[1] or s.dir or s.import or "unknown"), vim.log.levels.INFO)
    elseif type(s[1]) == "string" then
      desired_set[s[1]] = true
    elseif type(s.import) == "string" then
      desired_set["(import) " .. s.import] = true
    elseif type(s.dir) == "string" then
      desired_set["(dir) " .. s.dir] = true
    end
  end

  log("Desired plugin set: " .. vim.inspect(desired_set), vim.log.levels.DEBUG)
  log("Installed plugins: " .. vim.inspect(lazy_conf.plugins), vim.log.levels.DEBUG)

  if next(desired_set) == nil then
    log("Desired plugin set is empty; skipping cleanup", vim.log.levels.INFO)
    return
  end

  if vim.fn.exists(":Lazy") == 0 then
    log("Lazy command not available; skipping cleanup", vim.log.levels.INFO)
    return
  end

  for name, _ in pairs(lazy_conf.plugins) do
    if not desired_set[name] then
      safe_cmd("Lazy clean " .. name)
      log("Removed unused plugin: " .. name, vim.log.levels.INFO)
    end
  end
end


-- Setup plugins using the detected package manager.
local function setup_plugins(plugin_specs)
  local detected_manager = detect_plugin_manager() or "lazy"
  if detected_manager == "lazy" then
    require("lazy").setup(plugin_specs, {
      defaults = { lazy = false, version = false },
      performance = { cache = { enabled = true } },
    })
    -- Wait for lazy.nvim to signal setup completion before cleaning.
    vim.api.nvim_create_autocmd("User", {
      pattern = "LazyDone",
      once = true,
      callback = function()
        cleanup_plugins(plugin_specs)
      end,
    })
  elseif detected_manager == "packer" then
    local packer = require("packer")
    packer.startup(function(use)
      for _, plugin in ipairs(plugin_specs) do
        use(plugin)
      end
    end)
  else
    vim.notify("No plugin manager detected. Please install Lazy.nvim or Packer.nvim.", vim.log.levels.WARN)
  end
end


--------------------------------------------------------------------------------
-- Section 6: Execute Config Blocks
--------------------------------------------------------------------------------
local function apply_extra_settings()
    for key, value in pairs(_G) do
        if key:match("^extra_") then
            log("Applying extra setting: " .. key, vim.log.levels.INFO, value)
            if key == "extra_mappings" then
                for mode, mappings in pairs(value) do
                    for lhs, rhs in pairs(mappings) do
                        vim.keymap.set(mode, lhs, rhs[1], { desc = rhs[2] })
                    end
                end
            elseif key == "extra_colorscheme_integrations" then
                vim.g.colorscheme_integrations = value
            else
                vim.g[key] = value
            end
        end
    end
    log("All extra settings applied.", vim.log.levels.INFO)
end

local function execute_configs(standalone_configs)
  for i, config in ipairs(standalone_configs) do
    if type(config) == "function" then
      log("Executing extracted config function #" .. i, vim.log.levels.DEBUG)
      local ok, runtime_err = pcall(config)
      if not ok then
        log("Error executing config function #" .. i, vim.log.levels.ERROR, { error = runtime_err })
      else
        log("Executed config function #" .. i, vim.log.levels.DEBUG)
      end
    elseif type(config) == "string" then
      log("Executing config block #" .. i, vim.log.levels.DEBUG, config)
      local fn, err = loadstring(config)
      if fn then
        local ok, runtime_err = pcall(fn)
        if not ok then
          log("Error executing config block #" .. i, vim.log.levels.ERROR, { code = config, error = runtime_err })
        else
          log("Executed config block #" .. i, vim.log.levels.DEBUG)
        end
      else
        log("Error compiling config block #" .. i, vim.log.levels.ERROR, { code = config, error = err })
      end
    elseif type(config) == "table" then
      if type(config.setup) == "function" then
        log("Executing config setup from table in block #" .. i, vim.log.levels.DEBUG)
        local ok, runtime_err = pcall(config.setup)
        if not ok then
          log("Error executing config setup from table in block #" .. i, vim.log.levels.ERROR, { error = runtime_err })
        else
          log("Executed config setup from table in block #" .. i, vim.log.levels.DEBUG)
        end
      else
        log("Skipping config block #" .. i .. " (table with no setup function)", vim.log.levels.WARN, { config = config })
      end
    else
      log("Skipping config block #" .. i .. " (unexpected type: " .. type(config) .. ")", vim.log.levels.WARN)
    end
  end

  apply_extra_settings()
  log("Standalone configurations executed.", vim.log.levels.INFO)
end


--------------------------------------------------------------------------------
-- Section 7: Main Execution
--------------------------------------------------------------------------------
log("=== Starting Single-file Neovim config ===", vim.log.levels.INFO)

local blocks = load_markdown_configs()
update_block_hashes(blocks)
local plugin_specs, standalone_configs = extract_plugins_and_configs(blocks)
log("Scanned " .. #plugin_specs .. " plugin specs and " .. #standalone_configs .. " config blocks.", vim.log.levels.INFO)

setup_plugins(plugin_specs)
execute_configs(standalone_configs)
log("=== Done loading config ===", vim.log.levels.INFO)

--------------------------------------------------------------------------------
-- Re-run any pending commands that previously errored.
--------------------------------------------------------------------------------
if #pending_commands > 0 then
  log("Re-running pending commands...", vim.log.levels.INFO)
  vim.defer_fn(function()
    for _, cmd in ipairs(pending_commands) do
      safe_cmd(cmd)
    end
    pending_commands = {}
  end, 200)
end
