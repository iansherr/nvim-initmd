-- manifest_manager.lua
-- Validates cache freshness via MD5 hash comparison

local M = {}

local function simple_hash(content)
    local hash = 0
    for i = 1, #content do
        hash = (hash * 31 + string.byte(content, i)) % 0x7FFFFFFF
    end
    return string.format("%x", hash)
end

local function read_markdown_hash(markdown_filepath)
    local file = io.open(markdown_filepath, "r")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return simple_hash(content)
end

local function read_manifest_hash(cache_dir)
    local manifest_file = cache_dir .. "/manifest.txt"
    local file = io.open(manifest_file, "r")
    if not file then return nil end
    local hash = file:read("*a"):match("^%s*(%S+)")
    file:close()
    return hash
end

function M.is_cache_valid(cache_dir, markdown_filepath)
    if not (vim.fn.filereadable(cache_dir .. "/00_init.lua") == 1) then
        return false
    end

    local current_hash = read_markdown_hash(markdown_filepath)
    local cached_hash = read_manifest_hash(cache_dir)

    return current_hash == cached_hash
end

function M.invalidate_cache(cache_dir)
    os.execute("rm -rf " .. cache_dir)
end

return M
