#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

DIM=$'\033[2m' BOLD=$'\033[1m' RESET=$'\033[0m'

setup() {
	load test_helper
	tpp_setup
	standard_env
	make_remote alpha
	make_remote beta
	clone_plugin alpha
	clone_plugin beta
	# Declared as owner/repo, the way the list shows them; the clones pull
	# from their local remotes.
	declare_plugin someone/alpha
	declare_plugin someone/beta
}

teardown() {
	tpp_teardown
}

# short <name>: the short commit checked out in plugin <name>.
short() {
	git -C "$PLUGIN_DIR/$1" rev-parse --short HEAD
}

# update <arg>...: what the panel's update does, without the spinner: records
# the plugins' commits, runs TPM's update with its output in a file, and
# prints the summary.
update() {
	load_lib
	tpp_update_heads "$@" >"$TEST_ROOT/heads"
	local rc=0
	"$PLUGIN_DIR/tpm/bin/update_plugins" "$@" >"$TEST_ROOT/log" 2>&1 || rc=$?
	tpp_update_summary "$TEST_ROOT/heads" "$TEST_ROOT/log" "$rc"
}

@test "the update summary shows the new commit of a moved plugin and the up-to-date ones" {
	local old
	old=$(short alpha)
	push_commit alpha
	run update alpha beta
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = "${DIM}someone/${RESET}${BOLD}alpha${RESET}  $old → $(short alpha)" ]
	[ "${lines[1]}" = "${DIM}someone/${RESET}${BOLD}beta${RESET}   already up to date" ]
	[ "$old" != "$(short alpha)" ]
}

@test "the update summary leaves TPM's output out when nothing failed" {
	push_commit alpha
	run update all
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 2 ]
	[[ $output != *"update success"* ]]
	[[ $(cat "$TEST_ROOT/log") == *"update success"* ]]
}

@test "the update summary lists the plugins sorted by name, aligned" {
	make_remote a-plugin-with-a-long-name
	clone_plugin a-plugin-with-a-long-name
	declare_plugin someone/a-plugin-with-a-long-name
	run update beta alpha a-plugin-with-a-long-name
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	local i visible
	local -a names=(someone/a-plugin-with-a-long-name someone/alpha someone/beta)
	for i in 0 1 2; do
		visible=$(printf '%s' "${lines[i]}" | sed $'s/\033\\[[0-9;]*m//g')
		[[ $visible == "${names[i]}"* ]]
		[ "${visible:${#names[0]}+2}" = "already up to date" ]
	done
}

@test "a plugin whose update fails is reported, with TPM's output below" {
	push_commit alpha
	rm -rf "$TEST_ROOT/remotes/beta.git"
	local old
	old=$(short alpha)
	run update all
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "${DIM}someone/${RESET}${BOLD}alpha${RESET}  $old → $(short alpha)" ]
	[ "${lines[1]}" = "${DIM}someone/${RESET}${BOLD}beta${RESET}   update failed" ]
	[ "$output" = "${lines[0]}"$'\n'"${lines[1]}"$'\n\n'"$(cat "$TEST_ROOT/log")" ]
	[[ $output == *'"beta" update fail'* ]]
	[[ $output == *'"alpha" update success'* ]]
}

@test "when TPM's update exits with an error, the plugins it did not move are reported as failed" {
	cat >"$PLUGIN_DIR/tpm/bin/update_plugins" <<'EOF2'
#!/usr/bin/env bash
echo "FATAL: something went wrong" >&2
exit 1
EOF2
	run update alpha
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "${DIM}someone/${RESET}${BOLD}alpha${RESET}  update failed" ]
	[ "${lines[1]}" = "FATAL: something went wrong" ]
}

@test "a plugin that is not installed is reported as failed" {
	declare_plugin someone/gamma
	run update beta gamma
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "${DIM}someone/${RESET}${BOLD}beta${RESET}   already up to date" ]
	[ "${lines[1]}" = "${DIM}someone/${RESET}${BOLD}gamma${RESET}  update failed" ]
	[[ $output == *"gamma not installed!"* ]]
}

@test "an update of all plugins leaves out the ones that are not installed" {
	declare_plugin someone/gamma
	run update all
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 2 ]
	[[ $output != *gamma* ]]
}

@test "panel.sh update shows a spinner, then the summary" {
	push_commit alpha
	local panel old
	old=$(short alpha)
	panel=$(printf '%q' "$TPP_ROOT/scripts/panel.sh")
	run on_terminal "$panel update alpha beta"
	[ "$status" -eq 0 ]
	[[ $output == *"Updating 2 plugins ⠋"*$'\r\033[K'"${DIM}someone/${RESET}${BOLD}alpha${RESET}  $old → $(short alpha)"$'\r\n'"${DIM}someone/${RESET}${BOLD}beta${RESET}   already up to date"$'\r\n'* ]]
	[[ $output != *"update success"* ]]
}
