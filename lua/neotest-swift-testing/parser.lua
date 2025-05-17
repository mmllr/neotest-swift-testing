local logger = require("neotest-swift-testing.logging")
local M = {}

---@class SwiftTesting.SourceLocation
---@field _filePath string
---@field fileID string
---@field line number
---@field column number

---@alias SwiftTesting.Instant "absolute" | "since1970"

---@alias SwiftTesting.RecordType "test" | "event"

---@alias SwiftTesting.TestType "suite" | "function"

---@class SwiftTesting.TestSuite
---@field id string
---@field kind SwiftTesting.TestType
---@field sourceLocation SwiftTesting.SourceLocation
---@field name string
---@field diplayName? string

---@class SwiftTesting.TestFunction
---@field id string
---@field kind SwiftTesting.TestType
---@field sourceLocation SwiftTesting.SourceLocation
---@field name string
---@field displayName? string
---@field isParameterized boolean

---@class SwiftTesting.TestRecord
---@field version number
---@field kind SwiftTesting.RecordType
---@field payload SwiftTesting.TestSuite | SwiftTesting.TestFunction

---@alias SwiftTesting.EventKind "runStarted" | "testStarted" | "testCaseStarted" | "issueRecorded" | "testCaseEnded" | "testEnded" | "testSkipped" | "runEnded" | "valueAttached"

---@class SwiftTesting.MessageSymbol "default" | "skip" | "pass" | "passWithKnownIssue" | "fail" | "difference" | "warning" | "details"

---@class SwiftTesting.Message
---@field symbol SwiftTesting.MessageSymbol
---@field text string

---@class SwiftTesting.Issue
---@field isKnown boolean
---@field sourceLocation? SwiftTesting.SourceLocation

---@class SwiftTesting.Attachment
---@field path string

---@class SwiftTesting.Event
---@field kind SwiftTesting.EventKind
---@field instant SwiftTesting.Instant
---@field messages SwiftTesting.Message[]
---@field issue? SwiftTesting.Issue
---@field attachment? SwiftTesting.Attachment
---@field testID? string

---@param line string
---@return SwiftTesting.TestRecord|SwiftTesting.Event|nil
function M.parse(line)
  local status, result = pcall(function()
    return vim.json.decode(line)
  end)

  if not status then
    logger.error(string.format("Failed to parse JSON on line %s", result))
    return nil
  end

  return result
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
