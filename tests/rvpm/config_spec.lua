local cfg = require("rvpm.config")

describe("rvpm.config", function()
  describe("appname", function()
    local saved_rvpm, saved_nvim

    before_each(function()
      saved_rvpm = vim.env.RVPM_APPNAME
      saved_nvim = vim.env.NVIM_APPNAME
    end)

    after_each(function()
      vim.env.RVPM_APPNAME = saved_rvpm
      vim.env.NVIM_APPNAME = saved_nvim
    end)

    it("prefers $RVPM_APPNAME", function()
      vim.env.RVPM_APPNAME = "rvpm-test"
      vim.env.NVIM_APPNAME = "nvim-test"
      assert.equals("rvpm-test", cfg.appname())
    end)

    it("falls back to $NVIM_APPNAME when RVPM_APPNAME is unset", function()
      vim.env.RVPM_APPNAME = nil
      vim.env.NVIM_APPNAME = "nvim-test"
      assert.equals("nvim-test", cfg.appname())
    end)

    it("falls back to 'nvim' when both are unset", function()
      vim.env.RVPM_APPNAME = nil
      vim.env.NVIM_APPNAME = nil
      assert.equals("nvim", cfg.appname())
    end)
  end)

  describe("plugin_names", function()
    local tmp, orig

    before_each(function()
      tmp = vim.fn.tempname()
      orig = cfg.config_toml
      cfg.config_toml = function()
        return tmp
      end
    end)

    after_each(function()
      cfg.config_toml = orig
      pcall(os.remove, tmp)
    end)

    local function write(body)
      local fd = assert(io.open(tmp, "w"))
      fd:write(body)
      fd:close()
    end

    it("picks up `name` and derives from `url` when missing", function()
      write([=[
[[plugins]]
name = "foo"
url = "owner/foo.nvim"

[[plugins]]
url = "owner/bar.nvim"
]=])
      assert.same({ "foo", "bar.nvim" }, cfg.plugin_names())
    end)

    it("strips `.git` suffix from URL-derived names", function()
      write([=[
[[plugins]]
url = "https://github.com/owner/baz.nvim.git"
]=])
      assert.same({ "baz.nvim" }, cfg.plugin_names())
    end)

    it("returns an empty list when the file is missing", function()
      pcall(os.remove, tmp)
      assert.same({}, cfg.plugin_names())
    end)

    it("ignores entries outside [[plugins]] arrays", function()
      write([=[
[vars]
name = "decoy"

[options]
concurrency = 8

[[plugins]]
url = "real/plugin"
]=])
      assert.same({ "plugin" }, cfg.plugin_names())
    end)
  end)
end)
