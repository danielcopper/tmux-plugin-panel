#!/usr/bin/env bats

setup() {
	load test_helper
	tpp_setup
	# A config outside the XDG and ~/.tmux locations, so the tests below
	# decide which of those exist.
	printf 'set -g status off\n' >"$TEST_ROOT/server.conf"
	# shellcheck source=scripts/lib.sh
	source "$TPP_ROOT/scripts/lib.sh"
}

teardown() {
	tpp_teardown
}

@test "TMUX_PLUGIN_MANAGER_PATH in the tmux environment wins" {
	mkdir -p "$(dirname "$TMUX_CONF")"
	touch "$TMUX_CONF"
	start_server "$TEST_ROOT/server.conf"
	tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "$TEST_ROOT/custom/"
	[ "$(tpp_plugin_dir)" = "$TEST_ROOT/custom/" ]
}

@test "the environment path gets ~ expanded and a trailing slash" {
	start_server "$TEST_ROOT/server.conf"
	# shellcheck disable=SC2088 # a literal ~ is the input under test
	tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "~/somewhere"
	[ "$(tpp_plugin_dir)" = "$HOME/somewhere/" ]
}

@test "without the variable, an XDG tmux.conf selects the XDG plugin directory" {
	mkdir -p "$(dirname "$TMUX_CONF")"
	touch "$TMUX_CONF"
	start_server "$TEST_ROOT/server.conf"
	[ "$(tpp_plugin_dir)" = "$XDG_CONFIG_HOME/tmux/plugins/" ]
}

@test "a custom XDG_CONFIG_HOME is honoured" {
	export XDG_CONFIG_HOME="$TEST_ROOT/xdg"
	mkdir -p "$XDG_CONFIG_HOME/tmux"
	touch "$XDG_CONFIG_HOME/tmux/tmux.conf"
	start_server "$TEST_ROOT/server.conf"
	[ "$(tpp_plugin_dir)" = "$TEST_ROOT/xdg/tmux/plugins/" ]
}

@test "without the variable or an XDG tmux.conf, ~/.tmux/plugins/ is used" {
	touch "$HOME/.tmux.conf"
	start_server "$TEST_ROOT/server.conf"
	[ "$(tpp_plugin_dir)" = "$HOME/.tmux/plugins/" ]
}

@test "the resolved directory is the one TPM sets when it runs" {
	standard_env
	local tpm_value
	tpm_value=$(tmux show-environment -g TMUX_PLUGIN_MANAGER_PATH)
	[ "$tpm_value" = "TMUX_PLUGIN_MANAGER_PATH=$PLUGIN_DIR/" ]
	[ "$(tpp_plugin_dir)" = "$PLUGIN_DIR/" ]
}

@test "the panel reports a missing TPM" {
	mkdir -p "$(dirname "$TMUX_CONF")"
	touch "$TMUX_CONF"
	start_server "$TEST_ROOT/server.conf"
	run tpp_init
	[ "$status" -ne 0 ]
	[[ $output == *"TPM not found in $PLUGIN_DIR/tpm"* ]]
}
