# shellcheck shell=bash
#
# Shared setup for the bats suite.
#
# Every test runs against its own tmux server on a private socket directory
# (TMUX_TMPDIR, kept short under /tmp because a socket path is limited to about
# 100 bytes) and socket name, with HOME and XDG_CONFIG_HOME pointing into a
# temporary directory. A `tmux` shim first on PATH adds `-L <socket>` to every
# call, so the panel, TPM's scripts and the tests all reach the test server and
# never the user's. Plugin remotes are local bare repositories reached through
# file:// URLs; GIT_ALLOW_PROTOCOL=file makes any other transport fail at once,
# so nothing touches the network.
#
# The suite needs a TPM checkout to copy from: set TPM_SRC to it.

TPP_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

tpp_setup() {
	if [[ -z ${TPM_SRC:-} || ! -f $TPM_SRC/scripts/helpers/plugin_functions.sh ]]; then
		echo "TPM_SRC must point to a TPM checkout (tmux-plugins/tpm)" >&2
		return 1
	fi

	REAL_TMUX=$(command -v tmux)
	TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/tpp.XXXXXX")
	SOCKET_ROOT=$(mktemp -d /tmp/tpp.XXXX)
	TEST_SOCKET="tpp-test-$$-$RANDOM"

	unset TMUX TMUX_PANE TMUX_PLUGIN_MANAGER_PATH GIT_SSH GIT_SSH_COMMAND
	export TMUX_TMPDIR="$SOCKET_ROOT"
	export HOME="$TEST_ROOT/home"
	export XDG_CONFIG_HOME="$HOME/.config"
	export GIT_CONFIG_NOSYSTEM=1
	export GIT_ALLOW_PROTOCOL=file
	export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
	export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
	# A fixed date keeps the relative age ("%cr") stable within a test.
	export GIT_AUTHOR_DATE="2020-01-01T00:00:00Z" GIT_COMMITTER_DATE="2020-01-01T00:00:00Z"
	mkdir -p "$HOME" "$TEST_ROOT/bin" "$TEST_ROOT/remotes" "$TEST_ROOT/work"

	printf '#!/bin/sh\nexec "%s" -L "%s" "$@"\n' "$REAL_TMUX" "$TEST_SOCKET" >"$TEST_ROOT/bin/tmux"
	chmod +x "$TEST_ROOT/bin/tmux"
	export PATH="$TEST_ROOT/bin:$PATH"

	git config --global init.defaultBranch main
	git config --global advice.detachedHead false

	PLUGIN_DIR="$XDG_CONFIG_HOME/tmux/plugins"
	TMUX_CONF="$XDG_CONFIG_HOME/tmux/tmux.conf"
	PANEL_FILE="$XDG_CONFIG_HOME/tmux/plugins.conf"
}

tpp_teardown() {
	if [[ -n ${TEST_ROOT:-} ]]; then
		"$REAL_TMUX" -L "$TEST_SOCKET" kill-server 2>/dev/null || true
		rm -rf "$TEST_ROOT"
	fi
	if [[ -n ${SOCKET_ROOT:-} ]]; then
		rm -rf "$SOCKET_ROOT"
	fi
}

# Copies TPM into the test plugin directory, without its git metadata so no
# test can reach its real remote.
install_tpm() {
	mkdir -p "$PLUGIN_DIR"
	cp -R "$TPM_SRC" "$PLUGIN_DIR/tpm"
	rm -rf "$PLUGIN_DIR/tpm/.git"
}

# Writes the default test config: sources the panel file, then runs TPM,
# which sets TMUX_PLUGIN_MANAGER_PATH on the server.
write_default_conf() {
	mkdir -p "$(dirname "$TMUX_CONF")"
	{
		printf 'source-file -q %s\n' "$PANEL_FILE"
		printf "run '%s/tpm/tpm'\n" "$PLUGIN_DIR"
	} >"$TMUX_CONF"
}

# start_server <config>
start_server() {
	tmux -f "$1" new-session -d -s test -x 120 -y 40
}

# Standard fixture: TPM installed, config written, server running.
standard_env() {
	install_tpm
	write_default_conf
	touch "$PANEL_FILE"
	start_server "$TMUX_CONF"
}

# make_remote <name>: creates a bare repository with one commit.
make_remote() {
	local name=$1 work="$TEST_ROOT/work/$1"
	git init -q --bare "$TEST_ROOT/remotes/$name.git"
	git init -q "$work"
	printf '#!/usr/bin/env bash\n' >"$work/$name.tmux"
	git -C "$work" add "$name.tmux"
	git -C "$work" commit -q -m "initial"
	git -C "$work" remote add origin "$TEST_ROOT/remotes/$name.git"
	git -C "$work" push -q origin HEAD:main
}

remote_url() {
	printf 'file://%s/remotes/%s.git\n' "$TEST_ROOT" "$1"
}

# push_commit <name> [<branch>]: adds a commit to the remote.
push_commit() {
	local name=$1 branch=${2:-main} work="$TEST_ROOT/work/$1"
	git -C "$work" checkout -q -B "$branch"
	printf '%s\n' "$RANDOM" >>"$work/change"
	git -C "$work" add change
	git -C "$work" commit -q -m "change on $branch"
	git -C "$work" push -q origin "HEAD:$branch"
}

# clone_plugin <name> [<branch>]: installs a plugin the way TPM does.
clone_plugin() {
	local name=$1 branch=${2-}
	mkdir -p "$PLUGIN_DIR"
	if [[ -n $branch ]]; then
		git clone -q -b "$branch" --single-branch "$(remote_url "$name")" "$PLUGIN_DIR/$name"
	else
		git clone -q --single-branch "$(remote_url "$name")" "$PLUGIN_DIR/$name"
	fi
}

declare_plugin() {
	printf "set -g @plugin '%s'\n" "$1" >>"${2:-$PANEL_FILE}"
}

# Loads the library the way panel.sh does.
load_lib() {
	# shellcheck source=scripts/lib.sh
	source "$TPP_ROOT/scripts/lib.sh"
	tpp_init
}

# status_of <name>: status column of one plugin from tpp_collect.
status_of() {
	tpp_collect | awk -F '\t' -v n="$1" '$1 == n { print $2 }'
}

# on_terminal <command>: runs the shell command <command> on a terminal of its
# own (a pty from util-linux script) and prints what the terminal showed. The
# terminal gets one key press as input, for the panel's "Press any key".
on_terminal() {
	printf x | SHELL=/bin/bash script -qec "$1" /dev/null
}
