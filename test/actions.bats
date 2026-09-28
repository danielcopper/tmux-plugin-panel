#!/usr/bin/env bats

setup() {
	load test_helper
	tpp_setup
	standard_env
}

teardown() {
	tpp_teardown
}

@test "an action writes to the terminal when its stdout is not the terminal" {
	# fzf before 0.53 gives an execute'd command fzf's own stdout, which the
	# panel sends to /dev/null.
	local panel
	panel=$(printf '%q' "$TPP_ROOT/scripts/panel.sh")
	run on_terminal "$panel clean >/dev/null 2>&1"
	[ "$status" -eq 0 ]
	[[ $output == *"Nothing to clean. Press any key"* ]]
}
