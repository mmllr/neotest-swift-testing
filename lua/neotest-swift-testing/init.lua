local lib = require("neotest.lib")
local async = require("neotest.async")
local xml = require("neotest.lib.xml")
local util = require("neotest-swift-testing.util")
local Path = require("plenary.path")
local logger = require("neotest-swift-testing.logging")
local filetype = require("plenary.filetype")

local M = {
  name = "neotest-swift-testing",
  root = lib.files.match_root_pattern("Package.swift"),
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
}

-- Add filetype for swift until it gets added to plenary's built-in filetypes
-- See https://github.com/nvim-lua/plenary.nvim?tab=readme-ov-file#plenaryfiletype for more information
if filetype.detect_from_extension("swift") == "" then
  filetype.add_table({
    extension = { ["swift"] = "swift" },
  })
end

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

M.discover_positions = function(file_path)
  return lib.treesitter.parse_positions(file_path, treesitter_query, { nested_tests = true, require_namespaces = true })
end

---@async
---@param cmd string[]
---@return string|nil
local function shell(cmd)
  local code, result = lib.process.run(cmd, { stdout = true, stderr = true })
  if code ~= 0 or result.stderr ~= nil or result.stdout == nil then
    logger.error("Failed to run command: " .. vim.inspect(cmd) .. " " .. result.stderr)
    return nil
  end
  return result.stdout
end

---Removes new line characters
---@param str string
---@return string
local function remove_nl(str)
  local trimmed, _ = string.gsub(str, "\n", "")
  return trimmed
end

---Returns Xcode devoloper path
---@async
---@return string|nil
local function get_dap_cmd()
  local result = shell({ "xcode-select", "-p" })
  if not result then
    return nil
  end
  result = shell({ "fd", "swiftpm-testing-helper", remove_nl(result) })
  if not result then
    return nil
  end
  return remove_nl(result)
end

---@async
---@return string[]|nil
local function get_test_executable()
  local bin_path = shell({ "swift", "build", "--show-bin-path" })
  if not bin_path then
    return nil
  end
  local json_path = remove_nl(bin_path) .. "/description.json"
  if not lib.files.exists(json_path) then
    return nil
  end
  local decoded = vim.json.decode(lib.files.read(json_path))
  return decoded.builtTestProducts[1].binaryPath
end

---@async
---@param test_name string
---@param dap_args? table
---@return table|nil
local function get_dap_config(test_name, dap_args)
  local program = get_dap_cmd()
  if program == nil then
    logger.error("Failed to get the spm test helper path")
    return nil
  end
  local executable = get_test_executable()
  if not executable then
    logger.error("Failed to get the test executable path")
    return nil
  end
  return vim.tbl_extend("force", dap_args or {}, {
    name = "Swift Test debugger",
    type = "lldb",
    request = "launch",
    program = program,
    args = {
      "--test-bundle-path",
      executable,
      "--testing-library",
      "swift-testing",
      "--enable-swift-test",
      "--filter",
      test_name,
    },
    cwd = "${workspaceFolder}",
    stopOnEntry = false,
  })
end

---@async
---@return integer
local function ensure_test_bundle_is_build()
  local code, result = lib.process.run({
    "swift",
    "build",
    "--build-tests",
    "--enable-swift-testing",
    "-c",
    "debug",
  })
  if code ~= 0 then
    logger.debug("Failed to build test bundle: " .. result.stderr)
  end
  return code
end

---Finds the test target for a given file in the package directory
---@async
---@param package_directory string
---@param file_name string
---@return string|nil The test target name or nil if not found
local function find_test_target(package_directory, file_name)
  local result = shell({ "swift", "package", "--package-path", package_directory, "describe", "--type", "json" })
  if result == nil then
    logger.error("Failed to run swift package describe.")
    return nil
  end

  local decoded = vim.json.decode(result)
  if not decoded then
    logger.error("Failed to decode swift package describe output.")
    return nil
  end

  for _, target in ipairs(decoded.targets or {}) do
    if target.type == "test" and target.sources and vim.list_contains(target.sources, file_name) then
      return target.name
    end
  end
  return nil
end

---@async
---@param args neotest.RunArgs
---@return neotest.RunSpec|neotest.RunSpec[]|nil
function M.build_spec(args)
  if not args.tree then
    logger.error("Unexpectedly did not receive a neotest.Tree.")
    return nil
  end
  local position = args.tree:data()
  local junit_folder = async.fn.tempname()
  local cwd = assert(M.root(position.path), "could not locate root directory of " .. position.path)

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
      return
    end

    local full_test_name = target .. "." .. class_name .. "/" .. test_name .. "()"
    if ensure_test_bundle_is_build() ~= 0 then
      logger.error("Failed to build test bundle.")
      return nil
    end
    local path = shell({ "xcrun", "--show-sdk-platform-path" }) or ""
    return {
      cwd = cwd,
      context = { is_dap_active = true, position_id = position.id },
      strategy = get_dap_config(full_test_name),
      env = { ["DYLD_FRAMEWORK_PATH"] = remove_nl(path) .. "/Developer/Library/Frameworks" },
    }
  end

  local command = {
    "swift",
    "test",
    "--enable-swift-testing",
    "-c",
    "debug",
    "--xunit-output",
    junit_folder .. "junit.xml",
    "-q",
  }
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

  return {
    command = command,
    context = {
      results_path = junit_folder .. "junit-swift-testing.xml",
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
function M.results(spec, result, tree)
  local test_results = {}
  local nodes = {}

  if spec.context.errors ~= nil and #spec.context.errors > 0 then
    -- mark as failed if a non-test error occurred.
    test_results[spec.context.position_id] = {
      status = "failed",
      errors = spec.context.errors,
    }
    return test_results
  elseif spec.context and spec.context.is_dap_active and spec.context.position_id then
    -- return early if test result processing is not desired.
    test_results[spec.context.position_id] = {
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
  local raw_output = async.fn.readfile(result.output)

  if lib.files.exists(spec.context.results_path) then
    local root = xml.parse(lib.files.read(spec.context.results_path))

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
          logger.debug("Position not found: " .. testcase._attr.classname .. " " .. testcase._attr.name)
        end
      end
    end
  else
    if spec.context.position_id ~= nil then
      test_results[spec.context.position_id] = {
        status = "failed",
        output = result.output,
        short = raw_output,
      }
    end
  end
  return test_results
end

setmetatable(M, {
  __call = function(_, opts)
    if opts.log_level then
      logger:set_level(opts.log_level)
    end
    return M
  end,
})

return M
