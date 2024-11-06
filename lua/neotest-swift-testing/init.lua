local lib = require("neotest.lib")
local async = require("neotest.async")
local context_manager = require("plenary.context_manager")
local open = context_manager.open
local with = context_manager.with
local xml = require("neotest.lib.xml")
local util = require("neotest-swift-testing.util")
local errors = require("neotest-swift-testing.errors")
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

local function swift_test_list()
	local list_cmd = { "swift", "test", "list", "-c", "debug", "--skip-build", "--enable-xctest" }
	local list_cmd_string = table.concat(list_cmd, " ")
	logger.debug("Running swift list: " .. list_cmd_string)
	local result = vim.system(list_cmd, { text = true }):wait()

	local err = nil
	if result.code == 1 then
		err = "swift list:"
		if result.stdout ~= nil and result.stdout ~= "" then
			err = err .. " " .. result.stdout
		end
		if result.stdout ~= nil and result.stderr ~= "" then
			err = err .. " " .. result.stderr
		end
		logger.error({ "Swift list error: ", err })
	end
	return result
end

local function swift_package_describe()
	local describe_cmd = { "swift", "package", "describe" }
	local describe_cmd_string = table.concat(describe_cmd, " ")
	logger.debug("Running swift package describe: " .. describe_cmd_string)
	local result = vim.system(describe_cmd, { text = true }):wait()

	local err = nil
	if result.code == 1 then
		err = "swift package describe:"
		if result.stdout ~= nil and result.stdout ~= "" then
			err = err .. " " .. result.stdout
		end
		if result.stdout ~= nil and result.stderr ~= "" then
			err = err .. " " .. result.stderr
		end
		logger.error({ "Swift package describe error: ", err })
	end
	return result
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
	local command = { "swift", "test", "--enable-swift-testing", "--xunit-output", junit_folder .. ".junit.xml" }

	local filters = {}
	if position.type == "file" then
		table.insert(filters, "/" .. position.name)
	elseif position.type == "namespace" then
		table.insert(filters, '".' .. position.name .. '$"')
	elseif position.type == "test" or position.type == "dir" and position.name ~= cwd then
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

---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param tree neotest.Tree
---@return table<string, neotest.Result>
local function results(spec, result, tree)
	local test_results = {}
	local position = tree:data()
	local list = tree:to_list()
	local tests = util.collect_tests(list)
	local nodes = {}
	if position.type == "test" then
		table.insert(nodes, position)
	end

	for _, node in ipairs(tests) do
		table.insert(nodes, node)
	end
	logger.debug("Nodes: " .. vim.inspect(nodes))
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

			for _, testcase in pairs(testcases) do
				local function result_from_testcaste(t)
					if t.failure then
						return {
							status = "failed",
							errors = {
								{ message = t.failure._attr.message },
							},
						}
					else
						return {
							status = "passed",
						}
					end
				end
				local position = util.find_position(nodes, testcase._attr.classname, testcase._attr.name)
				if position ~= nil then
					test_results[position.id] = result_from_testcaste(testcase)
				else
					logger.info("Position not found: " .. testcase._attr.classname .. " " .. testcase._attr.name)
				end
			end
		end
	else
		local output = result.output

		test_results[spec.context.position_id] = {
			status = "failed",
			output = output,
		}
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
