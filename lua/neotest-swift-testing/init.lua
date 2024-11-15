local lib = require("neotest.lib")
local async = require("neotest.async")
local context_manager = require("plenary.context_manager")
local open = context_manager.open
local with = context_manager.with
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

---@param args neotest.RunArgs
---@return neotest.RunSpec | neotest.RunSpec[] | nil
local function build_spec(args)
	local position = args.tree:data()
	local junit_folder = async.fn.tempname()
	local cwd = assert(get_root(position.path), "could not locate root directory of " .. position.path)
	local command = { "swift", "test", "--enable-swift-testing", "--xunit-output", junit_folder .. ".junit.xml", "-q" }

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
	elseif position.type == "dir" and position.name ~= cwd then
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
---comment
---@param output string[]
---@param position neotest.Position
---@param test_name string
---@return integer?, string?
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
		local data
		with(open(spec.context.results_path, "r"), function(reader)
			data = reader:read("*a")
		end)

		local root = xml.parse(data)

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
		return util.table_contains({ "Sources", "build", ".git", ".build", ".git", ".swiftpm" }, name) == false
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
		return lib.treesitter.parse_positions(file_path, treesitter_query, {})
	end,
	build_spec = build_spec,
	results = results,
}
