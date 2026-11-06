local parser = dofile("runtime/markdown_parser.lua")

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

print("markdown parser acceptance: passed")
