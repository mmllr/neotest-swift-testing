describe("Swift testing adapter", function()
  local sut = require("neotest-swift-testing")

  it("has a name", function()
    assert.is_equal("neotest-swift-testing", sut.name)
  end)

  it("has a valid root function", function()
    local path = vim.fn.getcwd() .. "/spec/fixtures/Sources"
    local expected = vim.fn.getcwd() .. "/spec/fixtures"
    local actual = sut.root(path)

    assert.is_equal(expected, actual)
  end)

  it("filters invalid directories", function()
    local root = vim.fn.getcwd() .. "/spec/fixtures/Sources"

    local invalid = { "Sources", "build", ".git", ".build", ".git", ".swiftpm" }

    for _, dir in ipairs(invalid) do
      local actual = sut.filter_dir(dir, "spec/fixtures/Sources", root)
      assert.is_false(actual)
    end
  end)

  it("does not filters test directories", function()
    local root = vim.fn.getcwd() .. "/spec/fixtures/Sources"

    local actual = sut.filter_dir("Tests", "spec/fixtures/", root)
    assert.is_true(actual)
  end)
end)
