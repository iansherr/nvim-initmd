local parser = dofile("runtime/markdown_parser.lua")
local generator = dofile("runtime/cache_generator.lua")

local function with_markdown(content, run)
    local path = os.tmpname()
    local file = assert(io.open(path, "w"))
    file:write(content)
    file:close()
    local ok, err = pcall(run, path)
    os.remove(path)
    if not ok then
        error(err)
    end
end

with_markdown([[
Prose mentions `**Spec:**` inline and must not make the next fence a plugin.
```lua
return { src = "https://github.com/not-a-spec/false-positive" }
```

**Spec:**
```lua
return {
  "legacy-owner/legacy.plugin",
  opts = { enabled = true },
  config = function() end,
}
```

**Spec:**
```lua
return {
  { src = "https://example.com/nested.git" },
}
```

**Setup: executable**
```lua
vim.g.test_setup = true
```
]], function(path)
    local plugins = parser.parse(path)
    assert(#plugins == 2, "expected two labeled specs, got " .. #plugins)
    assert(plugins[1].src == "https://github.com/legacy-owner/legacy.plugin", plugins[1].src)
    assert(plugins[2].src == "https://example.com/nested.git", plugins[2].src)
    local setups = parser.extract_executable_setups(path)
    assert(#setups == 1, "expected one executable setup block")
    assert(load(setups[1]), "executable setup must compile")
end)

with_markdown([[
```lua
return {
  "legacy-owner/legacy.plugin",
  opts = { enabled = true },
  config = function() end,
}
```
]], function(path)
    local plugins, configs = parser.parse(path)
    assert(#plugins == 1, "legacy lazy format spec should convert")
    assert(plugins[1].src == "https://github.com/legacy-owner/legacy.plugin", plugins[1].src)
    assert(#configs == 1, "legacy lazy opts/config should be preserved")
    assert(configs[1].config.opts.enabled == true)
    assert(type(configs[1].config.config) == "function")
end)

local include_root = vim.fn.tempname()
assert(vim.fn.mkdir(include_root .. "/lua/plugins", "p") == 1)

local function write_file(path, content)
    local file = assert(io.open(path, "w"))
    file:write(content)
    file:close()
end

local markdown_path = include_root .. "/init.md"
write_file(include_root .. "/lua/plugins/group.lua", [[
return {
  { src = "https://example.com/included-one.git" },
  { src = "https://example.com/included-two.git" },
}
]])
write_file(markdown_path, [[
# Plugins
**Spec:**
```lua
return { { src = "https://example.com/inline-first.git" } }
```
**Spec file:** `lua/plugins/group.lua`
**Spec:**
```lua
return { { src = "https://example.com/inline-last.git" } }
```
]])

local included_plugins = parser.parse(markdown_path)
assert(#included_plugins == 4, "included files should contribute all specs")
assert(included_plugins[1].src == "https://example.com/inline-first.git")
assert(included_plugins[2].src == "https://example.com/included-one.git")
assert(included_plugins[3].src == "https://example.com/included-two.git")
assert(included_plugins[4].src == "https://example.com/inline-last.git")

local cache_dir = include_root .. "/cache"
generator.generate(cache_dir, included_plugins, {}, markdown_path, {})
local generated_file = assert(io.open(cache_dir .. "/00_init.lua", "r"))
local generated_init = generated_file:read("*a")
generated_file:close()
local compiled_init, compile_error = load(generated_init, "generated included specs")
assert(compiled_init, compile_error)
local first_position = assert(generated_init:find("inline-first", 1, true))
local included_position = assert(generated_init:find("included-one", 1, true))
local last_position = assert(generated_init:find("inline-last", 1, true))
assert(first_position < included_position and included_position < last_position,
    "generated vim.pack specs should preserve Markdown include ordering")

local function assert_parse_error(markdown, expected)
    write_file(markdown_path, markdown)
    local ok, err = pcall(parser.parse, markdown_path)
    assert(not ok, "invalid spec file directive should fail")
    assert(tostring(err):match(expected), tostring(err))
end

assert_parse_error("**Spec file:** `../outside.lua`\n", "cannot traverse")
assert_parse_error("**Spec file:** `lua/plugins/missing.lua`\n", "Cannot read spec file")
assert_parse_error("**Spec file:** lua/plugins/group.lua\n", "backticked relative path")

write_file(include_root .. "/lua/plugins/invalid.lua", "return 'not a spec table'\n")
assert_parse_error("**Spec file:** `lua/plugins/invalid.lua`\n", "must return a spec table")

local outside_file = include_root .. "-outside.lua"
write_file(outside_file, 'return { { src = "https://example.com/outside.git" } }\n')
local symlink = include_root .. "/lua/plugins/outside.lua"
local symlink_ok = (vim.uv or vim.loop).fs_symlink(outside_file, symlink)
if symlink_ok then
    assert_parse_error("**Spec file:** `lua/plugins/outside.lua`\n", "resolves outside")
end

vim.fn.delete(include_root, "rf")
os.remove(outside_file)

print("markdown parser acceptance: passed")
