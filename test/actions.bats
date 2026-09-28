#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	load test_helper
	tpp_setup
	standard_env
}

teardown() {
	# Kills the processes a failed test left running (see alive below).
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

# write_spin: writes $TEST_ROOT/spin <command> [<arg>...], which runs the
# command behind tpp_spin with its output in $TEST_ROOT/log, then prints the
# status, and "no children" when the shell has no child process left: neither
# the command nor the spinner.
write_spin() {
	cat >"$TEST_ROOT/spin" <<EOF2
#!/usr/bin/env bash
source "$TPP_ROOT/scripts/lib.sh"
tpp_spin Working "$TEST_ROOT/log" "\$@"
echo "status \$?"
pgrep -P \$\$ || echo "no children"
EOF2
	chmod +x "$TEST_ROOT/spin"
}

@test "the spinner shows its message while the command runs, then clears its line" {
	write_spin
	# A spinner left running would make tpp_spin wait forever: the timeout
	# turns that into a failure.
	run timeout 20 "$TEST_ROOT/spin" bash -c 'echo out; echo err >&2; sleep 0.3'
	[ "$status" -eq 0 ]
	[[ $output == $'\r'"Working ⠋"*$'\r\033[K'"status 0"$'\n'"no children" ]]
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
	write_spin
	# A spinner left running would make tpp_spin wait forever: the timeout
	# turns that into a failure.
	run timeout 20 "$TEST_ROOT/spin" "$TEST_ROOT/fail" "$TEST_ROOT"
	[ "$status" -eq 0 ]
	[[ $output == $'\r'"Working ⠋"*$'\r\033[K'"status 3"$'\n'"no children" ]]
	[ -z "$(alive "$TEST_ROOT/pids")" ]
}

@test "the spinner stops when the shell running tpp_spin is killed" {
	cat >"$TEST_ROOT/long" <<'EOF2'
#!/usr/bin/env bash
echo $$ >>"$1/pids"
exec sleep 30
EOF2
	chmod +x "$TEST_ROOT/long"
	write_spin
	"$TEST_ROOT/spin" "$TEST_ROOT/long" "$TEST_ROOT" >"$TEST_ROOT/out" 2>&1 3>&- &
	local runner=$! child spinner=
	for _ in $(seq 50); do
		[[ -s $TEST_ROOT/pids ]] && break
		sleep 0.1
	done
	# The runner's children: the child shell that runs the command in the
	# foreground, and the spinner.
	for child in $(pgrep -P "$runner"); do
		[[ $(ps -o args= -p "$child") == "bash -c set -m"* ]] || spinner=$child
	done
	[ -n "$spinner" ]
	echo "$spinner" >>"$TEST_ROOT/pids"
	kill -0 "$spinner"
	kill -KILL "$runner"
	wait "$runner" 2>/dev/null || true
	for _ in $(seq 10); do
		kill -0 "$spinner" 2>/dev/null || break
		sleep 0.1
	done
	run ! kill -0 "$spinner"
}

@test "the spinner stops when its terminal is gone" {
	# A spinner that outlives the terminal it draws on: SIGHUP ignored, and
	# its owner still running.
	sleep 30 3>&- &
	local owner=$!
	echo "$owner" >>"$TEST_ROOT/pids"
	cat >"$TEST_ROOT/hup-spinner" <<EOF2
#!/usr/bin/env bash
trap '' HUP
source "$TPP_ROOT/scripts/lib.sh"
echo \$\$ >"$TEST_ROOT/spinner-pid"
tpp_spinner Working "$owner"
EOF2
	chmod +x "$TEST_ROOT/hup-spinner"
	tmux new-window -d -n spin "$TEST_ROOT/hup-spinner"
	for _ in $(seq 50); do
		[[ -s $TEST_ROOT/spinner-pid ]] && break
		sleep 0.1
	done
	local spinner
	spinner=$(cat "$TEST_ROOT/spinner-pid")
	echo "$spinner" >>"$TEST_ROOT/pids"
	sleep 0.3
	kill -0 "$spinner"
	# Closing the window hangs up the spinner's terminal.
	tmux kill-window -t spin
	for _ in $(seq 10); do
		kill -0 "$spinner" 2>/dev/null || break
		sleep 0.1
	done
	run ! kill -0 "$spinner"
}

@test "Ctrl-C ends the command and everything it started, then the spinner" {
	# The command starts two more processes and records all three, itself
	# last.
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
	write_spin
	# Started with job control (set -m), so that the shell does not start it
	# with SIGINT ignored, which the command would inherit.
	set -m
	"$TEST_ROOT/spin" "$TEST_ROOT/busy" "$TEST_ROOT" >"$TEST_ROOT/out" 2>&1 3>&- &
	local pid=$!
	set +m
	for _ in $(seq 50); do
		[[ -f $TEST_ROOT/pids && $(wc -l <"$TEST_ROOT/pids") -eq 3 ]] && break
		sleep 0.1
	done
	[ "$(alive "$TEST_ROOT/pids" | wc -l)" -eq 3 ]
	local group
	group=$(tail -n 1 "$TEST_ROOT/pids")
	# The runner too, for teardown, should it be left waiting for its spinner.
	echo "$pid" >>"$TEST_ROOT/pids"
	# Ctrl-C: the terminal sends SIGINT to its foreground process group,
	# which is the command's own, led by the command.
	kill -INT -- "-$group"
	for _ in $(seq 50); do
		kill -0 "$pid" 2>/dev/null || break
		sleep 0.1
	done
	run ! kill -0 "$pid"
	wait "$pid"
	[ -z "$(alive "$TEST_ROOT/pids")" ]
	run cat "$TEST_ROOT/out"
	[[ $output == $'\r'"Working "* ]]
	[[ $output == *$'\r\033[K'"status 130"$'\n'"no children" ]]
}

@test "a command behind the spinner can read from the terminal; the spinner pauses while echo is off" {
	# Asks for a passphrase the way ssh does: echo off, a prompt and a read
	# on the terminal.
	cat >"$TEST_ROOT/ask" <<'EOF2'
#!/usr/bin/env bash
sleep 0.3
stty -echo </dev/tty
sleep 0.3
printf '[asking]' >/dev/tty
read -r answer </dev/tty
sleep 0.5
printf '[answered]' >/dev/tty
stty echo </dev/tty
echo "got $answer"
EOF2
	chmod +x "$TEST_ROOT/ask"
	write_spin
	local cmd
	printf -v cmd '%q ' "$TEST_ROOT/spin" "$TEST_ROOT/ask"
	# A command that cannot read the terminal would wait forever: the
	# timeout makes that a failure.
	run bash -c 'printf "secret\r" | SHELL=/bin/bash timeout 20 script -qec "$1" /dev/null' _ "$cmd"
	[ "$status" -eq 0 ]
	[[ $output == *"status 0"* ]]
	[ "$(cat "$TEST_ROOT/log")" = "got secret" ]
	# Between the prompt and the answer the spinner drew nothing, though it
	# did before: every frame after the first starts with ESC 7.
	local asking=${output#*\[asking\]}
	asking=${asking%%\[answered\]*}
	[[ $output == *"[asking]"*"[answered]"* ]]
	[[ $asking != *$'\0337'* ]]
	[[ $output == *$'\0337'* ]]
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
	run bash -c 'printf "y\rx" | SHELL=/bin/bash timeout 30 script -qec "$1 clean" /dev/null' _ "$panel"
	[ "$status" -eq 0 ]
	[[ $output == *"Cleaning ⠋"*$'\r\033[K''Removing "orphan"'*'"orphan" clean success'* ]]
	[ ! -e "$PLUGIN_DIR/orphan" ]
}

@test "add runs TPM's install behind a spinner, then shows TPM's output" {
	make_remote alpha
	slow_tpm install_plugins
	local panel url
	panel=$(printf '%q' "$TPP_ROOT/scripts/panel.sh")
	url=$(remote_url alpha)
	# The plugin and enter answer the prompt, x is the key for "Press any key".
	run bash -c 'printf "%s\rx" "$2" | SHELL=/bin/bash timeout 30 script -qec "$1 add" /dev/null' _ "$panel" "$url"
	[ "$status" -eq 0 ]
	[[ $output == *"Installing $url ⠋"*$'\r\033[K''Installing "alpha"'*'"alpha" download success'* ]]
	[ -d "$PLUGIN_DIR/alpha/.git" ]
}
