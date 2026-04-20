local M = {}

local cfg = require("rvpm.config")
local cli = require("rvpm.cli")
local chezmoi = require("rvpm.chezmoi")

local IS_WINDOWS = vim.fn.has("win32") == 1

local function normalize(path)
  return (path:gsub("\\", "/"))
end

-- Compare path prefixes case-insensitively on Windows. The filesystem is
-- case-insensitive there but `vim.env.USERPROFILE` often reports `C:\Users`
-- while `ev.file` can come back with `c:\users` depending on how the
-- buffer was opened — strict string match would silently never classify
-- the save. Keep the original (normalized) path for the relative-slice
-- return so downstream chezmoi calls see the real casing.
local function fold_case(s)
  if IS_WINDOWS then
    return s:lower()
  end
  return s
end

local function relative_under(path, root)
  if not path or path == "" or not root or root == "" then
    return nil
  end
  local norm_path = normalize(path)
  local norm_root = normalize(root)
  local cmp_path = fold_case(norm_path)
  local cmp_root = fold_case(norm_root)
  if cmp_path:sub(1, #cmp_root + 1) ~= cmp_root .. "/" then
    return nil
  end
  return norm_path:sub(#norm_root + 2)
end

-- True when `rel` (relative to either config_root or its chezmoi source) names
-- a file rvpm cares about.
local function is_rvpm_file(rel)
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

---Classify a saved path:
--- - `"target"` — under `config_root` (needs push to source when chezmoi on)
--- - `"source"` — under the resolved chezmoi source root (needs apply to target)
--- - `nil` — unrelated
---@param path string Absolute path of the saved file.
---@return "target"|"source"|nil
local function classify(path)
  if not path or path == "" then
    return nil
  end

  local rel = relative_under(path, cfg.config_root())
  if rel and is_rvpm_file(rel) then
    return "target"
  end

  local source_root = chezmoi.source_root()
  if source_root then
    rel = relative_under(path, source_root)
    if rel and is_rvpm_file(rel) then
      return "source"
    end
  end

  return nil
end

function M.register()
  local group = vim.api.nvim_create_augroup("rvpm_auto_generate", { clear = true })

  -- Warm the chezmoi source-root cache asynchronously at setup time so the
  -- first save doesn't pay a `chezmoi source-path` round-trip on the UI
  -- thread. Cheap when chezmoi is off (one file read, no subprocess spawn).
  chezmoi.prewarm_source_root()

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(ev)
      local path = normalize(vim.fn.fnamemodify(ev.file, ":p"))

      -- config.toml save may flip the chezmoi flag. Drop caches and re-prewarm
      -- so subsequent saves see the new state. The *current* save still uses
      -- the pre-flip caches for classification, which is fine — either the
      -- path is under config_root (target case, doesn't need source_root) or
      -- it's outside (unrelated).
      if path:match("/config%.toml$") then
        chezmoi.invalidate_cache()
        chezmoi.prewarm_source_root()
      end

      local kind = classify(path)
      if not kind then
        return
      end

      local function do_generate()
        cli.run({ "generate" }, { silent = true })
      end

      if kind == "target" then
        chezmoi.sync_target_to_source(path, do_generate)
      else
        chezmoi.apply_source_to_target(path, do_generate)
      end
    end,
  })
end

-- Exposed for tests.
M._classify = classify
M._is_rvpm_file = is_rvpm_file
-- Back-compat shim for earlier smoke tests.
function M._should_generate(path)
  return classify(path) ~= nil
end

return M
