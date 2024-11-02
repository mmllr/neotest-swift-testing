local M = {}

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

M.trim_up_to_prefix = function(str, char)
	local pattern = "^[^" .. char .. "]*" .. char
	return string.gsub(str, pattern, "")
end

M.get_prefix = function(str, char)
	local prefix = string.match(str, "^[^" .. char .. "]*")
	return prefix
end

return M
