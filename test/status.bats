#!/usr/bin/env bats

setup() {
	load test_helper
	tpp_setup
	standard_env
	make_remote alpha
}

teardown() {
	tpp_teardown
}

@test "an up-to-date plugin is current" {
	clone_plugin alpha
	declare_plugin "$(remote_url alpha)"
	load_lib
	tpp_fetch_all
	[ "$(status_of alpha)" = "✓" ]
}

@test "a plugin behind its upstream shows the commit count after a fetch" {
	clone_plugin alpha
	declare_plugin "$(remote_url alpha)"
	push_commit alpha
	push_commit alpha
	load_lib
	[ "$(status_of alpha)" = "✓" ]
	tpp_fetch_all
	[ "$(status_of alpha)" = "↓2" ]
}

@test "a plugin with local commits is ahead" {
	clone_plugin alpha
	declare_plugin "$(remote_url alpha)"
	printf 'local\n' >"$PLUGIN_DIR/alpha/local"
	git -C "$PLUGIN_DIR/alpha" add local
	git -C "$PLUGIN_DIR/alpha" commit -q -m local
	load_lib
	tpp_fetch_all
	[ "$(status_of alpha)" = "↑1" ]
}

@test "a diverged plugin shows both counts" {
	clone_plugin alpha
	declare_plugin "$(remote_url alpha)"
	printf 'local\n' >"$PLUGIN_DIR/alpha/local"
	git -C "$PLUGIN_DIR/alpha" add local
	git -C "$PLUGIN_DIR/alpha" commit -q -m local
	push_commit alpha
	load_lib
	tpp_fetch_all
	[ "$(status_of alpha)" = "↑1 ↓1" ]
}

@test "a declared plugin without a directory is not installed" {
	declare_plugin "$(remote_url alpha)"
	load_lib
	[ "$(status_of alpha)" = "not installed" ]
}

@test "a directory without a declaration is not declared, tpm is not listed" {
	clone_plugin alpha
	load_lib
	[ "$(status_of alpha)" = "not declared" ]
	run tpp_collect
	[ "$status" -eq 0 ]
	[[ $output != *tpm* ]]
}

@test "a detached HEAD is pinned" {
	clone_plugin alpha
	declare_plugin "$(remote_url alpha)"
	git -C "$PLUGIN_DIR/alpha" checkout -q --detach
	push_commit alpha
	load_lib
	tpp_fetch_all
	[ "$(status_of alpha)" = "pinned" ]
}

@test "a #branch declaration is pinned" {
	push_commit alpha dev
	clone_plugin alpha dev
	declare_plugin "$(remote_url alpha)#dev"
	load_lib
	tpp_fetch_all
	[ "$(status_of alpha)" = "pinned" ]
}

@test "a plain directory inside another repository is not a git repo" {
	git init -q "$XDG_CONFIG_HOME"
	mkdir -p "$PLUGIN_DIR/plain"
	touch "$PLUGIN_DIR/plain/plain.tmux"
	declare_plugin "someone/plain"
	load_lib
	[ "$(status_of plain)" = "not a git repo" ]
}

@test "records carry the age of the local HEAD commit and the declaration source" {
	clone_plugin alpha
	declare_plugin "$(remote_url alpha)"
	load_lib
	run tpp_collect
	[ "$status" -eq 0 ]
	local expected
	expected=$(printf 'alpha\t✓\t%s\t%s\t%s' "$(git -C "$PLUGIN_DIR/alpha" log -1 --format=%cr)" "$(remote_url alpha)" "$PANEL_FILE")
	[ "$output" = "$expected" ]
}

@test "the checking rows mark installed plugins as checking" {
	clone_plugin alpha
	declare_plugin "$(remote_url alpha)"
	declare_plugin "someone/missing"
	load_lib
	[ "$(tpp_collect_checking | awk -F '\t' '$1 == "alpha" { print $2 }')" = "checking…" ]
	[ "$(tpp_collect_checking | awk -F '\t' '$1 == "missing" { print $2 }')" = "not installed" ]
}

@test "fetch runs ssh in batch mode, keeping a configured ssh command" {
	clone_plugin alpha
	declare_plugin "$(remote_url alpha)"
	# The upload-pack command runs under the fetch's environment, so it can
	# record GIT_SSH_COMMAND for local remotes too.
	git -C "$PLUGIN_DIR/alpha" config remote.origin.uploadpack \
		"printf '%s\n' \"\$GIT_SSH_COMMAND\" >$TEST_ROOT/ssh-cmd; git-upload-pack"
	git -C "$PLUGIN_DIR/alpha" config core.sshCommand "ssh -i key"
	load_lib
	tpp_fetch_all
	[ "$(cat "$TEST_ROOT/ssh-cmd")" = "ssh -i key -o BatchMode=yes" ]
	GIT_SSH=/opt/my-ssh tpp_fetch_all
	[ "$(cat "$TEST_ROOT/ssh-cmd")" = "ssh -i key -o BatchMode=yes" ]
	git -C "$PLUGIN_DIR/alpha" config --unset core.sshCommand
	tpp_fetch_all
	[ "$(cat "$TEST_ROOT/ssh-cmd")" = "ssh -o BatchMode=yes" ]
	GIT_SSH="/opt/my ssh" tpp_fetch_all
	[ "$(cat "$TEST_ROOT/ssh-cmd")" = "/opt/my\\ ssh -o BatchMode=yes" ]
	GIT_SSH_COMMAND="ssh -v" GIT_SSH=/opt/my-ssh tpp_fetch_all
	[ "$(cat "$TEST_ROOT/ssh-cmd")" = "ssh -v -o BatchMode=yes" ]
}

@test "plink is not given ssh's -o option" {
	load_lib
	[ "$(GIT_SSH='C:/Program Files/PuTTY/plink.exe' tpp_ssh_command "$TEST_ROOT")" = 'C:/Program\ Files/PuTTY/plink.exe' ]
	[ "$(GIT_SSH_COMMAND='/usr/bin/tortoiseplink -batch' tpp_ssh_command "$TEST_ROOT")" = '/usr/bin/tortoiseplink -batch' ]
	[ "$(GIT_SSH_COMMAND='ssh -4' tpp_ssh_command "$TEST_ROOT")" = 'ssh -4 -o BatchMode=yes' ]
}

@test "a remote that does not answer is abandoned after the timeout" {
	clone_plugin alpha
	declare_plugin "$(remote_url alpha)"
	git -C "$PLUGIN_DIR/alpha" config remote.origin.uploadpack "sleep 20; git-upload-pack"
	load_lib
	# shellcheck disable=SC2034 # read by tpp_fetch_all from lib.sh
	TPP_FETCH_TIMEOUT=1
	local start=$SECONDS
	tpp_fetch_all
	[ $((SECONDS - start)) -lt 6 ]
	[ "$(status_of alpha)" = "✓" ]
}
