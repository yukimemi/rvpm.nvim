local chezmoi = require("rvpm.chezmoi")
local cfg = require("rvpm.config")

describe("rvpm.chezmoi", function()
  local tmpdir
  local orig_config_toml

  before_each(function()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    orig_config_toml = cfg.config_toml
    cfg.options.config_root = tmpdir
    cfg.config_toml = function()
      return tmpdir .. "/config.toml"
    end
    chezmoi.invalidate_cache()
  end)

  after_each(function()
    cfg.config_toml = orig_config_toml
    chezmoi.invalidate_cache()
    pcall(vim.fn.delete, tmpdir, "rf")
  end)

  local function write_config(body)
    local fd = assert(io.open(tmpdir .. "/config.toml", "w"))
    fd:write(body)
    fd:close()
    chezmoi.invalidate_cache()
  end

  describe("enabled_in_config", function()
    it("returns false when config.toml is missing", function()
      assert.is_false(chezmoi.enabled_in_config())
    end)

    it("returns true when [options].chezmoi = true", function()
      write_config("[options]\nchezmoi = true\n")
      assert.is_true(chezmoi.enabled_in_config())
    end)

    it("returns false when [options].chezmoi = false", function()
      write_config("[options]\nchezmoi = false\n")
      assert.is_false(chezmoi.enabled_in_config())
    end)

    it("returns false when the chezmoi key is absent", function()
      write_config("[options]\nconcurrency = 8\n")
      assert.is_false(chezmoi.enabled_in_config())
    end)

    it("ignores chezmoi keys in other sections", function()
      -- Only `[options].chezmoi` is authoritative; a stray `chezmoi = true`
      -- elsewhere must not flip the integration on.
      write_config("[vars]\nchezmoi = true\n\n[options]\nconcurrency = 8\n")
      assert.is_false(chezmoi.enabled_in_config())
    end)

    it("caches until invalidate_cache is called", function()
      write_config("[options]\nchezmoi = false\n")
      assert.is_false(chezmoi.enabled_in_config())
      -- Change the file on disk without invalidating — cached value wins.
      local fd = assert(io.open(tmpdir .. "/config.toml", "w"))
      fd:write("[options]\nchezmoi = true\n")
      fd:close()
      assert.is_false(chezmoi.enabled_in_config())
      -- After invalidation we see the updated value.
      chezmoi.invalidate_cache()
      assert.is_true(chezmoi.enabled_in_config())
    end)
  end)

  describe("source_root", function()
    it("returns nil when chezmoi is disabled", function()
      write_config("[options]\nchezmoi = false\n")
      assert.is_nil(chezmoi.source_root())
    end)
  end)

  describe("prewarm_source_root", function()
    it("is an immediate no-op when chezmoi is disabled (no subprocess)", function()
      write_config("[options]\nchezmoi = false\n")
      local start = vim.uv.hrtime()
      chezmoi.prewarm_source_root()
      local elapsed_ms = (vim.uv.hrtime() - start) / 1e6
      assert.is_true(
        elapsed_ms < 50,
        "prewarm should be instant when chezmoi is off, was " .. elapsed_ms .. "ms"
      )
      assert.is_nil(chezmoi.source_root())
    end)
  end)

  describe("sync_target_to_source", function()
    it("invokes the callback synchronously when chezmoi is disabled", function()
      write_config("[options]\nchezmoi = false\n")
      local called = false
      chezmoi.sync_target_to_source(tmpdir .. "/config.toml", function()
        called = true
      end)
      assert.is_true(called, "callback must fire immediately when disabled")
    end)
  end)

  describe("apply_source_to_target", function()
    it("invokes the callback synchronously when chezmoi is disabled", function()
      write_config("[options]\nchezmoi = false\n")
      local called = false
      chezmoi.apply_source_to_target("/any/source/path", function()
        called = true
      end)
      assert.is_true(called, "callback must fire immediately when disabled")
    end)
  end)
end)
