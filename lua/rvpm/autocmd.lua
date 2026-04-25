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
--- - `"target"` — under `config_root` (run `rvpm generate` only; no chezmoi
---    push-back — re-add/add into source is too lossy for templated files)
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

-- BufWritePost handler body. Exposed for tests so we can verify the
-- classify-then-invalidate ordering without juggling autocmd plumbing.
function M._on_save(path)
  -- Defensive guard for nil/empty path. classify() already handles nil
  -- safely, but the `path:match("/config%.toml$")` call below would raise
  -- "attempt to index a nil value". The autocmd callback always feeds a
  -- non-empty string, but tests and any future direct callers shouldn't
  -- have to know about that contract.
  if not path or path == "" then
    return nil
  end

  -- Classify FIRST, while the chezmoi cache (source_root) is still valid.
  -- A source-side `config.toml` save is the canonical pitfall: the path
  -- matches `/config%.toml$` AND lives under source_root, so invalidating
  -- before classify drops the source_root cache — classify then sees
  -- source_root() = nil, falls through to nil, and the apply is silently
  -- skipped. The user's edit reaches disk on the source side but never
  -- materializes to target until they run `chezmoi apply` by hand.
  local kind = classify(path)

  -- Now refresh the chezmoi cache so the *next* save sees an updated
  -- `[options].chezmoi` flag. Saving config.toml is the only event that
  -- can flip enabled-ness; we re-prewarm asynchronously to keep the
  -- subsequent save off the UI thread.
  if path:match("/config%.toml$") then
    chezmoi.invalidate_cache()
    chezmoi.prewarm_source_root()
  end

  if not kind then
    return nil
  end

  -- verbose=true surfaces cli.run's start + success info on autocmd-
  -- triggered generates; default keeps them silent (failures always
  -- show regardless of silent when cfg.options.notify is on).
  local function do_generate()
    cli.run({ "generate" }, { silent = not cfg.options.verbose })
  end

  if kind == "target" then
    -- Target edits don't get pushed back into chezmoi source: `re-add`
    -- would overwrite the source verbatim (destroying templates, losing
    -- attribute prefixes, etc.), and chezmoi's own design treats source
    -- as the source of truth. Just regenerate — if the user also wants
    -- the edit preserved across `chezmoi apply`, they should edit the
    -- source file (or use `:Rvpm edit` / `chezmoi edit`).
    do_generate()
  else
    chezmoi.apply_source_to_target(path, do_generate)
  end

  return kind
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
      M._on_save(path)
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
