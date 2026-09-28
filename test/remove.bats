#!/usr/bin/env bats

setup() {
	load test_helper
	tpp_setup
	standard_env
	make_remote alpha
	make_remote beta
}

teardown() {
	tpp_teardown
}

@test "remove deletes the panel file line and the plugin directory" {
	printf '# keep this comment\n' >"$PANEL_FILE"
	declare_plugin "$(remote_url alpha)"
	declare_plugin "$(remote_url beta)"
	clone_plugin alpha
	clone_plugin beta
	load_lib
	run tpp_remove alpha
	[ "$status" -eq 0 ]
	[ ! -e "$PLUGIN_DIR/alpha" ]
	[ -d "$PLUGIN_DIR/beta" ]
	local expected
	expected=$(printf "# keep this comment\nset -g @plugin '%s'" "$(remote_url beta)")
	[ "$(cat "$PANEL_FILE")" = "$expected" ]
}

@test "remove matches declarations by plugin name, including #branch and double quotes" {
	push_commit alpha dev
	printf 'set -g @plugin "%s#dev"\n' "$(remote_url alpha)" >"$PANEL_FILE"
	printf "set-option -g @plugin 'someone/alpha.git'\n" >>"$PANEL_FILE"
	declare_plugin "someone/alphabet"
	clone_plugin alpha dev
	load_lib
	run tpp_remove alpha
	[ "$status" -eq 0 ]
	[ "$(cat "$PANEL_FILE")" = "set -g @plugin 'someone/alphabet'" ]
	[ ! -e "$PLUGIN_DIR/alpha" ]
}

@test "a plugin declared outside the panel file is kept and the file is named" {
	declare_plugin "$(remote_url alpha)" "$TMUX_CONF"
	clone_plugin alpha
	load_lib
	local before
	before=$(cat "$TMUX_CONF")
	run tpp_remove alpha
	[ "$status" -ne 0 ]
	[[ $output == *"declared in $TMUX_CONF, remove the line there"* ]]
	[ -d "$PLUGIN_DIR/alpha" ]
	[ "$(cat "$TMUX_CONF")" = "$before" ]
}

@test "a plugin declared in both files is left alone, panel line included" {
	declare_plugin "$(remote_url alpha)" "$TMUX_CONF"
	declare_plugin "$(remote_url alpha)"
	clone_plugin alpha
	load_lib
	run tpp_remove alpha
	[ "$status" -ne 0 ]
	[[ $output == *"declared in $TMUX_CONF, remove the line there"* ]]
	[ "$(cat "$PANEL_FILE")" = "set -g @plugin '$(remote_url alpha)'" ]
	[ -d "$PLUGIN_DIR/alpha" ]
}

@test "tpm itself is refused" {
	declare_plugin "tmux-plugins/tpm"
	load_lib
	run tpp_remove tpm
	[ "$status" -ne 0 ]
	[[ $output == *"refusing to remove tpm"* ]]
	[ -f "$PLUGIN_DIR/tpm/tpm" ]
	[ "$(cat "$PANEL_FILE")" = "set -g @plugin 'tmux-plugins/tpm'" ]
}

@test "an undeclared directory is removed" {
	clone_plugin alpha
	load_lib
	run tpp_remove alpha
	[ "$status" -eq 0 ]
	[ ! -e "$PLUGIN_DIR/alpha" ]
}

@test "a symlinked plugin directory loses the link, its target stays" {
	clone_plugin alpha
	mv "$PLUGIN_DIR/alpha" "$TEST_ROOT/alpha-checkout"
	ln -s "$TEST_ROOT/alpha-checkout" "$PLUGIN_DIR/alpha"
	declare_plugin "$(remote_url alpha)"
	load_lib
	run tpp_remove alpha
	[ "$status" -eq 0 ]
	[ ! -e "$PLUGIN_DIR/alpha" ] && [ ! -L "$PLUGIN_DIR/alpha" ]
	[ -f "$TEST_ROOT/alpha-checkout/alpha.tmux" ]
}

@test "a dangling symlink in the plugin directory is removed" {
	mkdir -p "$PLUGIN_DIR"
	ln -s "$TEST_ROOT/gone" "$PLUGIN_DIR/ghost"
	load_lib
	run tpp_remove ghost
	[ "$status" -eq 0 ]
	[ "$output" = "removed ghost" ]
	[ ! -L "$PLUGIN_DIR/ghost" ]
}

@test "remove says so when there is nothing to remove" {
	load_lib
	run tpp_remove nosuchplugin
	[ "$status" -eq 0 ]
	[ "$output" = "nothing to remove for nosuchplugin" ]
}

@test "surrounding whitespace in a name is ignored" {
	clone_plugin alpha
	load_lib
	run tpp_remove "  alpha "
	[ "$status" -eq 0 ]
	[ "$output" = "removed alpha" ]
	[ ! -e "$PLUGIN_DIR/alpha" ]
}

@test "remove refuses to run without a plugin directory" {
	load_lib
	local bad
	for bad in "" "/"; do
		TPP_PLUGIN_DIR=$bad run tpp_remove alpha
		[ "$status" -ne 0 ]
		[[ $output == *"plugin directory is not set"* ]]
	done
}

@test "the panel file reached through another path still owns its lines" {
	mkdir -p "$TEST_ROOT/dotfiles"
	mv "$PANEL_FILE" "$TEST_ROOT/dotfiles/plugins.conf"
	ln -s "$TEST_ROOT/dotfiles/plugins.conf" "$PANEL_FILE"
	declare_plugin "$(remote_url alpha)"
	clone_plugin alpha
	tmux set -g @tmux-plugin-panel-file "$TEST_ROOT/dotfiles/plugins.conf"
	load_lib
	run tpp_remove alpha
	[ "$status" -eq 0 ]
	[ ! -s "$TEST_ROOT/dotfiles/plugins.conf" ]
	[ ! -e "$PLUGIN_DIR/alpha" ]
}

@test "names that leave the plugin directory are refused" {
	mkdir -p "$XDG_CONFIG_HOME/tmux/victim" "$PLUGIN_DIR/sub/inner"
	load_lib
	local name
	for name in "../victim" "sub/inner" "." ".." ""; do
		run tpp_remove "$name"
		[ "$status" -ne 0 ] || {
			echo "'$name' was accepted"
			return 1
		}
	done
	[ -d "$XDG_CONFIG_HOME/tmux/victim" ]
	[ -d "$PLUGIN_DIR/sub/inner" ]
	[ -f "$PLUGIN_DIR/tpm/tpm" ]
}

@test "a symlinked panel file stays a symlink" {
	mkdir -p "$TEST_ROOT/dotfiles"
	mv "$PANEL_FILE" "$TEST_ROOT/dotfiles/plugins.conf"
	ln -s "$TEST_ROOT/dotfiles/plugins.conf" "$PANEL_FILE"
	declare_plugin "$(remote_url alpha)"
	declare_plugin "$(remote_url beta)"
	load_lib
	run tpp_remove alpha
	[ "$status" -eq 0 ]
	[ -L "$PANEL_FILE" ]
	[ "$(cat "$TEST_ROOT/dotfiles/plugins.conf")" = "set -g @plugin '$(remote_url beta)'" ]
}

@test "remove never writes when the panel file option points at tmux.conf" {
	declare_plugin "$(remote_url alpha)" "$TMUX_CONF"
	clone_plugin alpha
	tmux set -g @tmux-plugin-panel-file "$TMUX_CONF"
	load_lib
	local before
	before=$(cat "$TMUX_CONF")
	run tpp_remove alpha
	[ "$status" -ne 0 ]
	[ "$(cat "$TMUX_CONF")" = "$before" ]
	[ -d "$PLUGIN_DIR/alpha" ]
}
