#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# The styles of a name in the list and the preview title.
DIM=$'\033[2m' BOLD=$'\033[1m' RESET=$'\033[0m'

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
	[[ ${lines[0]} == alpha$'\t'"$(remote_url alpha) "*✓* ]]
	[[ ${lines[1]} == missing$'\t'"${DIM}someone/${RESET}${BOLD}missing${RESET} "*"not installed"* ]]
}

@test "rows keep their columns when a record has no age" {
	make_remote alpha
	clone_plugin alpha
	declare_plugin "$(remote_url alpha)"
	declare_plugin "someone/missing"
	run bash -c 'source "$1/scripts/lib.sh"; tpp_init; tpp_collect_checking | tpp_format_rows' _ "$TPP_ROOT"
	[ "$status" -eq 0 ]
	[[ $output != *"$PANEL_FILE"* ]]
	[[ ${lines[1]} == missing$'\t'"${DIM}someone/${RESET}${BOLD}missing${RESET} "*"not installed"*$'\033[2m-\033[0m' ]]
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

@test "a declaration is shown as owner/repo, other URLs as declared, without #branch" {
	# shellcheck source=scripts/lib.sh
	source "$TPP_ROOT/scripts/lib.sh"
	[ "$(tpp_display_name someone/alpha)" = someone/alpha ]
	[ "$(tpp_display_name someone/alpha#dev)" = someone/alpha ]
	[ "$(tpp_display_name https://github.com/someone/alpha)" = someone/alpha ]
	[ "$(tpp_display_name https://github.com/someone/alpha.git#v1.0)" = someone/alpha ]
	[ "$(tpp_display_name git@github.com:someone/alpha.git)" = someone/alpha ]
	[ "$(tpp_display_name https://gitlab.com/someone/alpha.git)" = https://gitlab.com/someone/alpha.git ]
	[ "$(tpp_display_name https://gitlab.com/someone/alpha.git#dev)" = https://gitlab.com/someone/alpha.git ]
	[ "$(tpp_display_name git@gitlab.com:someone/alpha.git)" = git@gitlab.com:someone/alpha.git ]
}

@test "rows show the declared name, keyed by directory, in one aligned column" {
	declare_plugin tmux-plugins/tpm
	declare_plugin someone/alpha
	declare_plugin "someone/beta#dev"
	declare_plugin https://github.com/someone/gamma.git
	declare_plugin "https://gitlab.com/someone/delta.git#dev"
	mkdir -p "$PLUGIN_DIR/orphan"
	run "$TPP_ROOT/scripts/panel.sh" rows
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 6 ]
	# owner/repo: the owner dim, the repo bold; a directory without a
	# declaration: bold; any other URL: plain.
	[[ ${lines[0]} == alpha$'\t'"${DIM}someone/${RESET}${BOLD}alpha${RESET} "*"not installed"* ]]
	[[ ${lines[1]} == beta$'\t'"${DIM}someone/${RESET}${BOLD}beta${RESET} "*"not installed"* ]]
	[[ ${lines[2]} == delta$'\t'"https://gitlab.com/someone/delta.git "*"not installed"* ]]
	[[ ${lines[3]} == gamma$'\t'"${DIM}someone/${RESET}${BOLD}gamma${RESET} "*"not installed"* ]]
	[[ ${lines[4]} == orphan$'\t'"${BOLD}orphan${RESET} "*"not declared"* ]]
	[[ ${lines[5]} == tpm$'\t'"${DIM}tmux-plugins/${RESET}${BOLD}tpm${RESET} "* ]]
	# Without the escapes, every status starts two columns after the longest
	# name.
	local i visible expected longest=https://gitlab.com/someone/delta.git
	local -a names=(someone/alpha someone/beta "$longest" someone/gamma orphan tmux-plugins/tpm)
	for i in "${!lines[@]}"; do
		visible=$(printf '%s' "${lines[i]#*$'\t'}" | sed $'s/\033\\[[0-9;]*m//g')
		printf -v expected '%-*s' $((${#longest} + 2)) "${names[i]}"
		[ "${visible:0:${#expected}}" = "$expected" ]
		[[ ${visible:${#expected}:1} != ' ' ]]
	done
}

@test "panel.sh preview is titled with the list's name, styled the same" {
	declare_plugin "someone/alpha#dev"
	declare_plugin https://gitlab.com/someone/beta.git
	mkdir -p "$PLUGIN_DIR/orphan"
	run "$TPP_ROOT/scripts/panel.sh" preview alpha
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "${DIM}someone/${RESET}${BOLD}alpha${RESET}" ]
	run "$TPP_ROOT/scripts/panel.sh" preview beta
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = https://gitlab.com/someone/beta.git ]
	run "$TPP_ROOT/scripts/panel.sh" preview orphan
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "${BOLD}orphan${RESET}" ]
}

@test "panel.sh preview shows TPM's clone URL without its git::@ userinfo" {
	make_remote alpha
	clone_plugin alpha
	declare_plugin someone/alpha
	git -C "$PLUGIN_DIR/alpha" remote set-url origin https://git::@github.com/someone/alpha
	run "$TPP_ROOT/scripts/panel.sh" preview alpha
	[ "$status" -eq 0 ]
	[[ $output == *"repo      https://github.com/someone/alpha"$'\n'* ]]
	[[ $output != *git::@* ]]
	git -C "$PLUGIN_DIR/alpha" remote set-url origin https://someone@example.com/alpha.git
	run "$TPP_ROOT/scripts/panel.sh" preview alpha
	[ "$status" -eq 0 ]
	[[ $output == *"repo      https://someone@example.com/alpha.git"$'\n'* ]]
	git -C "$PLUGIN_DIR/alpha" remote set-url origin https://git::@example.com/x
	run "$TPP_ROOT/scripts/panel.sh" preview alpha
	[ "$status" -eq 0 ]
	[[ $output == *"repo      https://git::@example.com/x"$'\n'* ]]
}
