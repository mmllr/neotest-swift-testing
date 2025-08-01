local Tree = require("neotest.types").Tree
local lib = require("neotest.lib")
local async = require("neotest.async")

local function load_file(filename)
  local cwd = vim.fn.getcwd()
  local path = cwd .. "/" .. filename
  local file = io.open(path, "r")
  if not file then
    error("Could not open file: " .. path)
  end
  local content = file:read("*a")
  file:close()
  return content
end

describe("Swift testing adapter", function()
  local it = async.tests.it

  ---@param id string
  ---@param type neotest.PositionType
  ---@param name string
  ---@param path? string
  ---@return neotest.Tree
  local function given_tree(id, type, name, path)
    ---@type neotest.Position
    local pos = {
      id = id,
      type = type,
      name = name,
      path = path or "/neotest/client",
      range = { 0, 0, 0, 0 },
    }
    ---@type neotest.Tree
    local tree = Tree.from_list({ pos }, function(p)
      return p.id
    end)
    return tree
  end

  ---@param code? integer
  ---@param output? string
  ---@return neotest.StrategyResult
  local function given_strategy_result(code, output)
    return {
      code = code or 0,
      output = output or "",
    }
  end

  ---@type table<string, string>
  local files = {}
  ---@type table<string, boolean>
  local files_exists = {}

  local function stub_files()
    local orig = lib.files.read

    lib.files.read = function(path)
      if files[path] ~= nil then
        return files[path]
      end
      return orig(path)
    end
    local orig_exists = lib.files.exists
    lib.files.exists = function(path)
      if files_exists[path] ~= nil then
        return files_exists[path]
      end
      return orig_exists(path)
    end
  end

  ---@type neotest.Adapter
  local sut
  setup(function()
    sut = require("neotest-swift-testing")({ log_level = vim.log.levels.OFF })
  end)

  teardown(function()
    sut = nil
  end)

  ---@type table<string, table>
  local stubbed_commands

  before_each(function()
    stubbed_commands = {}
    lib.process.run = function(cmd, opts)
      local key = table.concat(cmd, " ")
      assert.is_not_nil(stubbed_commands[key], "Expected to find\n" .. key .. "\nin stubbed commands")
      local p = stubbed_commands[key]
      if p then
        stubbed_commands[key] = nil
        return p.code, { stdout = p.result }
      end
      return -1, nil
    end

    ---@diagnostic disable-next-line: duplicate-set-field
    async.fn.tempname = function()
      return "/temporary/path/"
    end
    files = {}
    files_exists = {}
  end)

  after_each(function()
    assert.are.same({}, stubbed_commands, "Expected all stubbed commands to be invoked. Uninvoked commands:\n" .. vim.inspect(stubbed_commands))
    files = {}
    files_exists = {}
  end)

  ---Stubs the result for a command.
  ---@param cmd string
  ---@param result string
  ---@param code? integer
  local function given(cmd, result, code)
    stubbed_commands[cmd] = { result = result, code = code or 0 }
  end

  ---Stubs content for lib.files.read
  ---@param path string
  ---@param content? string
  local function given_file(path, content)
    files[path] = content
    files_exists[path] = content ~= nil
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
    before_each(function()
      sut.root = function(p)
        return "/project/root"
      end
    end)

    describe("Integrated strategy", function()
      ---@param filter string
      ---@return string[]
      local function expected_command(filter)
        return {
          "swift",
          "test",
          "--enable-swift-testing",
          "--disable-xctest",
          "-c",
          "debug",
          "--xunit-output",
          "/temporary/path/junit.xml",
          "-q",
          "--filter",
          filter,
        }
      end
      it("Directory filter", function()
        ---@type neotest.RunArgs
        local args = {
          tree = given_tree(
            "/Users/name/project/Tests/ProjectTests/MyPackageTests.swift::className::testName",
            "dir",
            "folderName"
          ),
          strategy = "integrated",
        }
        local result = sut.build_spec(args)

        assert.are.same({
          command = expected_command("folderName"),
          cwd = "/project/root",
          context = {
            results_path = "/temporary/path/junit.xml",
          },
        }, result)
      end)

      it("Test filter", function()
        ---@type neotest.RunArgs
        local args = {
          tree = given_tree(
            "/Users/name/project/Tests/ProjectTests/MyPackageTests.swift::className::testName",
            "test",
            "testName()"
          ),
          strategy = "integrated",
        }
        local result = sut.build_spec(args)

        assert.are.same({
          command = expected_command("className.testName"),
          cwd = "/project/root",
          context = {
            results_path = "/temporary/path/junit.xml",
          },
        }, result)
      end)

      it("Namespace filter", function()
        ---@type neotest.RunArgs
        local args = {
          tree = given_tree(
            "/Users/name/project/Tests/ProjectTests/MyPackageTests.swift::className::testName",
            "namespace",
            "TestSuite"
          ),
          strategy = "integrated",
        }
        local result = sut.build_spec(args)

        assert.are.same({
          command = expected_command(".TestSuite$"),
          cwd = "/project/root",
          context = {
            results_path = "/temporary/path/junit.xml",
          },
        }, result)
      end)

      it("File filter", function()
        ---@type neotest.RunArgs
        local args = {
          tree = given_tree(
            "/Users/name/project/Tests/ProjectTests/MyPackageTests.swift::className::testName",
            "file",
            "filename"
          ),
          strategy = "integrated",
        }
        local result = sut.build_spec(args)

        assert.are.same({
          command = expected_command("/filename"),
          cwd = "/project/root",
          context = {
            results_path = "/temporary/path/junit.xml",
          },
        }, result)
      end)
    end)

    describe("DAP support", function()
      it("build spec when strategy is dap", function()
        given(
          "swift package --package-path /project/root describe --type json",
          load_file("spec/Fixtures/package_description.json")
        )
        given("swift build --build-tests --enable-swift-testing --disable-xctest -c debug", "")
        given("xcrun --show-sdk-platform-path", "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform")
        given("xcode-select -p", "/Applications/Xcode.App/Contents/Developer")
        given("fd swiftpm-testing-helper /Applications/Xcode.App/Contents/Developer", "/path/to/swiftpm-testing-helper")
        given("swift build --show-bin-path", "/Users/name/project/.build/arm-apple-macosx/debug")
        ---@type neotest.RunArgs
        local args = {
          tree = given_tree(
            "/project/Tests/ProjectTests/MyPackageTests.swift::className::testName",
            "dir",
            "folderName"
          ),
          strategy = "dap",
        }

        local result = sut.build_spec(args)

        assert.are.same({
          context = {
            is_dap_active = true,
            position_id = "/project/Tests/ProjectTests/MyPackageTests.swift::className::testName",
          },
          cwd = "/project/root",
          env = {
            DYLD_FRAMEWORK_PATH = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks",
          },
        }, result)
      end)
    end)
  end)

  describe("Results method", function()
    ---@type neotest.Tree
    local tree
    ---@type neotest.StrategyResult
    local strategy_result
    before_each(function()
      tree = given_tree("/project/Tests/ProjectTests/MyPackageTests.swift::className::testName", "test", "testName()")
      strategy_result = given_strategy_result(0, "/outputpath/log")
    end)
    it("Failed build", function()
      ---@type neotest.RunSpec
      local spec = {
        command = { "swift", "test" },
        context = {
          position_id = "/project/Tests/ProjectTests/MyPackageTests.swift::className::testName",
          ---@type neotest.Error[]
          errors = {
            {
              message = "Build error",
              line = 42,
            },
          },
        },
      }

      assert.are.same({
        ["/project/Tests/ProjectTests/MyPackageTests.swift::className::testName"] = {
          status = "failed",
          errors = {
            {
              message = "Build error",
              line = 42,
            },
          },
        },
      }, sut.results(spec, strategy_result, tree))
    end)

    it("Skips dap results", function()
      ---@type neotest.RunSpec
      local spec = {
        command = { "swift", "test" },
        context = {
          position_id = "/project/Tests/ProjectTests/MyPackageTests.swift::className::testName",
          is_dap_active = true,
        },
      }

      assert.are.same({
        ["/project/Tests/ProjectTests/MyPackageTests.swift::className::testName"] = {
          status = "skipped",
        },
      }, sut.results(spec, strategy_result, tree))
    end)

    it("Fails when result_path is not found", function()
      given_file("/temporary/path/junit-swift-testing.xml", nil)
      given_file("/outputpath/log", "Output errors")
      stub_files()
      local spec = {
        command = { "swift", "test" },
        context = {
          results_path = "/temporary/path/junit.xml",
          position_id = "/project/Tests/ProjectTests/MyPackageTests.swift::className::testName",
        },
      }

      assert.are.same({
        ["/project/Tests/ProjectTests/MyPackageTests.swift::className::testName"] = {
          status = "failed",
          output = "/outputpath/log",
          short = "Output errors",
        },
      }, sut.results(spec, strategy_result, tree))
    end)

    it("Successful test run", function()
      local results = [[
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="TestResults" errors="0" tests="83" failures="0" skipped="0" time="0.218349459">
  <testcase name="testName()" classname="ProjectTests.className" time="1.000001"/>
  </testsuite>
  </testsuites>
]]
      given_file("/temporary/path/junit.xml", results)
      given_file("/outputpath/log", "")
      stub_files()
      local spec = {
        cwd = "/project",
        command = { "swift", "test" },
        context = {
          results_path = "/temporary/path/junit.xml",
          position_id = "/project/Tests/ProjectTests/MyPackageTests.swift::className::testName",
        },
      }
      assert.are.same({
        ["/project/Tests/ProjectTests/MyPackageTests.swift::className::testName"] = {
          status = "passed",
        },
      }, sut.results(spec, given_strategy_result(0, "/outputpath/log"), tree))
    end)
  end)

  describe("Test discovery", function()
    it("discovers tests", function()
      local path = vim.fn.getcwd() .. "/spec/fixtures/Tests/TargetTests/TargetTests.swift"
      local output = "/temporary/path/test-events.jsonl"
      local entry = [[
{"kind":"test","payload":{"id":"MyPackageTests.example()\/MyPackageTests.swift:4:2","isParameterized":false,"kind":"function","name":"example()","sourceLocation":{"_filePath":"\/Users\/user\/MyPackage\/Tests\/MyPackageTests\/MyPackageTests.swift","column":2,"fileID":"MyPackageTests\/MyPackageTests.swift","line":4}},"version":0}
      ]]
      -- given("swift test list --enable-swift-testing --event-stream-output-path " .. output, "", 0)
      -- given_file(output, entry)

      -- assert.are.same({}, sut.discover_positions(path))
    end)
  end)
end)
