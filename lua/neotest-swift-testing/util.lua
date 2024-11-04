local ok, async = pcall(require, "nio")
if not ok then
	async = require("neotest.async")
end
local logger = require("neotest-swift-testing.logging")
local M = {}
local separator = "::"

M.file_exists = function(file)
	local f = io.open(file, "r")

	if f ~= nil then
		io.close(f)
		return true
	else
		return false
	end
end

M.replace_first_occurrence = function(str, char, replacement)
	return string.gsub(str, char, replacement, 1)
end

M.table_contains = function(table, value)
	for _, v in pairs(table) do
		if v == value then
			return true
		end
	end
	return false
end

M.trim_up_to_prefix = function(str, char)
	local pattern = "^[^" .. char .. "]*" .. char
	return string.gsub(str, pattern, "")
end

local function get_prefix(str, char)
	local prefix = string.match(str, "^[^" .. char .. "]*")
	return prefix
end

local function has_prefix(str, prefix)
	return str:sub(1, #prefix) == prefix
end

local function has_suffix(str, suffix)
	return str == "" or str:sub(-#suffix) == suffix
end

local function find_element_by_id(list, prefix, suffix)
	for _, item in ipairs(list) do
		local a = has_prefix(item.id, prefix)
		local b = has_suffix(item.id, suffix)

		logger.info("list.id: " .. item.id)
		logger.info("predicate: " .. vim.inspect(a) .. " " .. vim.inspect(b))
		if item.type == "test" and a and b then
			return item
		end
	end
	return nil
end

M.collect_tests = function(nested_table)
	local flattened_table = {}

	local function recurse(subtable)
		for _, item in ipairs(subtable) do
			if type(item) == "table" then
				if item.type == "test" then
					table.insert(flattened_table, item)
				else
					recurse(item)
				end
			end
		end
	end

	recurse(nested_table)
	return flattened_table
end

M.find_position = function(list, class_name, test_name)
	local cwd = async.fn.getcwd()

	local module, class = class_name:match("([^%.]+)%.([^%.]+)")
	if not module or not class then
		return nil
	end
	local prefix = cwd .. "/Tests/" .. module
	local suffix = separator .. class .. separator .. get_prefix(test_name, "(")

	logger.info("prefix: " .. prefix)
	logger.info("suffix: " .. suffix)

	return find_element_by_id(list, prefix, suffix)
end

return M
