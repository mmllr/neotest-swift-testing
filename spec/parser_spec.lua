describe("JSON Lines parser", function()
  local sut = require("neotest-swift-testing/parser")({ log_level = vim.log.levels.OFF })
  it("Parses empty lines", function()
    local result = sut.parse("")
    assert.is_nil(result)
  end)

  describe("Discovering", function()
    it("can parse test suites", function() end)
    local input = [[
{"kind":"test","payload":{"id":"GPXKitTests.ArrayExtensionsTests","kind":"suite","name":"ArrayExtensionsTests","sourceLocation":{"_filePath":"\/Users\/user\/folder\/GPXKit\/Tests\/GPXKitTests\/CollectionExtensionsTests.swift","column":2,"fileID":"GPXKitTests\/CollectionExtensionsTests.swift","line":11}},"version":0}
    ]]

    local result = sut.parse(input)

    ---@type SwiftTesting.TestRecord
    local actual = {
      kind = "test",
      payload = {
        id = "GPXKitTests.ArrayExtensionsTests",
        kind = "suite",
        name = "ArrayExtensionsTests",
        sourceLocation = {
          _filePath = "/Users/user/folder/GPXKit/Tests/GPXKitTests/CollectionExtensionsTests.swift",
          column = 2,
          fileID = "GPXKitTests/CollectionExtensionsTests.swift",
          line = 11,
        },
      },
      version = 0,
    }
    assert.are.same(actual, result)
  end)

  it("can parse test cases", function()
    local input = [[
{"kind":"test","payload":{"id":"GPXKitTests.GPXParserTests\/testTrackPointsDateWithFraction()\/GPXParserTests.swift:235:6","isParameterized":false,"kind":"function","name":"testTrackPointsDateWithFraction()","sourceLocation":{"_filePath":"\/Users\/user\/folder\/GPXKit\/Tests\/GPXKitTests\/GPXParserTests.swift","column":6,"fileID":"GPXKitTests\/GPXParserTests.swift","line":235}},"version":0}
  ]]

    local result = sut.parse(input)
    local actual = {
      kind = "test",
      version = 0,
      payload = {
        id = "GPXKitTests.GPXParserTests/testTrackPointsDateWithFraction()/GPXParserTests.swift:235:6",
        isParameterized = false,
        kind = "function",
        name = "testTrackPointsDateWithFraction()",
        sourceLocation = {
          _filePath = "/Users/user/folder/GPXKit/Tests/GPXKitTests/GPXParserTests.swift",
          column = 6,
          fileID = "GPXKitTests/GPXParserTests.swift",
          line = 235,
        },
      },
    }
    assert.are.same(actual, result)
  end)
end)
