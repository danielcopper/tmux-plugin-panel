#!/usr/bin/env bats

setup() {
	load test_helper
	tpp_setup
	standard_env
}

teardown() {
	tpp_teardown
}

# declarations_from_home: tpp_declarations without anything outside $HOME
# (a system-wide /etc/tmux.conf may exist on the test machine).
declarations_from_home() {
	tpp_declarations | awk -F '\t' -v home="$HOME" 'index($2, home) == 1'
}

@test "declarations in tmux.conf and in the sourced panel file are found" {
	declare_plugin "someone/in-conf" "$TMUX_CONF"
	declare_plugin "someone/in-panel"
	load_lib
	run declarations_from_home
	[ "$status" -eq 0 ]
	local expected
	expected=$(printf 'someone/in-conf\t%s\nsomeone/in-panel\t%s' "$TMUX_CONF" "$PANEL_FILE")
	[ "$output" = "$expected" ]
}

@test "a file sourced with source and ~ is read, in both quoting styles" {
	mkdir -p "$HOME/extra"
	printf "source '~/extra/one.conf'\nsource-file -q \"~/extra/two.conf\"\n" >>"$TMUX_CONF"
	printf "set-option -g @plugin \"someone/one\"\n" >"$HOME/extra/one.conf"
	printf "  set -g @plugin 'someone/two#dev'\n" >"$HOME/extra/two.conf"
	load_lib
	run declarations_from_home
	[ "$status" -eq 0 ]
	[[ $output == *$'someone/one\t'"$HOME/extra/one.conf"* ]]
	[[ $output == *$'someone/two#dev\t'"$HOME/extra/two.conf"* ]]
}

@test "a file sourced only from a sourced file is not read (one level, like TPM)" {
	mkdir -p "$HOME/extra"
	printf "source-file %s\n" "$HOME/extra/nested.conf" >>"$PANEL_FILE"
	declare_plugin "someone/nested" "$HOME/extra/nested.conf"
	load_lib
	run declarations_from_home
	[[ $output != *someone/nested* ]]
}

@test "the panel list matches TPM's own plugin list" {
	mkdir -p "$HOME/extra"
	printf "source ~/extra/one.conf\n" >>"$TMUX_CONF"
	declare_plugin "someone/in-conf" "$TMUX_CONF"
	declare_plugin "someone/in-panel"
	declare_plugin "someone/in-extra#v2" "$HOME/extra/one.conf"
	load_lib
	local ours theirs
	ours=$(declarations_from_home | cut -f1 | sort)
	theirs=$(tpm_plugins_list_helper | grep . | sort)
	[ "$ours" = "$theirs" ]
}

@test "source lines with a trailing comment or several paths are split like TPM" {
	mkdir -p "$HOME/extra"
	{
		printf 'source-file -q ~/.config/tmux/plugins.conf  # plugins\n'
		printf 'source-file ~/extra/a.conf ~/extra/b.conf\n'
		printf "run '%s/tpm/tpm'\n" "$PLUGIN_DIR"
	} >"$TMUX_CONF"
	declare_plugin "someone/in-panel"
	declare_plugin "someone/in-a" "$HOME/extra/a.conf"
	declare_plugin "someone/in-b" "$HOME/extra/b.conf"
	load_lib
	cd "$TEST_ROOT"
	local ours theirs
	ours=$(declarations_from_home | cut -f1 | sort)
	theirs=$(tpm_plugins_list_helper | grep . | sort)
	[ "$ours" = "$(printf 'someone/in-a\nsomeone/in-b\nsomeone/in-panel')" ]
	[ "$ours" = "$theirs" ]
	tpp_panel_file_sourced
}

@test "the panel's own options are not read as plugin declarations" {
	{
		printf "set -g @tmux-plugin-panel-key 'M-p'\n"
		printf "set -g @tmux-plugin-panel-file '~/.config/tmux/plugins.conf'\n"
	} >>"$TMUX_CONF"
	declare_plugin "someone/real"
	load_lib
	local theirs
	theirs=$(tpm_plugins_list_helper | grep .)
	[ "$theirs" = "someone/real" ]
	run tpp_collect
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | cut -f1)" = "real" ]
}

@test "the panel file counts as sourced through another path to the same file" {
	mkdir -p "$TEST_ROOT/dotfiles"
	mv "$PANEL_FILE" "$TEST_ROOT/dotfiles/plugins.conf"
	ln -s "$TEST_ROOT/dotfiles/plugins.conf" "$PANEL_FILE"
	tmux set -g @tmux-plugin-panel-file "$TEST_ROOT/dotfiles/plugins.conf"
	load_lib
	tpp_panel_file_sourced
}

@test "a glob in a source line is expanded, as TPM does" {
	mkdir -p "$HOME/conf.d"
	printf "source-file -q ~/conf.d/*.conf\n" >>"$TMUX_CONF"
	declare_plugin "someone/one" "$HOME/conf.d/one.conf"
	declare_plugin "someone/two" "$HOME/conf.d/two.conf"
	load_lib
	local ours theirs
	ours=$(declarations_from_home | cut -f1 | sort)
	theirs=$(tpm_plugins_list_helper | grep . | sort)
	[[ $ours == *someone/one*someone/two* ]]
	[ "$ours" = "$theirs" ]
}

@test "a file sourced twice is read once" {
	printf 'source-file %s\n' "$PANEL_FILE" >>"$TMUX_CONF"
	declare_plugin "someone/in-panel"
	load_lib
	run declarations_from_home
	[ "$status" -eq 0 ]
	[ "$output" = "$(printf 'someone/in-panel\t%s' "$PANEL_FILE")" ]
}

@test "the panel file is reported as sourced only when tmux.conf sources it" {
	load_lib
	tpp_panel_file_sourced
	printf "run '%s/tpm/tpm'\n" "$PLUGIN_DIR" >"$TMUX_CONF"
	run tpp_panel_file_sourced
	[ "$status" -ne 0 ]
}

@test "the first declaration of a name wins and the plugin is listed once" {
	declare_plugin "someone/dup" "$TMUX_CONF"
	declare_plugin "otherfork/dup"
	load_lib
	run tpp_collect
	[ "$(printf '%s\n' "$output" | grep -c '^dup')" -eq 1 ]
	[[ $output == *$'\tsomeone/dup\t'"$TMUX_CONF"* ]]
}
