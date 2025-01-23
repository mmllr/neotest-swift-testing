rockspec_format = "3.0"
package = "neotest-swift-testing"
version = "scm-1"
source = {
	url = "git+https://github.com/mmllr/neotest-swift-testing",
}
dependencies = {
	"lua >= 5.1",
	"nvim-nio",
}
test_dependencies = {
	"nlua",
	"busted",
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
