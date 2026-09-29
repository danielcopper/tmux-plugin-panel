#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# The check behind the animated list (fzf 0.73 and newer): `panel.sh check
# <dir>` fetches the plugins and writes the list's frames and fzf's next
# action into <dir>.

setup() {
	load test_helper
	tpp_setup
	standard_env
	PANEL="$TPP_ROOT/scripts/panel.sh"
	SELF=$(printf '%q' "$PANEL")
	CHECK_DIR="$TEST_ROOT/check"
	mkdir -p "$CHECK_DIR"
}

teardown() {
	# Kills what a failed test left running: the processes it started
	# ($TEST_ROOT/pids), the remotes' sleeps ($TEST_ROOT/sleeps, see
	# slow_remote) and a check started by recheck.
	local file pid
	[[ -n ${ORIGINAL_PATH-} ]] && PATH=$ORIGINAL_PATH
	for file in "$TEST_ROOT/pids" "$TEST_ROOT/sleeps" "$CHECK_DIR/pid"; do
		[[ -f $file ]] || continue
		while read -r pid; do
			kill "$pid" 2>/dev/null || true
		done <"$file"
	done
	tpp_teardown
}

# slow_remote <name> <seconds>: the fetch of the installed plugin <name>
# waits <seconds> before its remote answers. The remote's side runs under the
# fetch, as a local remote's upload-pack does; it records the pid of its
# sleep in $TEST_ROOT/sleeps.
slow_remote() {
	git -C "$PLUGIN_DIR/$1" config remote.origin.uploadpack \
		"sleep $2 & echo \$! >>$TEST_ROOT/sleeps; wait; git-upload-pack"
}

# plugin <name>: a declared, installed plugin whose remote has one commit
# more than the clone.
plugin() {
	make_remote "$1"
	clone_plugin "$1"
	declare_plugin "$(remote_url "$1")"
	push_commit "$1"
}

# wait_for <seconds> <command> [<arg>...]: runs the command every 0.05 s
# until it succeeds; fails when it has not after about <seconds>.
wait_for() {
	local end=$((SECONDS + $1))
	shift
	until "$@"; do
		((SECONDS <= end)) || return 1
		sleep 0.05
	done
}

# dead <pid>...: true when none of the processes runs.
dead() {
	local pid
	for pid; do
		kill -0 "$pid" 2>/dev/null && return 1
	done
	return 0
}

# sleeps_dead: true when none of the remotes' sleeps runs.
sleeps_dead() {
	[[ -f $TEST_ROOT/sleeps ]] || return 0
	# shellcheck disable=SC2046 # one pid per line
	dead $(cat "$TEST_ROOT/sleeps")
}

# no_fetch_left: true when no process of a fetch runs: no git in a plugin
# directory, no remote side.
no_fetch_left() {
	sleeps_dead && ! pgrep -f -- "$PLUGIN_DIR" >/dev/null && ! pgrep -f -- "$TEST_ROOT/remotes" >/dev/null
}

# fetch_left: true when a process of a fetch runs.
fetch_left() {
	! no_fetch_left
}

# row_of <name>: the row of plugin <name> in the current frame, as shown:
# without its key and escape codes.
row_of() {
	awk -F '\t' -v n="$1" '$1 == n { print $2 }' "$CHECK_DIR/frame" 2>/dev/null | sed $'s/\033\\[[0-9;]*m//g'
}

# spinning <name>: true when the frame shows the spinner in <name>'s row.
spinning() {
	[[ $(row_of "$1") == *"checking "[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]* ]]
}

# shows <name> <text>: true when <name>'s row in the frame contains <text>.
shows() {
	[[ $(row_of "$1") == *"$2"* ]]
}

# glyph_of <name>: the spinner's frame in <name>'s row.
glyph_of() {
	local row
	row=$(row_of "$1")
	row=${row#*checking }
	printf '%s\n' "${row:0:1}"
}

# with_check <command> [<arg>...]: runs the command with TPP_CHECK_DIR set to
# the test's check directory, as fzf runs the commands of its bindings.
with_check() {
	TPP_CHECK_DIR=$CHECK_DIR "$@"
}

# glyph_other_than <glyph>: true when beta's row shows another frame.
glyph_other_than() {
	[[ $(glyph_of beta) != "$1" ]]
}

# inode_other_than <inode>: true when the frame is another file.
inode_other_than() {
	local inode
	inode=$(ls -i "$CHECK_DIR/frame")
	[[ ${inode%% *} != "$1" ]]
}

# sleeping <count>: true when <count> remotes have started their sleep.
sleeping() {
	[[ $(grep -c . "$TEST_ROOT/sleeps" 2>/dev/null) -eq $1 ]]
}

# final_action_written: true when the check has written its last action,
# which loads the list's usual rows.
final_action_written() {
	[[ $(cat "$CHECK_DIR/action" 2>/dev/null) == *"reload-sync($SELF rows)"* ]]
}

# without_timeout: takes timeout and gtimeout off PATH, for the test and for
# the commands its tmux server starts, so that the panel fetches without a
# timeout command. A directory of links to every other command on PATH takes
# PATH's place, after the test's own bin directory. The test itself keeps
# timeout as a function, which the panel does not see; teardown puts PATH
# back.
without_timeout() {
	local bin="$TEST_ROOT/no-timeout" dir i
	local -a dirs=()
	REAL_TIMEOUT=$(command -v timeout)
	timeout() { "$REAL_TIMEOUT" "$@"; }
	ORIGINAL_PATH=$PATH
	mkdir -p "$bin"
	IFS=: read -ra dirs <<<"$PATH"
	# Linked from the last directory to the first, so that the first
	# directory's command wins, as on PATH.
	for ((i = ${#dirs[@]} - 1; i >= 0; i--)); do
		dir=${dirs[i]}
		[[ -d $dir && $dir != "$TEST_ROOT/bin" ]] || continue
		find "$dir" -maxdepth 1 -mindepth 1 -exec ln -sfn -t "$bin" {} +
	done
	rm -f "$bin/timeout" "$bin/gtimeout"
	PATH="$TEST_ROOT/bin:$bin"
	hash -r
	if type -P timeout >/dev/null || type -P gtimeout >/dev/null; then
		return 1
	fi
	tmux set-environment -g PATH "$PATH"
}

# fake_fzf <version>: a fake fzf first on PATH that reports <version> and
# records the list's invocation: its arguments, each ended by a NUL, in
# $TEST_ROOT/fzf-argv, and TPP_CHECK_DIR in $TEST_ROOT/fzf-check-dir.
fake_fzf() {
	cat >"$TEST_ROOT/bin/fzf" <<EOF
#!/usr/bin/env bash
[[ \$1 == --version ]] && { echo "$1 (fake)"; exit 0; }
printf '%s\0' "\$@" >"$TEST_ROOT/fzf-argv"
printf '%s' "\${TPP_CHECK_DIR-}" >"$TEST_ROOT/fzf-check-dir"
cat >/dev/null
EOF
	chmod +x "$TEST_ROOT/bin/fzf"
}

# expected_argv <start>... -- <refresh>: the list's fzf arguments, each
# ended by a NUL, with <start> (the arguments that load the list's status)
# and the binding <refresh> for r in their places.
expected_argv() {
	local -a start=()
	while [[ $1 != -- ]]; do
		start+=("$1")
		shift
	done
	local refresh=$2
	printf '%s\0' --multi --ansi --no-sort --layout=reverse --disabled \
		--delimiter $'\t' --with-nth 2.. --header-lines 1 \
		--prompt '' --info default --no-separator --header "plugins ~/.config/tmux/plugins/   file ~/.config/tmux/plugins.conf
enter/u update · U all · a add · d remove · i install · c clean · r refresh · tab mark · q quit
j/k move · J/K scroll preview · ctrl-d/ctrl-u scroll preview by half a page" \
		--preview "$SELF preview {1}" --preview-window 'down,50%,wrap' \
		"${start[@]}" \
		--bind 'change:clear-query' \
		--bind 'j:down' \
		--bind 'k:up' \
		--bind 'J:preview-down' \
		--bind 'K:preview-up' \
		--bind 'ctrl-d:preview-half-page-down' \
		--bind 'ctrl-u:preview-half-page-up' \
		--bind "enter:execute($SELF update {+1})+reload-sync($SELF rows)" \
		--bind "u:execute($SELF update {+1})+reload-sync($SELF rows)" \
		--bind "U:execute($SELF update all)+reload-sync($SELF rows)" \
		--bind "a:execute($SELF add)+reload-sync($SELF rows)" \
		--bind "d:execute($SELF remove {+1})+reload-sync($SELF rows)" \
		--bind "i:execute($SELF install)+reload-sync($SELF rows)" \
		--bind "c:execute($SELF clean)+reload-sync($SELF rows)" \
		--bind "$refresh" \
		--bind 'q:abort'
}

@test "below fzf 0.73 the panel loads the status through fzf's load event, without a check" {
	local version
	for version in 0.36.0 0.72.1; do
		fake_fzf "$version"
		run timeout 20 "$PANEL"
		[ "$status" -eq 0 ]
		cmp "$TEST_ROOT/fzf-argv" <(expected_argv \
			--bind "load:reload-sync($SELF rows --fetch)+unbind(load)" \
			-- "r:reload-sync($SELF rows --fetch)")
		[ ! -s "$TEST_ROOT/fzf-check-dir" ]
	done
}

@test "from fzf 0.73 the list takes its frames from the check, keeps marks by name, and r starts the check again" {
	local version dir
	for version in 0.73.0 0.74.1; do
		fake_fzf "$version"
		run timeout 20 "$PANEL"
		[ "$status" -eq 0 ]
		dir=$(cat "$TEST_ROOT/fzf-check-dir")
		[ -n "$dir" ]
		# --no-track: with --id-nth, --track (for example from
		# FZF_DEFAULT_OPTS) can delay or drop keys while the frames reload
		# (seen with fzf 0.74).
		cmp "$TEST_ROOT/fzf-argv" <(expected_argv \
			--id-nth 1 --no-track --bind "every(0.1):transform(cat $(printf '%q' "$dir")/action)" \
			-- "r:execute-silent($SELF recheck)+rebind(every(0.1))")
		# The check's directory is gone once the panel is.
		[ ! -e "$dir" ]
	done
}

@test "the check turns a spinner in each row whose fetch runs and shows a row's status as soon as its fetch ends" {
	plugin alpha
	plugin beta
	slow_remote beta 3
	"$PANEL" check "$CHECK_DIR" 3>&- &
	echo "$!" >>"$TEST_ROOT/pids"
	# alpha's result while beta's fetch still runs.
	wait_for 10 shows alpha "↓1"
	spinning beta
	# The spinner turns.
	local glyph
	glyph=$(glyph_of beta)
	wait_for 5 glyph_other_than "$glyph"
	spinning beta
	# fzf reloads the frames until the check ends; then it drops the
	# every(0.1) binding and loads the list's usual rows.
	[ "$(cat "$CHECK_DIR/action")" = "reload-sync(cat $(printf '%q' "$CHECK_DIR")/frame)" ]
	wait_for 15 final_action_written
	[ "$(cat "$CHECK_DIR/action")" = "unbind(every(0.1))+reload-sync($SELF rows)" ]
	shows alpha "↓1"
	shows beta "↓1"
	# The last frame is the list's usual rows.
	cmp "$CHECK_DIR/frame" <("$PANEL" rows)
}

@test "the check replaces its frame at once, never writing into the file fzf reads" {
	plugin alpha
	slow_remote alpha 2
	"$PANEL" check "$CHECK_DIR" 3>&- &
	echo "$!" >>"$TEST_ROOT/pids"
	wait_for 10 test -s "$CHECK_DIR/frame"
	# A file written in place keeps its inode; one renamed over it does not.
	local first
	first=$(ls -i "$CHECK_DIR/frame")
	wait_for 5 inode_other_than "${first%% *}"
	wait_for 15 final_action_written
	# No temporary file is left behind.
	run ls -A "$CHECK_DIR"
	[ "$output" = $'action\nfetched\nframe' ]
}

@test "a declared plugin that is not a git checkout shows its status in the check's first frame" {
	mkdir -p "$PLUGIN_DIR/plain"
	declare_plugin someone/plain
	plugin alpha
	slow_remote alpha 3
	"$PANEL" check "$CHECK_DIR" 3>&- &
	echo "$!" >>"$TEST_ROOT/pids"
	wait_for 10 test -s "$CHECK_DIR/frame"
	shows plain "not a git repo"
	spinning alpha
}

@test "the check speaks German under a German locale" {
	plugin alpha
	slow_remote alpha 2
	german "$PANEL" check "$CHECK_DIR" 3>&- &
	echo "$!" >>"$TEST_ROOT/pids"
	wait_for 10 test -s "$CHECK_DIR/frame"
	[[ $(row_of alpha) == *"wird geprüft "[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]* ]]
}

case_fetch_env() {
	plugin alpha
	load_lib
	# tpp_git and the fetches each set git's environment inline; this test
	# fails when they drift apart. What tpp_git adds to git's environment:
	# the difference between the environments an alias sees when run
	# through tpp_git and without it.
	git -C "$PLUGIN_DIR/alpha" config alias.env '!env'
	local added
	added=$(comm -13 <(git -C "$PLUGIN_DIR/alpha" env | sort) <(tpp_git "$PLUGIN_DIR/alpha" env | sort))
	[ -n "$added" ]
	# None of it stays in the caller's environment.
	[ "$LC_ALL" = C.UTF-8 ]
	[ -z "${GIT_TERMINAL_PROMPT+set}" ]
	# The fetch's environment, as its remote side gets it. The fetch runs in
	# a process of its own, as in the panel, with the panel's credential
	# setting in its environment, and prints the command of the recorded
	# process: a forked process shows as bash until it has started its
	# command; a shell waiting for the command does for good (the remote
	# side keeps the fetch running for a second).
	git -C "$PLUGIN_DIR/alpha" config remote.origin.uploadpack \
		"env >$TEST_ROOT/fetch-env; sleep 1; git-upload-pack"
	cat >"$TEST_ROOT/fetch" <<EOF
#!/usr/bin/env bash
source "$TPP_ROOT/scripts/lib.sh"
tpp_init
tpp_disable_credential_helpers
tpp_fetch_start
for _ in 1 2 3 4 5 6 7 8 9 10; do
	command=\$(ps -o comm= -p "\${TPP_FETCH_PIDS[0]}")
	[[ \$command == bash ]] || break
	sleep 0.05
done
echo "\${#TPP_FETCH_PIDS[@]} \$command"
wait
EOF
	chmod +x "$TEST_ROOT/fetch"
	local recorded
	recorded=$("$TEST_ROOT/fetch")
	[[ $recorded == "1 timeout" || $recorded == "1 git" ]] || {
		echo "fetches and the recorded process: $recorded"
		return 1
	}
	local line
	while IFS= read -r line; do
		grep -qxF -- "$line" "$TEST_ROOT/fetch-env" || {
			echo "the fetch's environment lacks $line"
			return 1
		}
	done <<<"$added"
	# The rest of the environment reaches the fetch too.
	grep -qxF "GIT_CONFIG_KEY_0=credential.https://git@github.com.helper" "$TEST_ROOT/fetch-env"
}

@test "a fetch gets tpp_git's environment, and its recorded process is git or the timeout command" {
	case_fetch_env
}

@test "a fetch gets tpp_git's environment, and its recorded process is git or the timeout command, also without timeout" {
	without_timeout
	case_fetch_env
}

case_sigterm() {
	plugin alpha
	plugin beta
	slow_remote alpha 30
	slow_remote beta 30
	"$PANEL" check "$CHECK_DIR" 3>&- &
	local job=$!
	echo "$job" >>"$TEST_ROOT/pids"
	wait_for 10 sleeping 2
	wait_for 10 test -s "$CHECK_DIR/frame"
	fetch_left
	kill -TERM "$job"
	wait_for 5 dead "$job"
	wait_for 5 no_fetch_left
	[ "$(cat "$CHECK_DIR/action")" = "reload-sync(cat $(printf '%q' "$CHECK_DIR")/frame)" ]
}

@test "SIGTERM ends the check and its fetches, without a final action" {
	case_sigterm
}

@test "SIGTERM ends the check and its fetches, without a final action, also without timeout" {
	without_timeout
	case_sigterm
}

case_quit() {
	plugin alpha
	slow_remote alpha 30
	# A fake fzf that quits as soon as the check's fetch runs, as q does.
	cat >"$TEST_ROOT/bin/fzf" <<EOF
#!/usr/bin/env bash
[[ \$1 == --version ]] && { echo "0.73.0 (fake)"; exit 0; }
cat >/dev/null
for _ in \$(seq 100); do
	[[ -s $TEST_ROOT/sleeps ]] && break
	sleep 0.1
done
cp "\$TPP_CHECK_DIR/pid" "$TEST_ROOT/job"
printf '%s' "\$TPP_CHECK_DIR" >"$TEST_ROOT/fzf-check-dir"
EOF
	chmod +x "$TEST_ROOT/bin/fzf"
	timeout 20 "$PANEL"
	[ -s "$TEST_ROOT/sleeps" ]
	local job dir
	job=$(cat "$TEST_ROOT/job")
	dir=$(cat "$TEST_ROOT/fzf-check-dir")
	# Nothing is left once the panel has returned.
	dead "$job"
	no_fetch_left
	[ ! -e "$dir" ]
}

@test "quitting the list ends the check and its fetches, and removes the check's directory" {
	case_quit
}

@test "quitting the list ends the check and its fetches, and removes the check's directory, also without timeout" {
	without_timeout
	case_quit
}

case_popup() {
	plugin alpha
	slow_remote alpha 30
	# A fake fzf that, like fzf, ends when its terminal is gone: it waits for
	# a key on the terminal (for 30 seconds at most).
	cat >"$TEST_ROOT/bin/fzf" <<EOF
#!/usr/bin/env bash
[[ \$1 == --version ]] && { echo "0.73.0 (fake)"; exit 0; }
echo \$\$ >>"$TEST_ROOT/pids"
printf '%s' "\$TPP_CHECK_DIR" >"$TEST_ROOT/fzf-check-dir"
cat >/dev/null
read -rsn1 -t 30 _ </dev/tty
EOF
	chmod +x "$TEST_ROOT/bin/fzf"
	tmux new-window -d -n panel "$PANEL"
	wait_for 10 test -s "$TEST_ROOT/sleeps"
	wait_for 10 test -s "$TEST_ROOT/fzf-check-dir"
	local dir job
	dir=$(cat "$TEST_ROOT/fzf-check-dir")
	job=$(cat "$dir/pid")
	echo "$job" >>"$TEST_ROOT/pids"
	# Closing the window hangs up the panel's terminal, as closing the popup
	# does.
	tmux kill-window -t panel
	wait_for 5 dead "$job"
	wait_for 5 no_fetch_left
	wait_for 5 test ! -e "$dir"
}

@test "closing the popup ends the check and its fetches, and removes the check's directory" {
	case_popup
}

@test "closing the popup ends the check and its fetches, and removes the check's directory, also without timeout" {
	without_timeout
	case_popup
}

case_killed() {
	plugin alpha
	slow_remote alpha 30
	# The same fake fzf as in the test above.
	cat >"$TEST_ROOT/bin/fzf" <<EOF
#!/usr/bin/env bash
[[ \$1 == --version ]] && { echo "0.73.0 (fake)"; exit 0; }
echo \$\$ >>"$TEST_ROOT/pids"
printf '%s' "\$TPP_CHECK_DIR" >"$TEST_ROOT/fzf-check-dir"
cat >/dev/null
read -rsn1 -t 30 _ </dev/tty
EOF
	chmod +x "$TEST_ROOT/bin/fzf"
	tmux new-window -d -n panel "$PANEL"
	wait_for 10 test -s "$TEST_ROOT/sleeps"
	wait_for 10 test -s "$TEST_ROOT/fzf-check-dir"
	local dir job panel
	dir=$(cat "$TEST_ROOT/fzf-check-dir")
	job=$(cat "$dir/pid")
	echo "$job" >>"$TEST_ROOT/pids"
	panel=$(tmux display-message -p -t panel '#{pane_pid}')
	[ -n "$panel" ]
	# The panel gets no chance to end the check. It led the terminal's
	# session, so the terminal hangs up the processes left on it.
	kill -KILL "$panel"
	wait_for 5 dead "$job"
	wait_for 5 no_fetch_left
}

@test "a check whose panel is killed ends its fetches when the terminal hangs up" {
	case_killed
}

@test "a check whose panel is killed ends its fetches when the terminal hangs up, also without timeout" {
	without_timeout
	case_killed
}

case_action() {
	plugin alpha
	slow_remote alpha 30
	# TPM's install, replaced by one that records whether a fetch still runs.
	cat >"$PLUGIN_DIR/tpm/bin/install_plugins" <<EOF
#!/usr/bin/env bash
if kill -0 \$(cat "$TEST_ROOT/sleeps") 2>/dev/null; then
	echo "fetch running"
else
	echo "no fetch"
fi >"$TEST_ROOT/during-install"
EOF
	with_check timeout 20 "$PANEL" recheck
	local job
	job=$(cat "$CHECK_DIR/pid")
	wait_for 10 test -s "$TEST_ROOT/sleeps"
	with_check on_terminal "$SELF install" >/dev/null
	[ "$(cat "$TEST_ROOT/during-install")" = "no fetch" ]
	dead "$job"
	no_fetch_left
	[ "$(cat "$CHECK_DIR/action")" = "unbind(every(0.1))" ]
	[ ! -e "$CHECK_DIR/pid" ]
	[ ! -e "$CHECK_DIR/checking" ]
}

@test "an action ends a running check before it runs TPM, and leaves fzf an action that only drops the binding" {
	case_action
}

@test "an action ends a running check before it runs TPM, and leaves fzf an action that only drops the binding, also without timeout" {
	without_timeout
	case_action
}

case_recheck() {
	plugin alpha
	with_check timeout 20 "$PANEL" recheck
	local first
	first=$(cat "$CHECK_DIR/pid")
	wait_for 15 final_action_written
	wait_for 5 dead "$first"
	[ -e "$CHECK_DIR/fetched/alpha" ]
	[ ! -e "$CHECK_DIR/checking" ]
	slow_remote alpha 30
	with_check timeout 20 "$PANEL" recheck
	# At once: nothing for fzf to apply yet (the final action of the check
	# before would drop the binding r has just bound again), the preview
	# comes from the new check's cache, which is empty, and a new check runs.
	[ ! -s "$CHECK_DIR/action" ]
	[ -e "$CHECK_DIR/checking" ]
	[ -z "$(ls -A "$CHECK_DIR/fetched" 2>/dev/null)" ]
	[ -z "$(ls -A "$CHECK_DIR/preview" 2>/dev/null)" ]
	local second
	second=$(cat "$CHECK_DIR/pid")
	[ "$second" != "$first" ]
	kill -0 "$second"
	wait_for 10 test -s "$CHECK_DIR/action"
	[ "$(cat "$CHECK_DIR/action")" = "reload-sync(cat $(printf '%q' "$CHECK_DIR")/frame)" ]
	wait_for 10 spinning alpha
	# r while a check runs ends it and its fetch first.
	wait_for 10 test -s "$TEST_ROOT/sleeps"
	with_check timeout 20 "$PANEL" recheck
	dead "$second"
	wait_for 5 sleeps_dead
}

@test "recheck, bound to r, starts the check again from the start" {
	case_recheck
}

@test "recheck, bound to r, starts the check again from the start, also without timeout" {
	without_timeout
	case_recheck
}

@test "while a check runs, the preview comes from the check's cache, made once before and once after the plugin's fetch" {
	plugin alpha
	local usual
	usual=$("$PANEL" preview alpha)
	# No check running: the usual preview, and nothing cached.
	run with_check "$PANEL" preview alpha
	[ "$status" -eq 0 ]
	[ "$output" = "$usual" ]
	[ ! -e "$CHECK_DIR/preview" ]
	: >"$CHECK_DIR/checking"
	# Before the fetch: made once, then read from the cache.
	run with_check "$PANEL" preview alpha
	[ "$status" -eq 0 ]
	[ "$output" = "$usual" ]
	[ "$(cat "$CHECK_DIR/preview/before/alpha")" = "$usual" ]
	printf 'cached\n' >"$CHECK_DIR/preview/before/alpha"
	run with_check "$PANEL" preview alpha
	[ "$output" = cached ]
	# After the fetch: made again, with the commits the fetch brought.
	git -C "$PLUGIN_DIR/alpha" fetch -q
	mkdir -p "$CHECK_DIR/fetched"
	: >"$CHECK_DIR/fetched/alpha"
	run with_check "$PANEL" preview alpha
	[ "$status" -eq 0 ]
	[[ $output == *"pending commits:"*"change on main"* ]]
	[ "$(cat "$CHECK_DIR/preview/after/alpha")" = "$output" ]
	printf 'cached after\n' >"$CHECK_DIR/preview/after/alpha"
	run with_check "$PANEL" preview alpha
	[ "$output" = "cached after" ]
	# Once the check has ended: the usual preview again.
	rm "$CHECK_DIR/checking"
	run with_check "$PANEL" preview alpha
	[ "$status" -eq 0 ]
	[[ $output == *"pending commits:"*"change on main"* ]]
}
