-- https://github.com/fredrikaverpil/neotest-golang/blob/main/lua/neotest-golang/logging.lua

local Logger = {}
local prefix = "[neotest-swift-testing]"

local logger

local log_date_format = "%FT%H:%M:%SZ%z"
---@param opts table
---@return neotest.Logger
function Logger.new(opts)
  opts = opts or {}
  if logger then
    return logger
  end
  logger = {}
  setmetatable(logger, { __index = Logger })
  logger = logger

  logger._level = opts.log_level or vim.log.levels.DEBUG

  for level, levelnr in pairs(vim.log.levels) do
    logger[level:lower()] = function(...)
      local argc = select("#", ...)
      if levelnr < logger._level then
        return false
      end
      if argc == 0 then
        return true
      end
      local info = debug.getinfo(2, "Sl")
      local fileinfo = string.format("%s:%s", info.short_src, info.currentline)
      local parts = {
        table.concat({ prefix, level, os.date(log_date_format), fileinfo }, "|"),
      }
      if _G._NEOTEST_IS_CHILD then
        table.insert(parts, "CHILD |")
      end
      for i = 1, argc do
        local arg = select(i, ...)
        if arg == nil then
          table.insert(parts, "<nil>")
        elseif type(arg) == "string" then
          table.insert(parts, arg)
        elseif type(arg) == "table" and arg.__tostring then
          table.insert(parts, arg.__tostring(arg))
        else
          table.insert(parts, vim.inspect(arg))
        end
      end
      -- TODO: Add a log file
      vim.print(table.concat(parts, " "))
    end
  end
  return logger
end

function Logger:set_level(level)
  self._level = level
end

return Logger.new({})
