#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	load test_helper
	tpp_setup
	standard_env
	unset GIT_CONFIG_COUNT
	# A credential helper that records every call.
	HELPER_LOG="$TEST_ROOT/helper-log"
	git config --global credential.helper "!f() { cat >/dev/null; echo \"\$1\" >>'$HELPER_LOG'; }; f"
}

teardown() {
	tpp_teardown
}

# An entry the user already has in the environment.
export_user_config_entry() {
	export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=tpp.kept GIT_CONFIG_VALUE_0=yes
}

# Hands a credential to git to store, as git does after a successful pull
# from a URL with credentials in it; git passes it to every helper.
store_credential() {
	printf 'protocol=https\nhost=example.com\nusername=git\npassword=\n\n' | git credential approve
}

@test "without the panel's git environment the test helper is called" {
	store_credential
	[ "$(cat "$HELPER_LOG")" = store ]
}

@test "git run with the panel's git environment calls no credential helper" {
	load_lib
	tpp_disable_credential_helpers
	[ "$GIT_CONFIG_COUNT" = 1 ]
	[ "$(git config --get credential.helper)" = "" ]
	store_credential
	[ ! -e "$HELPER_LOG" ]
}

@test "the panel's git environment keeps the entries already in GIT_CONFIG_COUNT" {
	export_user_config_entry
	load_lib
	tpp_disable_credential_helpers
	[ "$GIT_CONFIG_COUNT" = 2 ]
	[ "$(git config --get tpp.kept)" = yes ]
	[ "$(git config --get credential.helper)" = "" ]
	store_credential
	[ ! -e "$HELPER_LOG" ]
}

@test "the panel's git environment is added once" {
	load_lib
	tpp_disable_credential_helpers
	tpp_disable_credential_helpers
	[ "$GIT_CONFIG_COUNT" = 1 ]
	[ -z "${GIT_CONFIG_KEY_1+set}" ]
}

@test "TPM's scripts run by the panel call no credential helper" {
	# TPM's install, replaced by one that stores a credential.
	cat >"$PLUGIN_DIR/tpm/bin/install_plugins" <<'EOF'
#!/usr/bin/env bash
printf 'protocol=https\nhost=example.com\nusername=git\npassword=\n\n' | git credential approve
echo "stored"
EOF
	"$PLUGIN_DIR/tpm/bin/install_plugins"
	[ "$(cat "$HELPER_LOG")" = store ]
	rm "$HELPER_LOG"
	local panel
	panel=$(printf '%q' "$TPP_ROOT/scripts/panel.sh")
	run on_terminal "$panel install"
	[ "$status" -eq 0 ]
	[[ $output == *stored* ]]
	[ ! -e "$HELPER_LOG" ]
}
