local autocmd = require("rvpm.autocmd")
local cfg = require("rvpm.config")
local chezmoi = require("rvpm.chezmoi")

-- Detect Windows once; on-disk behaviour (case folding, drive letters) only
-- applies there.
local IS_WINDOWS = vim.fn.has("win32") == 1
local ROOT = IS_WINDOWS and "C:/Users/test/.config/rvpm/nvim" or "/home/test/.config/rvpm/nvim"

local saved_options_config_root
local saved_config_toml

local function setup_root(root)
  saved_options_config_root = cfg.options.config_root
  saved_config_toml = cfg.config_toml
  cfg.options.config_root = root
  cfg.config_toml = function()
    return root .. "/config.toml"
  end
  chezmoi.invalidate_cache()
end

local function restore_root()
  cfg.options.config_root = saved_options_config_root
  cfg.config_toml = saved_config_toml
  chezmoi.invalidate_cache()
end

describe("rvpm.autocmd._classify", function()
  before_each(function()
    setup_root(ROOT)
  end)

  after_each(function()
    restore_root()
  end)

  it("classifies config.toml under config_root as target", function()
    assert.equals("target", autocmd._classify(ROOT .. "/config.toml"))
  end)

  it("classifies global hooks as target", function()
    assert.equals("target", autocmd._classify(ROOT .. "/before.lua"))
    assert.equals("target", autocmd._classify(ROOT .. "/after.lua"))
  end)

  it("classifies per-plugin hooks as target", function()
    local base = ROOT .. "/plugins/github.com/folke/snacks.nvim"
    assert.equals("target", autocmd._classify(base .. "/init.lua"))
    assert.equals("target", autocmd._classify(base .. "/before.lua"))
    assert.equals("target", autocmd._classify(base .. "/after.lua"))
  end)

  it("returns nil for non-rvpm files under config_root", function()
    assert.is_nil(autocmd._classify(ROOT .. "/README.md"))
    assert.is_nil(autocmd._classify(ROOT .. "/rvpm.lock"))
  end)

  it("returns nil for per-plugin paths that do not name a hook", function()
    local base = ROOT .. "/plugins/github.com/folke/snacks.nvim"
    assert.is_nil(autocmd._classify(base .. "/README.md"))
  end)

  it("returns nil for paths outside config_root", function()
    local other = IS_WINDOWS and "C:/Users/test/project/src/main.rs" or "/home/test/project/src/main.rs"
    assert.is_nil(autocmd._classify(other))
  end)

  it("returns nil for a near-miss prefix", function()
    -- `.config/rvpm/nvim-test/` must not match `.config/rvpm/nvim/` config_root.
    local sibling = ROOT:gsub("/nvim$", "/nvim-test") .. "/config.toml"
    assert.is_nil(autocmd._classify(sibling))
  end)

  it("returns nil for an empty path", function()
    assert.is_nil(autocmd._classify(""))
  end)

  if IS_WINDOWS then
    -- Windows-only: native backslashes and case-folded prefix should still
    -- classify. The target path delivered by BufWritePost can come in any
    -- of these shapes depending on how the buffer was opened.
    it("accepts native backslash paths on Windows", function()
      local p = (ROOT .. "/config.toml"):gsub("/", "\\")
      assert.equals("target", autocmd._classify(p))
    end)

    it("folds case for the prefix match on Windows", function()
      local p = (ROOT .. "/config.toml"):lower()
      assert.equals("target", autocmd._classify(p))
    end)
  end
end)

describe("rvpm.autocmd._is_rvpm_file", function()
  it("accepts root-level config and hooks", function()
    assert.is_true(autocmd._is_rvpm_file("config.toml"))
    assert.is_true(autocmd._is_rvpm_file("before.lua"))
    assert.is_true(autocmd._is_rvpm_file("after.lua"))
  end)

  it("accepts per-plugin init/before/after hooks", function()
    assert.is_true(autocmd._is_rvpm_file("plugins/github.com/owner/repo/init.lua"))
    assert.is_true(autocmd._is_rvpm_file("plugins/github.com/owner/repo/before.lua"))
    assert.is_true(autocmd._is_rvpm_file("plugins/github.com/owner/repo/after.lua"))
  end)

  it("rejects paths that do not match any known rvpm file", function()
    assert.is_false(autocmd._is_rvpm_file("README.md"))
    assert.is_false(autocmd._is_rvpm_file("rvpm.lock"))
    assert.is_false(autocmd._is_rvpm_file("plugins/github.com/owner/repo/README.md"))
    assert.is_false(autocmd._is_rvpm_file("plugins/github.com/owner/init.lua"))
  end)
end)
