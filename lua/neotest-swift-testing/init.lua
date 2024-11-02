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
if filetype.detect_from_extension("swift") == "" then
	filetype.add_table({
		extension = { ["swift"] = "swift" },
	})
end

local SwiftNeotestAdapter = {
	name = "neotest-swift",
}

function SwiftNeotestAdapter.root(dir)
	return lib.files.match_root_pattern("Package.swift")(dir)
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
	local filtered_folders = { "Sources", "build", ".git", ".build", ".git", ".swiftpm" }
	return table_contains(filtered_folders, name) == false
end

function SwiftNeotestAdapter.is_test_file(file_path)
	if not vim.endswith(file_path, ".swift") then
		return false
	end
	local elems = vim.split(file_path, Path.path.sep)
	local file_name = elems[#elems]
	return vim.endswith(file_name, "Test.swift") or vim.endswith(file_name, "Tests.swift")
end

function SwiftNeotestAdapter.discover_positions(file_path)
	local query = [[

;; @Suite struct TestSuite
((class_declaration
    (modifiers
        (attribute
            (user_type
                (type_identifier) @annotation (#eq? @annotation "Suite"))))?
         name: (type_identifier) @namespace.name)
         ) @namespace.definition

;; @Test test func 
((function_declaration
    (modifiers
        (attribute
            (user_type
                (type_identifier) @annotation (#eq? @annotation "Test"))))
         name: (simple_identifier) @test.name)) @test.definition

]]
	return lib.treesitter.parse_positions(file_path, query, {})
end

function SwiftNeotestAdapter.build_spec(args)
	local position = args.tree:data()
	local junit_folder = async.fn.tempname()
	local cwd = assert(SwiftNeotestAdapter.root(position.path), "could not locate root directory of " .. position.path)
	local command = "swift test  --xunit-output " .. junit_folder .. ".junit.xml"

	logger.info("Type: " .. position.type)
	logger.info("Name: " .. position.name)

	if position.type == "file" then
		command = command .. " --filter /" .. position.name
	elseif
		position.type == "namespace"
		or position.type == "test"
		or position.type == "dir" and position.name ~= cwd
	then
		command = command .. " --filter " .. position.name
	end

	return {
		command = command,
		context = {
			results_path = junit_folder .. ".junit-swift-testing.xml",
		},
		cwd = cwd,
	}
end

function SwiftNeotestAdapter.results(spec, result, tree)
	local results = {}
	logger.info(vim.inspect(tree))
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
					local filename = util.replace_first_occurrence(testcase._attr.classname, "%.", "/")
					local name = util.replace_first_occurrence(testcase._attr.classname, "%.", "::")
					results[spec.cwd .. "/Tests/" .. filename .. ".swift::" .. util.trim_up_to_prefix(
						testcase._attr.classname,
						"."
					) .. "::" .. util.get_prefix(testcase._attr.name, "(")] =
						{
							status = "passed",
						}
				end
			end
		end

		logger.info("Testsuites: " .. vim.inspect(testsuites))
	else
		local output = result.output

		results[spec.context.position_id] = {
			status = "failed",
			output = output,
		}
	end
	logger.info(results)
	logger.info("Results: " .. vim.inspect(results))
	return results
end

return SwiftNeotestAdapter
