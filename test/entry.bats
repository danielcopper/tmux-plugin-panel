#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	load test_helper
	tpp_setup
	standard_env
}

teardown() {
	tpp_teardown
}

# binding_of <key>: the prefix-table binding line for <key>. (list-keys with a
# key argument prints nothing when stdout is not a terminal, so filter the
# full table instead.)
binding_of() {
	tmux list-keys -T prefix | awk -v k="$1" '$4 == k'
}

@test "the entry point binds P in the prefix table to the popup" {
	run "$TPP_ROOT/tmux-plugin-panel.tmux"
	[ "$status" -eq 0 ]
	run binding_of P
	[ "$status" -eq 0 ]
	[[ $output == *display-popup*-E*"$TPP_ROOT/scripts/panel.sh"* ]]
}

@test "@tmux-plugin-panel-key changes the key" {
	tmux set -g @tmux-plugin-panel-key M-p
	run "$TPP_ROOT/tmux-plugin-panel.tmux"
	[ "$status" -eq 0 ]
	run binding_of M-p
	[ "$status" -eq 0 ]
	[[ $output == *display-popup* ]]
}

@test "version checks" {
	# shellcheck source=scripts/lib.sh
	source "$TPP_ROOT/scripts/lib.sh"
	tpp_version_ge 3.2 3.2
	tpp_version_ge 3.10 3.2
	tpp_version_ge 0.44.1 0.36
	run ! tpp_version_ge 3.1 3.2
	run ! tpp_version_ge 0.35.9 0.36
	tpp_tmux_version_ok "tmux 3.2a"
	tpp_tmux_version_ok "tmux next-3.6"
	tpp_tmux_version_ok "tmux master"
	run ! tpp_tmux_version_ok "tmux 3.1c"
	run ! tpp_tmux_version_ok "tmux 2.9"
}

@test "panel.sh rows prints one fzf row per plugin, keyed by name" {
	make_remote alpha
	clone_plugin alpha
	declare_plugin "$(remote_url alpha)"
	declare_plugin "someone/missing"
	run "$TPP_ROOT/scripts/panel.sh" rows --fetch
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 2 ]
	[[ ${lines[0]} == alpha$'\t'alpha*✓* ]]
	[[ ${lines[1]} == missing$'\t'missing*"not installed"* ]]
}

@test "rows keep their columns when a record has no age" {
	make_remote alpha
	clone_plugin alpha
	declare_plugin "$(remote_url alpha)"
	declare_plugin "someone/missing"
	run bash -c 'source "$1/scripts/lib.sh"; tpp_init; tpp_collect_checking | tpp_format_rows' _ "$TPP_ROOT"
	[ "$status" -eq 0 ]
	[[ $output != *file://* ]]
	[[ $output != *someone/missing* ]]
	[[ ${lines[1]} == missing$'\t'missing*"not installed"*-* ]]
}

@test "panel.sh preview lists pending commits" {
	make_remote alpha
	clone_plugin alpha
	declare_plugin "$(remote_url alpha)"
	push_commit alpha
	run "$TPP_ROOT/scripts/panel.sh" rows --fetch
	run "$TPP_ROOT/scripts/panel.sh" preview alpha
	[ "$status" -eq 0 ]
	[[ $output == *"in        $PANEL_FILE"* ]]
	[[ $output == *"pending commits:"*"change on main"* ]]
}

@test "panel.sh preview of a missing plugin shows its repository URL" {
	declare_plugin "someone/missing#dev"
	run "$TPP_ROOT/scripts/panel.sh" preview missing
	[ "$status" -eq 0 ]
	[[ $output == *"repo      https://github.com/someone/missing"* ]]
	[[ $output == *"not installed"* ]]
}
