local M = {}

local cfg = require("rvpm.config")
local cli = require("rvpm.cli")

local function normalize(path)
  return (path:gsub("\\", "/"))
end

-- Returns true when `path` is a file under config_root whose change should
-- trigger `rvpm generate` (config.toml or any of the Lua hook files).
local function should_generate(path)
  if path == "" then
    return false
  end
  path = normalize(path)
  local root = normalize(cfg.config_root())

  if path:sub(1, #root + 1) ~= root .. "/" then
    return false
  end
  local rel = path:sub(#root + 2)

  if rel == "config.toml" then
    return true
  end
  if rel == "before.lua" or rel == "after.lua" then
    return true
  end
  if rel:match("^plugins/[^/]+/[^/]+/[^/]+/init%.lua$") then
    return true
  end
  if rel:match("^plugins/[^/]+/[^/]+/[^/]+/before%.lua$") then
    return true
  end
  if rel:match("^plugins/[^/]+/[^/]+/[^/]+/after%.lua$") then
    return true
  end
  return false
end

local function relative_to_config_root(path)
  local root = normalize(cfg.config_root())
  path = normalize(path)
  if path:sub(1, #root + 1) ~= root .. "/" then
    return nil
  end
  return path:sub(#root + 2)
end

function M.register()
  local group = vim.api.nvim_create_augroup("rvpm_auto_generate", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(ev)
      local path = vim.fn.fnamemodify(ev.file, ":p")
      local rel = relative_to_config_root(path)
      -- Saving config.toml may flip `[options].chezmoi`; drop the cache.
      if rel == "config.toml" then
        require("rvpm.chezmoi").invalidate_cache()
      end
      if should_generate(path) then
        require("rvpm.chezmoi").readd_then(path, function()
          cli.run({ "generate" }, { silent = true })
        end)
      end
    end,
  })
end

M._should_generate = should_generate

return M
