local M = {}

local enabled_cache = nil
-- `false` = resolved to "no source root" (chezmoi off / unmanaged / errored);
-- `string` = the resolved path; `nil` = not yet resolved.
local source_root_cache = nil

function M.invalidate_cache()
  enabled_cache = nil
  source_root_cache = nil
end

---Parse the rvpm `config.toml` for `[options].chezmoi = true`.
---Tera templates are not expanded — literal-boolean only.
---@return boolean
function M.enabled_in_config()
  if enabled_cache ~= nil then
    return enabled_cache
  end
  local toml = require("rvpm.config").config_toml()
  local fd = io.open(toml, "r")
  if not fd then
    enabled_cache = false
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
  enabled_cache = value
  return value
end

local function normalize_slashes(p)
  return (p:gsub("\\", "/"))
end

---Resolve the chezmoi source root corresponding to rvpm's `config_root`.
---Blocking on first call (capped at 2s). Cached; invalidate via `invalidate_cache()`.
---Returns `nil` when chezmoi is disabled, not installed, or `config_root` isn't
---managed by chezmoi. A `nil` result is the signal for the autocmd to treat the
---save as "target-only" and skip chezmoi wiring entirely.
---@return string|nil
function M.source_root()
  if source_root_cache == false then
    return nil
  end
  if source_root_cache then
    return source_root_cache
  end
  if not M.enabled_in_config() or vim.fn.executable("chezmoi") ~= 1 then
    source_root_cache = false
    return nil
  end
  local cfg = require("rvpm.config")
  local ok, result = pcall(function()
    return vim.system({ "chezmoi", "source-path", cfg.config_root() }, { text = true }):wait(2000)
  end)
  if not ok or not result or result.code ~= 0 then
    source_root_cache = false
    return nil
  end
  local s = vim.trim(result.stdout or "")
  if s == "" then
    source_root_cache = false
    return nil
  end
  source_root_cache = normalize_slashes(s)
  return source_root_cache
end

---Push a user-edited target file into chezmoi source state so the next
---`chezmoi apply` won't revert it. Runs `chezmoi re-add --force` for existing
---managed files, falls back to `chezmoi add --force` for new files under the
---managed `config_root`. Guarded by `source_root()` — if `config_root` itself
---isn't chezmoi-managed we silently skip to avoid adding arbitrary files.
---@param target string Absolute target path.
---@param callback fun()
function M.sync_target_to_source(target, callback)
  if not M.enabled_in_config() or vim.fn.executable("chezmoi") ~= 1 then
    callback()
    return
  end
  if not M.source_root() then
    callback()
    return
  end
  vim.system({ "chezmoi", "re-add", "--force", target }, { text = true }, function(r1)
    if r1.code == 0 then
      vim.schedule(callback)
      return
    end
    -- re-add failed → typically because the file is new (not yet in source state).
    -- `chezmoi add --force` covers that case. The source_root() gate above means
    -- target is guaranteed to be under a managed ancestor, so add won't pull in
    -- arbitrary unrelated paths.
    vim.system({ "chezmoi", "add", "--force", target }, { text = true }, function(r2)
      vim.schedule(function()
        if r2.code ~= 0 then
          vim.notify(
            "rvpm.nvim: chezmoi sync failed for "
              .. target
              .. "\n  re-add: "
              .. (r1.stderr or "")
              .. "\n  add:    "
              .. (r2.stderr or ""),
            vim.log.levels.WARN,
            { title = "rvpm" }
          )
        end
        callback()
      end)
    end)
  end)
end

---Materialize a user-edited source file onto its target via `chezmoi apply`.
---Uses `chezmoi target-path <source>` to compute the target (handles attribute
---renames like `dot_` / `private_`). Fires only when chezmoi is enabled and
---the file is under the resolved source root.
---@param source string Absolute source path.
---@param callback fun()
function M.apply_source_to_target(source, callback)
  if not M.enabled_in_config() or vim.fn.executable("chezmoi") ~= 1 then
    callback()
    return
  end
  vim.system({ "chezmoi", "target-path", source }, { text = true }, function(r1)
    local target = nil
    if r1.code == 0 then
      target = vim.trim(r1.stdout or "")
    end
    if not target or target == "" then
      vim.schedule(callback)
      return
    end
    vim.system({ "chezmoi", "apply", "--force", target }, { text = true }, function(r2)
      vim.schedule(function()
        if r2.code ~= 0 then
          vim.notify(
            "chezmoi apply failed: " .. target .. "\n" .. (r2.stderr or ""),
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
