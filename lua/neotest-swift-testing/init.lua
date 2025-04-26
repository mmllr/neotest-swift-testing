local lib = require("neotest.lib")
local async = require("neotest.async")
local xml = require("neotest.lib.xml")
local util = require("neotest-swift-testing.util")
local Path = require("plenary.path")
local logger = require("neotest-swift-testing.logging")
local filetype = require("plenary.filetype")

-- Add filetype for swift until it gets added to plenary's built-in filetypes
-- See https://github.com/nvim-lua/plenary.nvim?tab=readme-ov-file#plenaryfiletype for more information
if filetype.detect_from_extension("swift") == "" then
  filetype.add_table({
    extension = { ["swift"] = "swift" },
  })
end

local get_root = lib.files.match_root_pattern("Package.swift")

local treesitter_query = [[
;; @Suite struct TestSuite
((class_declaration
    (modifiers
        (attribute
            (user_type
                (type_identifier) @annotation (#eq? @annotation "Suite"))))?
         name: (type_identifier) @namespace.name)
         ) @namespace.definition

((class_declaration
    name: (user_type
      (type_identifier) @namespace.name))) @namespace.definition

;; @Test test func
((function_declaration
    (modifiers
        (attribute
            (user_type
                (type_identifier) @annotation (#eq? @annotation "Test"))))
         name: (simple_identifier) @test.name)) @test.definition

]]

---@async
---@param test_name string
---@param bundle_name string
---@param dap_args? table
---@return table | nil
local function get_dap_config(test_name, bundle_name, dap_args)
  local result = async.wrap(util.run_job, 3)({ "xcrun", "-f", "xctest" }, nil)
  if result.code ~= 0 or result.stderr ~= "" then
    return nil
  end
  return vim.tbl_extend("force", dap_args or {}, {
    name = "Swift Test debugger",
    type = "lldb",
    request = "launch",
    program = vim.trim(result.stdout),
    args = { "-XCTest", test_name, bundle_name },
    cwd = "${workspaceFolder}",
    stopOnEntry = false,
    waitfor = true,
  })
end

---Finds the test target for a given file in the package directory
---@async
---@param package_directory string
---@param file_name string
-- @return string|nil The test target name or nil if not found
local function find_test_target(package_directory, file_name)
  logger.debug("Finding test target for file: " .. file_name)
  local result = async.process.run({
    cmd = "swift",
    args = { "package", "--package-path", package_directory, "describe", "--type", "json" },
    cwd = package_directory,
  })
  if not result then
    logger.error("Failed to run swift package describe.")
    return nil
  end
  local output = result.stdout.read()
  result.close()

  local decoded = vim.json.decode(output)
  if not decoded then
    logger.error("Failed to decode swift package describe output.")
    return nil
  end

  for _, target in ipairs(decoded.targets) do
    if target.type == "test" and target.sources and vim.list_contains(target.sources, file_name) then
      return target.name
    end
  end
  return nil
end

---@async
--@param args neotest.RunArgs
--@return neotest.RunSpec | neotest.RunSpec[] | nil
--@return neotest.RunSpec
local function build_spec(args)
  if not args.tree then
    logger.error("Unexpectedly did not receive a neotest.Tree.")
    return
  end
  local position = args.tree:data()
  local junit_folder = async.fn.tempname()
  local cwd = assert(get_root(position.path), "could not locate root directory of " .. position.path)
  local command = {
    "swift",
    "test",
    "--enable-swift-testing",
    "-c",
    "debug",
    "--xunit-output",
    junit_folder .. ".junit.xml",
    "-q",
  }

  if args.strategy == "dap" then
    -- id pattern /Users/name/project/Tests/ProjectTests/fileName.swift::className::testName
    local file_name, class_name, test_name = position.id:match(".*/(.-%.swift)::(.-)::(.*)")

    if file_name == nil or class_name == nil or test_name == nil then
      logger.error("Could not extract file, class name and test name from position.id: " .. position.id)
      return
    end

    local target = find_test_target(cwd, file_name)
    if not target then
      logger.error("Swift test target not found.")
    end

    local full_test_name = target .. "." .. class_name .. "/" .. test_name .. "()"
    -- TODO: is there a better way to get the test bundle?
    local test_bundle = cwd .. "/.build/apple/Products/Debug/" .. target .. ".xctest"
    local strategy_config = get_dap_config(full_test_name, test_bundle)
    return {
      command = vim.tbl_extend("force", command, {
        "--build-system",
        "xcode",
      }),
      cwd = get_root(position.path),
      context = { is_dap_active = true, pos_id = position.id },
      strategy = strategy_config,
    }
  end

  local filters = {}
  if position.type == "file" then
    table.insert(filters, "/" .. position.name)
  elseif position.type == "namespace" then
    table.insert(filters, "." .. position.name .. "$")
  elseif position.type == "test" then
    local namespace, test = string.match(position.id, ".*::(.-)::(.-)$")
    if namespace ~= nil and test ~= nil then
      table.insert(filters, namespace .. "." .. test)
    end
  elseif position.type == "dir" and position.path ~= cwd then
    table.insert(filters, position.name)
  end

  if #filters > 0 then
    table.insert(command, "--filter")
    for _, filter in ipairs(filters) do
      table.insert(command, filter)
    end
  end

  logger.debug("Command: " .. table.concat(command, " "))

  return {
    command = command,
    context = {
      results_path = junit_folder .. ".junit-swift-testing.xml",
    },
    cwd = cwd,
  }
end

---Parse the output of swift test to get the line number and error message
---@async
---@param output string[] The output of the swift test command
---@param position neotest.Position The position of the test
---@param test_name string The name of the test
---@return integer?, string? The line number and error message. nil if not found
local function parse_errors(output, position, test_name)
  local pattern = "Test (%w+)%(%) recorded an issue at ([%w-_]+%.swift):(%d+):%d+: (.+)"
  local pattern_with_arguments =
    "Test (%w+)%b() recorded an issue with 1 argument value → (.+) at ([%w-_]+%.swift):(%d+):%d+: (.+)"
  for _, line in ipairs(output) do
    local method, file, line_number, message = line:match(pattern)
    if method and file and line_number and message then
      if test_name == method and vim.endswith(position.path, file) then
        return tonumber(line_number) - 1 or nil, message
      end
    end
    method, _, file, line_number, message = line:match(pattern_with_arguments)
    logger.debug(
      "Method: "
        .. vim.inspect(method)
        .. " Test Name: "
        .. vim.inspect(test_name)
        .. " File: "
        .. vim.inspect(file)
        .. " Line: "
        .. vim.inspect(line_number)
        .. " Message: "
        .. vim.inspect(message)
    )
    if method and file and line_number and message then
      if test_name == method and vim.endswith(position.path, file) then
        return tonumber(line_number) - 1 or nil, message
      end
    end
  end
  return nil, nil
end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param tree neotest.Tree
---@return table<string, neotest.Result>
local function results(spec, result, tree)
  local test_results = {}
  local nodes = {}

  if spec.context.errors ~= nil and #spec.context.errors > 0 then
    logger.debug("Errors: " .. spec.context.errors)
    -- mark as failed if a non-test error occurred.
    test_results[spec.context.position_id] = {
      status = "failed",
      errors = spec.context.errors,
    }
    return test_results
  elseif spec.context and spec.context.is_dap_active and spec.context.pos_id then
    -- return early if test result processing is not desired.
    test_results[spec.context.pos_id] = {
      status = "skipped",
    }
    return test_results
  end

  local position = tree:data()
  local list = tree:to_list()
  local tests = util.collect_tests(list)
  if position.type == "test" then
    table.insert(nodes, position)
  end

  for _, node in ipairs(tests) do
    table.insert(nodes, node)
  end
  logger.debug("Nodes: " .. vim.inspect(nodes))
  local raw_output = async.fn.readfile(result.output)

  if util.file_exists(spec.context.results_path) then
    logger.debug("Results junit.xml: " .. spec.context.results_path)
    local data = async.file.open(spec.context.results_path)

    if data == nil then
      logger.error("Failed to open file: " .. spec.context.results_path)
      return {}
    end
    local content, error = data.read(nil, 0)
    data.close()
    if content == nil then
      logger.error("Failed to read file: " .. spec.context.results_path)
      return {}
    end

    local root = xml.parse(content)

    local testsuites
    if root.testsuites.testsuite == nil then
      testsuites = {}
    elseif #root.testsuites.testsuite == 0 then
      testsuites = { root.testsuites.testsuite }
    else
      testsuites = root.testsuites.testsuite
    end
    for _, testsuite in pairs(testsuites) do
      local testcases

      if testsuite.testcase == nil then
        testcases = {}
      elseif #testsuite.testcase == 0 then
        testcases = { testsuite.testcase }
      else
        testcases = testsuite.testcase
      end

      for _, testcase in ipairs(testcases) do
        local test_position = util.find_position(nodes, testcase._attr.classname, testcase._attr.name, spec.cwd)
        if test_position ~= nil then
          if testcase.failure then
            local line_number, error_message =
              parse_errors(raw_output, test_position, util.get_prefix(testcase._attr.name, "("))
            test_results[test_position.id] = {
              status = "failed",
            }
            if line_number and error_message then
              test_results[test_position.id].errors = {
                { line = line_number, message = error_message },
              }
            end
          else
            test_results[test_position.id] = {
              status = "passed",
            }
          end
        else
          logger.info("Position not found: " .. testcase._attr.classname .. " " .. testcase._attr.name)
        end
      end
    end
  else
    local output = result.output

    logger.info("Context: " .. vim.inspect(spec.context))
    if spec.context.position_id ~= nil then
      test_results[spec.context.position_id] = {
        status = "failed",
        output = output,
      }
    end
  end
  logger.debug("Results: " .. vim.inspect(test_results))
  return test_results
end

---@type neotest.Adapter
return {
  name = "neotest-swift-testing",
  root = get_root,
  filter_dir = function(name, rel_path, root)
    return vim.list_contains({ "Sources", "build", ".git", ".build", ".git", ".swiftpm" }, name) == false
  end,
  is_test_file = function(file_path)
    if not vim.endswith(file_path, ".swift") then
      return false
    end
    local elems = vim.split(file_path, Path.path.sep)
    local file_name = elems[#elems]
    return vim.endswith(file_name, "Test.swift") or vim.endswith(file_name, "Tests.swift")
  end,
  discover_positions = function(file_path)
    return lib.treesitter.parse_positions(
      file_path,
      treesitter_query,
      { nested_tests = true, require_namespaces = true }
    )
  end,
  build_spec = build_spec,
  results = results,
}
