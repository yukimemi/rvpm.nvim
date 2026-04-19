local M = {}

local cfg = require("rvpm.config")
local cli = require("rvpm.cli")
local chezmoi = require("rvpm.chezmoi")

local function normalize(path)
  return (path:gsub("\\", "/"))
end

local function relative_under(path, root)
  if not path or path == "" or not root or root == "" then
    return nil
  end
  path = normalize(path)
  root = normalize(root)
  if path:sub(1, #root + 1) ~= root .. "/" then
    return nil
  end
  return path:sub(#root + 2)
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
