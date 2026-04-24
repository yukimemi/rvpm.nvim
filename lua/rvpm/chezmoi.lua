local M = {}

-- Gate vim.notify calls on the user-facing `notify` option so `notify=false`
-- truly silences every message — matching cli.lua / terminal.lua. Chezmoi ops
-- only surface on failure (success is silent; autocmd fires on every :w and
-- success-per-save would be spam), but even failures must be suppressible.
local function notify_if_enabled(msg, level)
  if require("rvpm.config").options.notify then
    vim.notify(msg, level, { title = "rvpm" })
  end
end

-- Verbose-only notifier: fires only when the user opted into success / info
-- messages via `setup({ verbose = true })`. Gated on both `notify` and
-- `verbose` so disabling either silences these entirely. Used for the
-- "did it actually apply?" debugging hints on chezmoi successes.
local function notify_if_verbose(msg, level)
  local opts = require("rvpm.config").options
  if opts.notify and opts.verbose then
    vim.notify(msg, level or vim.log.levels.INFO, { title = "rvpm" })
  end
end

local enabled_cache = nil
-- `false` = resolved to "no source root" (chezmoi off / unmanaged / errored);
-- `string` = the resolved path; `nil` = not yet resolved.
local source_root_cache = nil
-- Guard so concurrent invalidate+prewarm cycles don't spawn overlapping
-- `chezmoi source-path` processes. Cleared from inside the async callback.
local source_root_in_flight = false

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

local IS_WINDOWS = vim.fn.has("win32") == 1

local function normalize_slashes(p)
  return (p:gsub("\\", "/"))
end

-- chezmoi CLI on Windows expects native backslash-separated paths. Our
-- internal comparisons work in forward slashes, but every path we hand
-- to a `chezmoi` subprocess needs to be converted back.
local function to_os_path(p)
  if IS_WINDOWS then
    return (p:gsub("/", "\\"))
  end
  return p
end

---Kick off an async `chezmoi source-path <config_root>` to populate the
---source-root cache. Returns immediately — no UI-thread work beyond the
---spawn of a subprocess (and only when chezmoi is actually enabled and
---installed). Subsequent calls are no-ops while a resolution is in flight
---or once a result is cached; pair with `invalidate_cache()` to refresh
---after a config.toml flip.
function M.prewarm_source_root()
  if source_root_cache ~= nil or source_root_in_flight then
    return
  end
  if not M.enabled_in_config() or vim.fn.executable("chezmoi") ~= 1 then
    source_root_cache = false
    return
  end
  source_root_in_flight = true
  local cfg = require("rvpm.config")
  vim.system(
    { "chezmoi", "source-path", to_os_path(cfg.config_root()) },
    { text = true },
    function(result)
      vim.schedule(function()
        source_root_in_flight = false
        if not result or result.code ~= 0 then
          source_root_cache = false
          return
        end
        local s = vim.trim(result.stdout or "")
        if s == "" then
          source_root_cache = false
          return
        end
        source_root_cache = normalize_slashes(s)
      end)
    end
  )
end

---Read the cached chezmoi source root. Non-blocking; returns `nil` when
---chezmoi is disabled, not installed, `config_root` isn't managed, or the
---async prewarm hasn't completed yet. The autocmd treats `nil` as the
---"source-side detection is off" signal, so a cold cache just skips the
---source path for the very first save and works normally on the next.
---@return string|nil
function M.source_root()
  if source_root_cache == false or source_root_cache == nil then
    return nil
  end
  return source_root_cache
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
  vim.system({ "chezmoi", "target-path", to_os_path(source) }, { text = true }, function(r1)
    local target = nil
    if r1.code == 0 then
      target = vim.trim(r1.stdout or "")
    end
    if not target or target == "" then
      vim.schedule(callback)
      return
    end
    -- target as returned by chezmoi is already OS-native on Windows; pass
    -- straight through.
    vim.system({ "chezmoi", "apply", "--force", target }, { text = true }, function(r2)
      vim.schedule(function()
        if r2.code == 0 then
          notify_if_verbose("chezmoi apply: " .. target)
        else
          notify_if_enabled(
            "chezmoi apply failed: " .. target .. "\n" .. (r2.stderr or ""),
            vim.log.levels.WARN
          )
        end
        callback()
      end)
    end)
  end)
end

return M
