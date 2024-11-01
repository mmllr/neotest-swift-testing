local lib = require("neotest.lib")
local async = require("neotest.async")
local context_manager = require("plenary.context_manager")
local open = context_manager.open
local with = context_manager.with
local xml = require("neotest.lib.xml")
local util = require("neotest-swift.util")
local errors = require("neotest-swift.errors")

local SwiftNeotestAdapter = {
	name = "neotest-swift",
}

function SwiftNeotestAdapter.root(dir)
	return lib.files.match_root_pattern("Package.swift")(dir)
end

local function i(prefix, value)
	print(prefix, vim.inspect(value))
end

local function table_contains(table, value)
	for _, v in pairs(table) do
		if v == value then
			return true
		end
	end
	return false
end

function SwiftNeotestAdapter.filter_dir(name, rel_path, root)
	local filtered_folders = { "Sources", "build", ".git", ".build" }
	return table_contains(filtered_folders, name) == false
end

function SwiftNeotestAdapter.is_test_file(file_path)
	local result = string.match(file_path, ".*Tests.swift$") ~= nil
	return result
end

function SwiftNeotestAdapter.discover_positions(file_path)
	local query = [[

;; struct TestSuite
(
class_declaration
    (modifiers
        (attribute
            (user_type
                (type_identifier) @annotation (#eq? @annotation "Suite"))))
         name: (type_identifier) @namespace.name) @namespace.definition

;; test func 
(function_declaration
    (modifiers
        (attribute
            (user_type
                (type_identifier) @annotation (#eq? @annotation "Test"))))
         name: (simple_identifier) @test.name) @test.definition

]]
	return lib.treesitter.parse_positions(file_path, query, {
		nested_tests = false,
		require_namespaces = false,
	})
end

function SwiftNeotestAdapter.build_spec(args)
	local position = args.tree:data()
	local junit_folder = async.fn.tempname()
	local cwd = assert(SwiftNeotestAdapter.root(position.path), "could not locate root directory of " .. position.path)
	local command = "swift test  --xunit-output " .. junit_folder .. ".junit.xml"

	if position.type == "file" then
		i("position", position)
		command = command .. " --filter /" .. position.name
	end

	-- if position.type == "test" or position.type == "namespace" then
	-- 	command = "swift test " .. position.path .. " --test-name-pattern " .. position.name
	-- elseif position.type == "file" then
	-- 	command = "swift test " .. position.name
	-- elseif position.type == "dir" then
	-- 	command = "swift test"
	-- end

	return {
		command = command,
		context = {
			results_path = junit_folder .. ".junit-swift-testing.xml",
		},
		cwd = cwd,
	}
end

local function replace_first_occurrence(str, char, replacement)
	return string.gsub(str, char, replacement, 1)
end

function SwiftNeotestAdapter.results(spec, result, tree)
	local output_path = spec.strategy.stdio and spec.strategy.stdio[2] or result.output
	local results = {}
	if util.file_exists(spec.context.results_path) then
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
			if #testsuite.testcase == 0 then
				testcases = { testsuite.testcase }
			else
				testcases = testsuite.testcase
			end
			for _, testcase in pairs(testcases) do
				if testcase.failure then
					local output = testcase.failure[1]

					results[testcase._attr.name] = {
						status = "failed",
						short = output,
						errors = errors.parse_errors(output),
					}
				else
					local classname = replace_first_occurrence(testcase._attr.classname, "%.", "/")
					results[spec.cwd .. "/Tests/" .. classname .. ".swift::" .. testcase._attr.name] = {
						status = "passed",
					}
				end
			end
		end
	else
		local output = result.output

		results[spec.context.position_id] = {
			status = "failed",
			output = output,
		}
	end
	i("results", results)
	return results
end

return SwiftNeotestAdapter
