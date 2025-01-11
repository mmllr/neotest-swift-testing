local ok, async = pcall(require, "nio")
if not ok then
	async = require("neotest.async")
end
local logger = require("neotest-swift-testing.logging")
local M = {}
local separator = "::"

---Check if a file exists.
---@param file string The file path.
---@return boolean True if the file exists, false otherwise.
M.file_exists = function(file)
	local f = io.open(file, "r")

	if f ~= nil then
		io.close(f)
		return true
	else
		return false
	end
end

---Replace the first occurrence of a character in a string.
---@param str string The string.
---@param char string The character to replace.
---@param replacement string The replacement character.
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

---Get the prefix of a string.
---@param str string
---@param char string
---@return string
M.get_prefix = function(str, char)
	local prefix = string.match(str, "^[^" .. char .. "]*")
	return prefix
end

---Get the suffix of a string.
---@param str string
---@param prefix string
---@return boolean
local function has_prefix(str, prefix)
	return str:sub(1, #prefix) == prefix
end

---Check if a string has a suffix.
---@param str string
---@param suffix string
---@return boolean
local function has_suffix(str, suffix)
	return str == "" or str:sub(-#suffix) == suffix
end

---@param list neotest.Position[]
---@param prefix string
---@param suffix string
---@return neotest.Position?
local function find_element_by_id(list, prefix, suffix)
	for _, item in ipairs(list) do
		local a = has_prefix(item.id, prefix)
		local b = has_suffix(item.id, suffix)

		logger.debug("list.id: " .. item.id)
		logger.debug("predicate: " .. vim.inspect(a) .. " " .. vim.inspect(b))
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

---@param list neotest.Position[]
---@param class_name string
---@param test_name string
---@param cwd string
---@return neotest.Position?
M.find_position = function(list, class_name, test_name, cwd)
	local module, class = class_name:match("([^%.]+)%.([^%.]+)")
	if not module or not class then
		return nil
	end
	local prefix = cwd .. "/Tests/" .. module
	local suffix = separator .. class .. separator .. M.get_prefix(test_name, "(")

	logger.debug("prefix: " .. prefix)
	logger.debug("suffix: " .. suffix)

	return find_element_by_id(list, prefix, suffix)
end

---Returns the path to the Xcode app or nil.
---@return string?
M.get_xcode_path = function()
	local xcode_select = { "xcode-select", "-p" }
	local xcode_select_output = vim.system(xcode_select, { text = true }):wait()

	if xcode_select_output.code ~= 0 and xcode_select_output.stdout ~= nil then
		return nil
	end
	local stripped = string.gsub(xcode_select_output.stdout, "\n$", "")
	return stripped
end

return M
