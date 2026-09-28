#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	load test_helper
	tpp_setup
	standard_env
}

teardown() {
	# Processes a failed test left running (see alive below).
	if [[ -f ${TEST_ROOT:-}/pids ]]; then
		local pid
		while read -r pid; do
			kill "$pid" 2>/dev/null || true
		done < <(alive "$TEST_ROOT/pids")
	fi
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

# alive <pid-file>: prints the processes listed in <pid-file> that still run.
alive() {
	local pid
	while read -r pid; do
		kill -0 "$pid" 2>/dev/null && printf '%s\n' "$pid"
	done <"$1"
	return 0
}

@test "the spinner shows its message while the command runs, then clears its line" {
	load_lib
	run tpp_spin "Working" "$TEST_ROOT/log" bash -c 'echo out; echo err >&2; sleep 0.3'
	[ "$status" -eq 0 ]
	[[ $output == $'\r'"Working ⠋"* ]]
	[[ $output == *$'\r\033[K' ]]
	[ "$(cat "$TEST_ROOT/log")" = $'out\nerr' ]
}

@test "the spinner returns the command's status and leaves no process behind" {
	cat >"$TEST_ROOT/fail" <<'EOF2'
#!/usr/bin/env bash
echo $$ >"$1/pids"
sleep 0.2
exit 3
EOF2
	chmod +x "$TEST_ROOT/fail"
	load_lib
	run tpp_spin "Working" "$TEST_ROOT/log" "$TEST_ROOT/fail" "$TEST_ROOT"
	[ "$status" -eq 3 ]
	[[ $output == *$'\r\033[K' ]]
	[ -z "$(alive "$TEST_ROOT/pids")" ]
}

@test "Ctrl-C stops the spinner, the command and everything it started" {
	# The command starts two more processes and records all three.
	cat >"$TEST_ROOT/busy" <<'EOF2'
#!/usr/bin/env bash
sleep 300 &
echo $! >>"$1/pids"
sleep 300 &
echo $! >>"$1/pids"
echo $$ >>"$1/pids"
wait
EOF2
	chmod +x "$TEST_ROOT/busy"
	# A terminal sends Ctrl-C's SIGINT to its foreground process group: the
	# spinner runs in a process group of its own here (set -m), so that it
	# can be sent the same way. Without it the shell would start the
	# background job with SIGINT ignored.
	set -m
	bash -c 'source "$1/scripts/lib.sh"; tpp_spin Working "$2/log" "$2/busy" "$2"; echo "status $?"' \
		_ "$TPP_ROOT" "$TEST_ROOT" >"$TEST_ROOT/out" 2>&1 3>&- &
	local pid=$!
	set +m
	for _ in $(seq 50); do
		[[ -f $TEST_ROOT/pids && $(wc -l <"$TEST_ROOT/pids") -eq 3 ]] && break
		sleep 0.1
	done
	[ "$(alive "$TEST_ROOT/pids" | wc -l)" -eq 3 ]
	kill -INT -- "-$pid"
	for _ in $(seq 50); do
		kill -0 "$pid" 2>/dev/null || break
		sleep 0.1
	done
	run ! kill -0 "$pid"
	wait "$pid"
	[ -z "$(alive "$TEST_ROOT/pids")" ]
	run cat "$TEST_ROOT/out"
	[[ $output == $'\r'"Working "* ]]
	[[ $output == *$'\r\033[K'"status 130" ]]
}

# slow_tpm <script>: makes TPM's bin/<script> take a moment, so that the
# spinner shows.
slow_tpm() {
	mv "$PLUGIN_DIR/tpm/bin/$1" "$PLUGIN_DIR/tpm/bin/$1.real"
	cat >"$PLUGIN_DIR/tpm/bin/$1" <<'EOF2'
#!/usr/bin/env bash
sleep 0.3
exec "$0.real" "$@"
EOF2
	chmod +x "$PLUGIN_DIR/tpm/bin/$1"
}

@test "install runs TPM behind a spinner, then shows TPM's output" {
	make_remote alpha
	declare_plugin "$(remote_url alpha)"
	slow_tpm install_plugins
	local panel
	panel=$(printf '%q' "$TPP_ROOT/scripts/panel.sh")
	run on_terminal "$panel install"
	[ "$status" -eq 0 ]
	[[ $output == *"Installing missing plugins ⠋"*$'\r\033[K''Installing "alpha"'*'"alpha" download success'* ]]
	[ -d "$PLUGIN_DIR/alpha/.git" ]
}

@test "clean runs TPM behind a spinner, then shows TPM's output" {
	mkdir -p "$PLUGIN_DIR/orphan"
	slow_tpm clean_plugins
	local panel
	panel=$(printf '%q' "$TPP_ROOT/scripts/panel.sh")
	# y and enter answer the question, x is the key for "Press any key".
	run bash -c 'printf "y\rx" | SHELL=/bin/bash script -qec "$1 clean" /dev/null' _ "$panel"
	[ "$status" -eq 0 ]
	[[ $output == *"Cleaning ⠋"*$'\r\033[K''Removing "orphan"'*'"orphan" clean success'* ]]
	[ ! -e "$PLUGIN_DIR/orphan" ]
}
