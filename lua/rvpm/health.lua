local M = {}

local cfg = require("rvpm.config")

local function health()
  return vim.health or require("health")
end

function M.check()
  local h = health()
  h.start("rvpm.nvim")

  local bin = cfg.options.cmd
  if vim.fn.executable(bin) == 1 then
    h.ok("rvpm binary found: " .. vim.fn.exepath(bin))
  else
    h.error("rvpm not found in PATH (looked for: " .. bin .. ")")
    return
  end

  local root = cfg.config_root()
  if vim.fn.isdirectory(root) == 1 then
    h.ok("config_root: " .. root)
  else
    h.warn("config_root missing: " .. root .. " — run `rvpm init --write`")
  end

  local tomlpath = cfg.config_toml()
  if vim.fn.filereadable(tomlpath) == 1 then
    h.ok("config.toml: " .. tomlpath)
  else
    h.warn("config.toml missing: " .. tomlpath)
  end

  -- chezmoi integration status
  local chezmoi = require("rvpm.chezmoi")
  chezmoi.invalidate_cache()
  local chezmoi_on = chezmoi.enabled_in_config()
  local chezmoi_bin = vim.fn.executable("chezmoi") == 1
  if chezmoi_on and chezmoi_bin then
    h.ok("chezmoi integration: active (options.chezmoi = true, chezmoi on PATH)")
  elseif chezmoi_on and not chezmoi_bin then
    h.warn("options.chezmoi = true but `chezmoi` is not on PATH — writes will bypass chezmoi")
  else
    h.info("chezmoi integration: disabled (set options.chezmoi = true in config.toml to enable)")
  end

  local result = vim.system({ bin, "doctor" }, { text = true }):wait(10000)
  if result.code == 0 then
    h.ok("rvpm doctor: OK")
  elseif result.code == 2 then
    h.warn("rvpm doctor: warnings")
  else
    h.error("rvpm doctor: errors (exit " .. tostring(result.code) .. ")")
  end
  for _, line in ipairs(vim.split(result.stdout or "", "\n", { plain = true })) do
    if line ~= "" then
      h.info("  " .. line)
    end
  end
end

return M
