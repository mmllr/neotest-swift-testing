rockspec_format = "3.0"
package = "neotest-swift-testing"
version = "scm-1"

description = {
	summary = "A plugin for running Swift Test with neotest in Neovim.",
	homepage = "https://codeberg.org/mmllr/neotest-swift-testing",
	license = "MIT",
	labels = { "neovim", "swift", "test", "neotest" },
}

source = {
	url = "git+https://github.com/mmllr/neotest-swift-testing",
}

dependencies = {
	"lua >= 5.1",
	"nvim-nio",
	"neotest",
	"plenary.nvim",
}

test_dependencies = {
	"nlua",
	"busted",
	"luassert",
}

test = {
	type = "busted",
}

build = {
	type = "builtin",
	copy_directories = {
		-- Add runtimepath directories, like
		-- 'plugin', 'ftplugin', 'doc'
		-- here. DO NOT add 'lua' or 'lib'.
	},
}
