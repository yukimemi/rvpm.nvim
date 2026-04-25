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

describe("rvpm.autocmd._on_save (chezmoi cache ordering)", function()
  -- Regression for the silent-skip bug observed in production:
  --   1. user opens `:Rvpm` → `c` (config edit)
  --   2. $EDITOR is a remote-send command that delivers the source-side
  --      config.toml to a long-running neovide
  --   3. user edits and saves the source-side config.toml in neovide
  --   4. expected: BufWritePost runs `chezmoi apply` then `rvpm generate`
  --   5. actual (before fix): nothing happens — the user has to
  --      `chezmoi apply` by hand
  --
  -- Root cause: the BufWritePost handler invalidated the chezmoi cache
  -- *before* classifying the path, so `chezmoi.source_root()` returned
  -- nil during classification of the very save that triggered the
  -- invalidation. The path was outside config_root (it's the source
  -- root), and source detection was off, so classify returned nil.
  --
  -- The fix is to classify first and invalidate after.
  local cli = require("rvpm.cli")

  local saved
  local source_root_path
  local cleared
  local order
  local apply_target
  local cli_calls

  local function fake_chezmoi_state()
    cleared = false
    order = {}
    apply_target = nil
    cli_calls = {}

    chezmoi.source_root = function()
      table.insert(order, "source_root")
      if cleared then
        return nil
      end
      return source_root_path
    end
    chezmoi.invalidate_cache = function()
      table.insert(order, "invalidate_cache")
      cleared = true
    end
    chezmoi.prewarm_source_root = function()
      table.insert(order, "prewarm")
    end
    chezmoi.apply_source_to_target = function(src, cb)
      apply_target = src
      cb()
    end
    cli.run = function(args)
      table.insert(cli_calls, args[1])
    end
  end

  before_each(function()
    setup_root(ROOT)
    source_root_path = IS_WINDOWS
      and "C:/Users/test/.local/share/chezmoi/dot_config/rvpm/nvim"
      or "/home/test/.local/share/chezmoi/dot_config/rvpm/nvim"
    saved = {
      source_root = chezmoi.source_root,
      invalidate_cache = chezmoi.invalidate_cache,
      prewarm_source_root = chezmoi.prewarm_source_root,
      apply_source_to_target = chezmoi.apply_source_to_target,
      run = cli.run,
    }
    fake_chezmoi_state()
  end)

  after_each(function()
    chezmoi.source_root = saved.source_root
    chezmoi.invalidate_cache = saved.invalidate_cache
    chezmoi.prewarm_source_root = saved.prewarm_source_root
    chezmoi.apply_source_to_target = saved.apply_source_to_target
    cli.run = saved.run
    restore_root()
  end)

  it("triggers chezmoi apply on source-side config.toml save", function()
    local source_config = source_root_path .. "/config.toml"
    autocmd._on_save(source_config)

    assert.equals(
      source_config,
      apply_target,
      "apply_source_to_target must run for source-side config.toml saves "
        .. "(otherwise the edit never reaches target)"
    )
    assert.same({ "generate" }, cli_calls, "generate must run after apply")
  end)

  it("classifies before invalidating so the source_root cache is still warm", function()
    autocmd._on_save(source_root_path .. "/config.toml")

    local first_source_root, first_invalidate
    for i, name in ipairs(order) do
      if name == "source_root" and not first_source_root then
        first_source_root = i
      end
      if name == "invalidate_cache" and not first_invalidate then
        first_invalidate = i
      end
    end
    assert.is_not_nil(first_source_root, "classify must consult source_root()")
    assert.is_not_nil(first_invalidate, "invalidate_cache must run for config.toml save")
    assert.is_true(
      first_source_root < first_invalidate,
      "classify must read source_root BEFORE invalidate_cache (otherwise source detection sees a cleared cache)"
    )
  end)

  it("still runs generate-only on target-side config.toml save", function()
    autocmd._on_save(ROOT .. "/config.toml")

    assert.is_nil(apply_target, "target-side config.toml save must NOT trigger chezmoi apply")
    assert.same({ "generate" }, cli_calls)
  end)

  it("still invalidates the chezmoi cache after a target-side config.toml save", function()
    autocmd._on_save(ROOT .. "/config.toml")
    assert.is_true(cleared, "invalidate_cache must run so the next save sees the new flag")
  end)

  it("does nothing for unrelated saves and does not invalidate the cache", function()
    local unrelated = IS_WINDOWS and "C:/Users/test/project/src/main.rs" or "/home/test/project/src/main.rs"
    autocmd._on_save(unrelated)

    assert.is_nil(apply_target)
    assert.same({}, cli_calls)
    assert.is_false(cleared, "non-config.toml saves must not churn the chezmoi cache")
  end)
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
