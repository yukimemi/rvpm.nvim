local M = {}

local cache = nil

function M.invalidate_cache()
  cache = nil
end

---Parse the rvpm `config.toml` for `[options].chezmoi = true`.
---Tera templates are not expanded — literal-boolean only.
---@return boolean
function M.enabled_in_config()
  if cache ~= nil then
    return cache
  end
  local toml = require("rvpm.config").config_toml()
  local fd = io.open(toml, "r")
  if not fd then
    cache = false
    return false
  end
  local in_options = false
  local value = false
  for line in fd:lines() do
    local header = line:match("^%s*%[%s*(.-)%s*%]")
    if header then
      in_options = (header == "options")
    elseif in_options then
      local k, v = line:match("^%s*([%w_]+)%s*=%s*([^#%s]+)")
      if k == "chezmoi" then
        value = (v == "true")
        break
      end
    end
  end
  fd:close()
  cache = value
  return value
end

---Route a user-edited target file back into chezmoi's source state, then invoke callback.
---No-ops (callback still runs) when chezmoi is disabled, not installed, or the file isn't managed.
---Matches `rvpm`'s own chezmoi contract: `.tmpl` sources are skipped with a warning.
---@param path string
---@param callback fun()
function M.readd_then(path, callback)
  if not M.enabled_in_config() or vim.fn.executable("chezmoi") ~= 1 then
    callback()
    return
  end
  vim.system({ "chezmoi", "source-path", path }, { text = true }, function(r1)
    if r1.code ~= 0 then
      vim.schedule(callback)
      return
    end
    local source = vim.trim(r1.stdout or "")
    if source:sub(-5) == ".tmpl" then
      vim.schedule(function()
        vim.notify(
          "rvpm.nvim: " .. path .. " has a .tmpl source — skipping chezmoi re-add",
          vim.log.levels.WARN,
          { title = "rvpm" }
        )
        callback()
      end)
      return
    end
    vim.system({ "chezmoi", "re-add", "--force", path }, { text = true }, function(r2)
      vim.schedule(function()
        if r2.code ~= 0 then
          vim.notify(
            "chezmoi re-add failed: " .. path .. "\n" .. (r2.stderr or ""),
            vim.log.levels.WARN,
            { title = "rvpm" }
          )
        end
        callback()
      end)
    end)
  end)
end

return M
