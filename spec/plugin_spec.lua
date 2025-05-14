describe("Swift testing adapter", function()
  local sut = require("neotest-swift-testing")

  it("Has a name", function()
    assert.is_equal("neotest-swift-testing", sut.name)
  end)

  it("Has a valid root function", function()
    local path = vim.fn.getcwd() .. "/spec/fixtures/Sources"
    local expected = vim.fn.getcwd() .. "/spec/fixtures"
    local actual = sut.root(path)

    assert.is_equal(expected, actual)
  end)

  it("Filters invalid directories", function()
    local root = vim.fn.getcwd() .. "/spec/fixtures/Sources"

    local invalid = { "Sources", "build", ".git", ".build", ".git", ".swiftpm" }

    for _, dir in ipairs(invalid) do
      local actual = sut.filter_dir(dir, "spec/fixtures/Sources", root)
      assert.is_false(actual)
    end
  end)

  it("Does not filters test directories", function()
    assert.is_true(sut.filter_dir("Tests", "spec/fixtures/", vim.fn.getcwd()))
    assert.is_false(sut.filter_dir("Sources", "spec/fixtures/", vim.fn.getcwd()))
  end)

  it("Accepts test files", function()
    for _, name in ipairs({ "Test.swift", "Tests/Test.swift", "FeatureTests.swift" }) do
      assert.is_true(sut.is_test_file(name), "expected " .. name .. " to be a test file")
    end
  end)

  it("Filters non test files", function()
    for _, name in ipairs({
      "Source.swift",
      "Feature.swift",
      "main.swift",
      "main.c",
      "header.h",
      "objc.m",
      "Package.swift",
      "Makefile",
    }) do
      assert.is_false(sut.is_test_file(name), "expected " .. name .. " to be a test file")
    end
  end)
end)
