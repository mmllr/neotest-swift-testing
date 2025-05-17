local Tree = require("neotest.types").Tree
local lib = require("neotest.lib")

describe("Swift testing adapter", function()
  ---@type neotest.Adapter
  local sut
  setup(function()
    sut = require("neotest-swift-testing")({ log_level = vim.log.levels.OFF })
  end)

  ---@type table<string, table>
  local stubbed_commands

  before_each(function()
    stubbed_commands = {}
    lib.process.run = function(cmd, opts)
      local key = table.concat(cmd, " ")
      assert.is.is_not_nil(stubbed_commands[key], "Expected to find\n" .. key .. "\nin stubbed commands")
      local p = stubbed_commands[key]
      if p then
        stubbed_commands[key] = nil
        return p.code, { stdout = p.result }
      end
      return -1, nil
    end
  end)

  after_each(function()
    assert.are.same({}, stubbed_commands, "Expected all stubbed commands to be invoked")
  end)

  ---Stubs the result for a command.
  ---@param cmd string
  ---@param result string
  ---@param code? integer
  local function given(cmd, result, code)
    stubbed_commands[cmd] = { result = result, code = code or 0 }
  end

  it("Has a name", function()
    assert.is_equal("neotest-swift-testing", sut.name)
  end)

  it("Has a valid root function", function()
    local path = vim.fn.getcwd() .. "/spec/fixtures/Sources"
    local expected = vim.fn.getcwd() .. "/spec/fixtures"
    local actual = sut.root(path)

    assert.is_equal(expected, actual)
  end)

  it("Filters invalid directories", function()
    local root = vim.fn.getcwd() .. "/spec/fixtures/Sources"

    local invalid = { "Sources", "build", ".git", ".build", ".git", ".swiftpm" }

    for _, dir in ipairs(invalid) do
      local actual = sut.filter_dir(dir, "spec/fixtures/Sources", root)
      assert.is_false(actual)
    end
  end)

  it("Does not filters test directories", function()
    assert.is_true(sut.filter_dir("Tests", "spec/fixtures/", vim.fn.getcwd()))
    assert.is_false(sut.filter_dir("Sources", "spec/fixtures/", vim.fn.getcwd()))
  end)

  it("Accepts test files", function()
    for _, name in ipairs({ "Test.swift", "Tests/Test.swift", "FeatureTests.swift" }) do
      assert.is_true(sut.is_test_file(name), "expected " .. name .. " to be a test file")
    end
  end)

  it("Filters non test files", function()
    for _, name in ipairs({
      "Source.swift",
      "Feature.swift",
      "main.swift",
      "main.c",
      "header.h",
      "objc.m",
      "Package.swift",
      "Makefile",
    }) do
      assert.is_false(sut.is_test_file(name), "expected " .. name .. " to be a test file")
    end
  end)

  describe("Build spec", function()
    describe("DAP support", function()
      it("builds when strategy is dap", function()
        ---@type neotest.Position
        local file = {
          id = "/Users/name/project/Tests/ProjectTests/fileName.swift::className::testName",
          type = "dir",
          name = "test",
          path = "/neotest/client",
          range = { 0, 0, 0, 0 },
        }
        ---@type neotest.Tree
        local tree = Tree.from_list({ file }, function(pos)
          return pos.id
        end)
        sut.root = function(p)
          return "/project/root"
        end

        given("swift package --package-path /project/root describe --type json", "{}")

        ---@type neotest.RunArgs
        local args = {
          tree = tree,
          strategy = "dap",
        }
        sut.build_spec(args)
      end)
    end)
  end)
end)
