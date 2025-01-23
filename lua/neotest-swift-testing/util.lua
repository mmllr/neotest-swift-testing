local ok, async = pcall(require, "nio")
if not ok then
  async = require("neotest.async")
end
local logger = require("neotest-swift-testing.logging")
local M = {}
local separator = "::"

---Check if a file exists.
---@async
---@param file string The file path.
---@return boolean True if the file exists, false otherwise.
M.file_exists = function(file)
  local err, tbl = async.uv.fs_stat(file)
  return tbl ~= nil
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

---@param list neotest.Position[]
---@param prefix string
---@param suffix string
---@return neotest.Position?
local function find_element_by_id(list, prefix, suffix)
  for _, item in ipairs(list) do
    local a = vim.startswith(item.id, prefix)
    local b = vim.endswith(item.id, suffix)

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

return M
