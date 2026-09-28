#!/usr/bin/env bats

setup() {
	load test_helper
	tpp_setup
	standard_env
	load_lib
}

teardown() {
	tpp_teardown
}

assert_normalizes() {
	run tpp_normalize_spec "$1"
	[ "$status" -eq 0 ] || {
		echo "'$1' was refused: $output"
		return 1
	}
	[ "$output" = "$2" ] || {
		echo "'$1' became '$output', expected '$2'"
		return 1
	}
}

assert_refused() {
	run tpp_normalize_spec "$1"
	[ "$status" -ne 0 ] || {
		echo "'$1' was accepted as '$output'"
		return 1
	}
}

@test "owner/repo and GitHub URLs normalise to owner/repo" {
	assert_normalizes "tmux-plugins/tmux-sensible" "tmux-plugins/tmux-sensible"
	assert_normalizes "  tmux-plugins/tmux-sensible  " "tmux-plugins/tmux-sensible"
	assert_normalizes "tmux-plugins/tmux-sensible.git" "tmux-plugins/tmux-sensible"
	assert_normalizes "https://github.com/tmux-plugins/tmux-sensible" "tmux-plugins/tmux-sensible"
	assert_normalizes "https://github.com/tmux-plugins/tmux-sensible.git" "tmux-plugins/tmux-sensible"
	assert_normalizes "https://github.com/tmux-plugins/tmux-sensible/" "tmux-plugins/tmux-sensible"
	assert_normalizes "https://www.github.com/tmux-plugins/tmux-sensible" "tmux-plugins/tmux-sensible"
	assert_normalizes "git@github.com:tmux-plugins/tmux-sensible.git" "tmux-plugins/tmux-sensible"
	assert_normalizes "ssh://git@github.com/tmux-plugins/tmux-sensible.git" "tmux-plugins/tmux-sensible"
	assert_normalizes "github.com/tmux-plugins/tmux-sensible" "tmux-plugins/tmux-sensible"
}

@test "a #branch suffix is kept" {
	assert_normalizes "tmux-plugins/tmux-sensible#dev" "tmux-plugins/tmux-sensible#dev"
	assert_normalizes "https://github.com/tmux-plugins/tmux-sensible.git#v1.0" "tmux-plugins/tmux-sensible#v1.0"
	assert_normalizes "git@gitlab.com:someone/plugin.git#main" "git@gitlab.com:someone/plugin.git#main"
}

@test "other git URLs are kept as they are" {
	assert_normalizes "https://gitlab.com/someone/plugin.git" "https://gitlab.com/someone/plugin.git"
	assert_normalizes "git@gitlab.com:someone/plugin.git" "git@gitlab.com:someone/plugin.git"
	assert_normalizes "file:///srv/git/plugin.git" "file:///srv/git/plugin.git"
}

@test "malformed input is refused" {
	assert_refused ""
	assert_refused "   "
	assert_refused "plugin"
	assert_refused "a/b/c"
	assert_refused "owner/re po"
	assert_refused "owner/repo'"
	assert_refused 'owner/repo"'
	assert_refused "owner/repo;rm"
	assert_refused "owner/repo#"
	assert_refused "owner/repo#a#b"
	assert_refused "https://github.com/owner"
	assert_refused "https://github.com/owner/repo/tree/main"
}

@test "add creates the panel file and appends the declaration" {
	rm -f "$PANEL_FILE"
	run tpp_add "https://github.com/tmux-plugins/tmux-sensible.git"
	[ "$status" -eq 0 ]
	[ "$output" = "tmux-plugins/tmux-sensible" ]
	[ "$(cat "$PANEL_FILE")" = "set -g @plugin 'tmux-plugins/tmux-sensible'" ]
}

@test "add creates a missing parent directory" {
	tmux set -g @tmux-plugin-panel-file "$TEST_ROOT/elsewhere/deep/plugins.conf"
	load_lib
	run tpp_add "someone/plugin"
	[ "$status" -eq 0 ]
	[ "$(cat "$TEST_ROOT/elsewhere/deep/plugins.conf")" = "set -g @plugin 'someone/plugin'" ]
}

@test "add appends after existing lines, also without a final newline" {
	printf '# my plugins\nset -g @plugin %s' "'someone/first'" >"$PANEL_FILE"
	run tpp_add "someone/second"
	[ "$status" -eq 0 ]
	local expected
	expected=$(printf "# my plugins\nset -g @plugin 'someone/first'\nset -g @plugin 'someone/second'")
	[ "$(cat "$PANEL_FILE")" = "$expected" ]
}

@test "add refuses a plugin already declared in the panel file" {
	declare_plugin "tmux-plugins/tmux-sensible"
	local before
	before=$(cat "$PANEL_FILE")
	run tpp_add "git@github.com:tmux-plugins/tmux-sensible.git"
	[ "$status" -ne 0 ]
	[[ $output == *"already declared"* ]]
	[ "$(cat "$PANEL_FILE")" = "$before" ]
}

@test "add refuses a plugin already declared in tmux.conf" {
	declare_plugin "someone/plugin" "$TMUX_CONF"
	run tpp_add "otherfork/plugin"
	[ "$status" -ne 0 ]
	[[ $output == *"already declared"*"$TMUX_CONF"* ]]
	[ ! -s "$PANEL_FILE" ]
}

@test "add refuses to write when the panel file option points at tmux.conf" {
	tmux set -g @tmux-plugin-panel-file "$TMUX_CONF"
	load_lib
	local before
	before=$(cat "$TMUX_CONF")
	run tpp_add "someone/plugin"
	[ "$status" -ne 0 ]
	[[ $output == *"never edits the tmux config"* ]]
	[ "$(cat "$TMUX_CONF")" = "$before" ]
}

@test "the panel file option is honoured and ~ is expanded" {
	# shellcheck disable=SC2088 # a literal ~ is the input under test
	tmux set -g @tmux-plugin-panel-file "~/custom/plugins.conf"
	load_lib
	[ "$TPP_PANEL_FILE" = "$HOME/custom/plugins.conf" ]
}

@test "an added plugin is installed by TPM through the sourced panel file" {
	make_remote alpha
	run tpp_add "$(remote_url alpha)"
	[ "$status" -eq 0 ]
	run "$PLUGIN_DIR/tpm/bin/install_plugins"
	[ "$status" -eq 0 ]
	[ -d "$PLUGIN_DIR/alpha/.git" ]
	[ "$(status_of alpha)" = "✓" ]
}
