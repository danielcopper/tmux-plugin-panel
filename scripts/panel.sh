#!/usr/bin/env bash
#
# The plugin panel. Without arguments it opens the fzf list; the other
# subcommands are what the list's key bindings call.

# preview_cache_file <name>: while the list shows the check's frames (see
# run_check), sets PREVIEW_CACHE_FILE to the file in the check's directory
# that holds the preview of plugin <name>, or will: one file while the
# plugin's fetch runs, another once it has ended. False at any other time.
preview_cache_file() {
	[[ -n ${TPP_CHECK_DIR-} && -e $TPP_CHECK_DIR/checking ]] || return 1
	case $1 in
	"" | . | .. | */*) return 1 ;;
	esac
	PREVIEW_CACHE_FILE="$TPP_CHECK_DIR/preview/before/$1"
	[[ -e $TPP_CHECK_DIR/fetched/$1 ]] && PREVIEW_CACHE_FILE="$TPP_CHECK_DIR/preview/after/$1"
	return 0
}

# A preview in the check's cache (see cmd_preview) is printed here, before
# the rest of the panel is read and the library loaded, which a cached
# preview does not need and which would cost more CPU than the rest of it.
if [[ ${1-} == preview ]] && preview_cache_file "${2-}" && [[ -f $PREVIEW_CACHE_FILE ]]; then
	exec cat "$PREVIEW_CACHE_FILE"
fi

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$CURRENT_DIR/panel.sh"
TPP_MIN_FZF=0.36
# From this fzf version on (its every() event) the list shows the check,
# see run_check; with older fzf it loads the status once all the fetches
# have ended.
TPP_CHECK_FZF=0.73
# Stands for the spinner's frame in the rows run_check renders, which it
# replaces by the frame each time it writes them.
FRAME_MARK=$'\037'

# shellcheck source=scripts/lib.sh
source "$CURRENT_DIR/lib.sh"

# fzf's execute shows the terminal's normal screen, which still holds the
# previous action's output.
clear_screen() {
	printf '\033[H\033[2J'
}

pause() {
	printf '\n%s' "${1:-$TPP_MSG_PRESS_KEY_RETURN}"
	read -rsn1 _ </dev/tty
	printf '\n'
}

fail_and_exit() {
	tpp_err "$1"
	pause "$TPP_MSG_PRESS_KEY_CLOSE"
	exit 1
}

# confirm <question>: true when the answer is one of TPP_MSG_CONFIRM_YES, in
# any case.
confirm() {
	local answer word
	printf '%s %s ' "$1" "$TPP_MSG_CONFIRM_CHOICES"
	read -r answer </dev/tty
	answer=$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')
	for word in $TPP_MSG_CONFIRM_YES; do
		[[ $answer == "$word" ]] && return 0
	done
	return 1
}

# Checks for git and fzf, and sets FZF_VERSION to fzf's version.
check_dependencies() {
	local cmd missing=() version
	for cmd in git fzf; do
		command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
	done
	if ((${#missing[@]})); then
		fail_and_exit "$(tpp_msg_missing_commands "${missing[@]}")"
	fi
	version=$(fzf --version 2>/dev/null)
	version=${version%% *}
	if ! tpp_version_ge "$version" "$TPP_MIN_FZF"; then
		fail_and_exit "$(tpp_msg_fzf_too_old "$TPP_MIN_FZF" "${version:-$TPP_MSG_UNKNOWN_VERSION}")"
	fi
	FZF_VERSION=$version
}

reload_tmux_config() {
	[[ -f $TPP_USER_CONF ]] || return 0
	tmux source-file "$TPP_USER_CONF" || tpp_err "$(tpp_msg_reload_failed "$TPP_USER_CONF")"
}

warn_if_not_sourced() {
	tpp_panel_file_sourced && return 0
	printf '\n%s\n' "$(tpp_msg_note_not_sourced "$TPP_PANEL_FILE" "$TPP_USER_CONF")"
	printf '%s\n' "$(tpp_msg_add_source_line "$TPP_PANEL_FILE")"
}

# run_tpm <message> <script> [<arg>...]: runs one of TPM's scripts behind the
# spinner, then prints what it printed.
run_tpm() {
	local message=$1 log rc
	shift
	log=$(mktemp) || return 1
	tpp_spin "$message" "$log" "$@"
	rc=$?
	cat "$log"
	rm -f "$log"
	((rc == 130)) && printf '%s\n' "$TPP_MSG_INTERRUPTED"
	return "$rc"
}

# Updates through TPM, and instead of TPM's output, in which the plugins
# updated in parallel interleave, prints one line per plugin from the commits
# before and after, with TPM's output only when something failed (see
# tpp_update_summary).
cmd_update() {
	local heads log count rc
	if (($# == 0)); then
		return 0
	fi
	clear_screen
	heads=$(mktemp) || return 1
	if ! log=$(mktemp); then
		rm -f "$heads"
		return 1
	fi
	tpp_update_heads "$@" >"$heads"
	count=$(grep -c . "$heads")
	tpp_spin "$(tpp_msg_updating "$count")" "$log" "$TPP_TPM_DIR/bin/update_plugins" "$@"
	rc=$?
	tpp_update_summary "$heads" "$log" "$rc"
	((rc == 130)) && printf '\n%s\n' "$TPP_MSG_INTERRUPTED"
	rm -f "$heads" "$log"
	reload_tmux_config
	pause
}

cmd_install() {
	clear_screen
	run_tpm "$TPP_MSG_INSTALLING_MISSING" "$TPP_TPM_DIR/bin/install_plugins"
	reload_tmux_config
	pause
}

cmd_clean() {
	local undeclared
	clear_screen
	undeclared=$(tpp_collect_checking | awk -F '\t' '$2 == "not declared" { print "  " $1 }')
	if [[ -z $undeclared ]]; then
		pause "$TPP_MSG_NOTHING_TO_CLEAN"
		return
	fi
	printf '%s\n%s\n\n' "$TPP_MSG_CLEAN_LIST" "$undeclared"
	if confirm "$TPP_MSG_CLEAN_CONFIRM"; then
		run_tpm "$TPP_MSG_CLEANING" "$TPP_TPM_DIR/bin/clean_plugins"
		reload_tmux_config
	fi
	pause
}

cmd_add() {
	local input spec
	clear_screen
	printf '%s\n' "$(tpp_msg_add_title "$TPP_PANEL_FILE")"
	printf '%s\n\n' "$TPP_MSG_ADD_FORMS"
	read -rp "$TPP_MSG_ADD_PROMPT" input </dev/tty
	if [[ -z $input ]]; then
		return
	fi
	if spec=$(tpp_add "$input"); then
		printf "\n%s set -g @plugin '%s'\n" "$TPP_MSG_ADDED" "$spec"
		warn_if_not_sourced
		printf '\n'
		run_tpm "$(tpp_msg_installing "$(tpp_display_name "$spec")")" "$TPP_TPM_DIR/bin/install_plugins"
		reload_tmux_config
	fi
	pause
}

cmd_remove() {
	local name source failed=0 removable=()
	if (($# == 0)); then
		return 0
	fi
	clear_screen
	for name in "$@"; do
		if [[ $name == tpm ]]; then
			printf '%s\n' "$TPP_MSG_TPM_NOT_REMOVED"
		elif source=$(tpp_declared_outside_panel_file "$name"); then
			printf '%s\n' "$(tpp_msg_remove_elsewhere "$name" "$source")"
		else
			removable+=("$name")
		fi
	done
	if ((${#removable[@]} == 0)); then
		pause
		return
	fi
	printf '\n%s\n' "$(tpp_msg_remove_list "${removable[*]}")"
	if ! confirm "$(tpp_msg_remove_confirm "$TPP_PANEL_FILE")"; then
		return
	fi
	for name in "${removable[@]}"; do
		tpp_remove "$name" || failed=1
	done
	reload_tmux_config
	((failed)) && printf '\n%s\n' "$TPP_MSG_SOME_NOT_REMOVED"
	pause
}

# hints <counts> <key> <action> [<key> <action>...]: the key hints, each
# "<key> <action>", joined by " · " in lines of as many hints as the numbers
# in <counts> say ("9 3": nine, then three). The hints left over after the
# last number share one more line; so do all the remaining hints from the
# first entry that is not a whole number above 0 written without leading
# zeros. The lines are separated by newlines, without one at the end.
hints() {
	local counts=$1 count line text='' newline=$'\n'
	shift
	while (($# >= 2)); do
		count=${counts%% *}
		counts=${counts#"$count"}
		counts=${counts# }
		[[ $count == [1-9]* && $count != *[!0-9]* ]] || count=$(($# / 2))
		line=''
		while ((count > 0 && $# >= 2)); do
			line+="${line:+ · }$1 $2"
			shift 2
			count=$((count - 1))
		done
		text+="${text:+$newline}$line"
	done
	printf '%s' "$text"
}

header() {
	local plugin_dir=${TPP_PLUGIN_DIR/#$HOME/\~} panel_file=${TPP_PANEL_FILE/#$HOME/\~}
	printf '%s\n' "$(tpp_msg_header "$plugin_dir" "$panel_file")"
	hints "$TPP_MSG_HINT_LINES" \
		enter/u "$TPP_MSG_HINT_UPDATE" U "$TPP_MSG_HINT_ALL" a "$TPP_MSG_HINT_ADD" \
		d "$TPP_MSG_HINT_REMOVE" i "$TPP_MSG_HINT_INSTALL" c "$TPP_MSG_HINT_CLEAN" \
		r "$TPP_MSG_HINT_REFRESH" tab "$TPP_MSG_HINT_MARK" q "$TPP_MSG_HINT_QUIT" \
		j/k "$TPP_MSG_HINT_MOVE" J/K "$TPP_MSG_HINT_SCROLL" ctrl-d/ctrl-u "$TPP_MSG_HINT_SCROLL_HALF"
	if ! tpp_panel_file_sourced; then
		printf '\n\033[33m%s\033[0m' "$(tpp_msg_not_sourced "$panel_file" "${TPP_USER_CONF/#$HOME/\~}")"
	fi
}

# The check (fzf 0.73 and newer): the list fetches the plugins with a
# spinner turning in the status of each plugin whose fetch runs, and shows a
# plugin's status as soon as its own fetch has ended. The check runs in the
# background, beside fzf, and keeps its files in the directory TPP_CHECK_DIR,
# which run_ui makes and exports to fzf, for the commands of the key
# bindings:
#   action          what fzf applies next; the every(0.1) binding in run_ui
#                   reads it every 0.1 s
#   frame           the list's rows as the check shows them now
#   pid             the process of the check, while it runs
#   checking        there while the list shows the check's frames
#   records         the records of the rows fzf starts with, from run_ui
#   fetched/<name>  there once the fetch of plugin <name> has ended
#   preview/        the previews made while the list shows the frames, in
#                   before/<name> and after/<name> (see preview_cache_file)

# write_file <file> <text>: replaces <file> with <text> and a newline through
# a temporary file renamed over it, so that a reader finds the old text or
# the new one, never a part of it.
write_file() {
	printf '%s\n' "$2" >"$1.$$" && mv -f "$1.$$" "$1"
}

# fetch_started <name>: true when tpp_fetch_start has started a fetch of
# plugin <name>.
fetch_started() {
	local started
	for started in "${TPP_FETCH_NAMES[@]}"; do
		[[ $started == "$1" ]] && return 0
	done
	return 1
}

# end_fetches: sends SIGTERM to the process group of each of run_check's
# fetches that still runs. Each fetch leads its group: git and what it
# started (ssh, a remote helper) without a timeout command, which on SIGTERM
# ends only itself; or the timeout command, which passes the signal on too.
end_fetches() {
	local pid
	for pid in "${TPP_FETCH_PIDS[@]}"; do
		kill -TERM -- "-$pid" 2>/dev/null
	done
}

# check_records: the records of run_check's rows, from its arrays names,
# statuses and rests.
check_records() {
	local i
	for i in "${!names[@]}"; do
		printf '%s\t%s\t%s\n' "${names[i]}" "${statuses[i]}" "${rests[i]}"
	done
}

# run_check <dir>: the check, with its files in <dir>. It starts the fetches,
# then writes a frame every 0.1 s: the rows of tpp_format_rows, each plugin
# whose fetch runs with the spinner's next frame for its status, as
# "checking ⠋", and each plugin whose fetch has ended with its status. The
# status of a plugin is made once, when its fetch ends. The action is a
# reload of the frame while the fetches run. At the end, after a last frame
# with every status, it drops the every(0.1) binding and loads the list's
# usual rows. On SIGTERM or SIGHUP it ends its fetches and exits without
# changing the action.
run_check() {
	local dir=$1 self qdir records line status spec template name i k frame=0 changed=1
	local -a names statuses rests
	[[ -d $dir ]] || return 1
	self=$(printf '%q' "$SELF")
	qdir=$(printf '%q' "$dir")
	mkdir -p "$dir/fetched" || return 1
	trap 'end_fetches; exit 1' TERM HUP
	# Each fetch in a process group of its own (job control), so that
	# end_fetches reaches everything the fetch started.
	set -m
	tpp_fetch_start
	set +m
	if [[ -f $dir/records ]]; then
		records=$(<"$dir/records")
	else
		records=$(tpp_collect_checking)
	fi
	# The rows, as tpp_collect_checking gives them: a plugin marked checking
	# gets the spinner while its fetch runs, or at once its status when
	# there is no fetch (not a git checkout).
	while IFS= read -r line; do
		[[ -n $line ]] || continue
		name=${line%%$'\t'*}
		line=${line#*$'\t'}
		status=${line%%$'\t'*}
		line=${line#*$'\t'}
		if [[ $status == "checking…" ]]; then
			status="checking $FRAME_MARK"
			if ! fetch_started "$name"; then
				spec=${line#*$'\t'}
				status=$(tpp_status "$TPP_PLUGIN_DIR$name" "${spec%%$'\t'*}")
			fi
		fi
		names+=("$name")
		statuses+=("$status")
		rests+=("$line")
	done <<<"$records"
	while :; do
		for k in "${!TPP_FETCH_PIDS[@]}"; do
			kill -0 "${TPP_FETCH_PIDS[k]}" 2>/dev/null && continue
			unset "TPP_FETCH_PIDS[k]"
			name=${TPP_FETCH_NAMES[k]}
			: >"$dir/fetched/$name"
			for i in "${!names[@]}"; do
				[[ ${names[i]} == "$name" && ${statuses[i]} == "checking $FRAME_MARK" ]] || continue
				spec=${rests[i]#*$'\t'}
				statuses[i]=$(tpp_status "$TPP_PLUGIN_DIR$name" "${spec%%$'\t'*}")
				changed=1
			done
		done
		# Rendered only when a status has changed; each frame puts the
		# spinner's frame in place of FRAME_MARK.
		if ((changed)); then
			template=$(check_records | tpp_format_rows)
			changed=0
		fi
		write_file "$dir/frame" "${template//$FRAME_MARK/${TPP_SPINNER_FRAMES[frame % ${#TPP_SPINNER_FRAMES[@]}]}}"
		((frame)) || write_file "$dir/action" "reload-sync(cat $qdir/frame)"
		((${#TPP_FETCH_PIDS[@]})) || break
		# In the background, so that SIGTERM ends the wait at once.
		sleep 0.1 &
		wait "$!"
		frame=$((frame + 1))
	done
	# Time for fzf to load the last frame, with every status, before the
	# list's usual rows, which take longer to load.
	sleep 0.2 &
	wait "$!"
	rm -f "$dir/checking"
	write_file "$dir/action" "unbind(every(0.1))+reload-sync($self rows)"
	rm -f "$dir/pid"
}

# start_check <dir>: starts the check in <dir> in the background, from its
# start: the previous check's fetched marks and cached previews are removed
# and the action emptied, so fzf finds nothing to apply until the first
# frame.
start_check() {
	local dir=$1
	rm -rf "$dir/fetched" "$dir/preview"
	: >"$dir/action"
	: >"$dir/checking"
	"$SELF" check "$dir" </dev/null >/dev/null 2>&1 &
	printf '%s\n' "$!" >"$dir/pid"
}

# stop_check <dir>: ends the check in <dir> if one runs, together with its
# fetches (its SIGTERM trap ends them), and leaves fzf an action that only
# drops the every(0.1) binding. A check that has not ended after 3 seconds
# is killed; its fetches then run on until their timeout, or without
# timeout or gtimeout until git gives up.
stop_check() {
	local dir=$1 pid='' tries=0
	{ read -r pid <"$dir/pid"; } 2>/dev/null
	if [[ -n $pid ]] && kill -TERM "$pid" 2>/dev/null; then
		while kill -0 "$pid" 2>/dev/null && ((tries++ < 60)); do
			sleep 0.05
		done
		kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
		# Collects it when it is this shell's child (run_ui's check).
		wait "$pid" 2>/dev/null
	fi
	rm -f "$dir/pid" "$dir/checking"
	write_file "$dir/action" 'unbind(every(0.1))'
}

# end_check: run_ui's exit trap: ends the check and removes its directory.
end_check() {
	stop_check "$TPP_CHECK_DIR"
	rm -rf "$TPP_CHECK_DIR"
}

# The r key with fzf 0.73 and newer: ends the check that runs, if any, and
# starts it again.
cmd_recheck() {
	[[ -n ${TPP_CHECK_DIR-} && -d $TPP_CHECK_DIR ]] || return 1
	stop_check "$TPP_CHECK_DIR"
	rm -f "$TPP_CHECK_DIR/records"
	start_check "$TPP_CHECK_DIR"
}

# cmd_preview <name>: the preview of plugin <name>. While the list shows the
# check's frames, fzf runs the preview again for every frame, so the preview
# goes into a cache in the check's directory (see preview_cache_file): it is
# made once while the plugin's fetch runs and once after the fetch has
# ended, and read from the cache at the top of this script from then on.
cmd_preview() {
	local name=$1 text
	if ! preview_cache_file "$name"; then
		tpp_preview "$name"
		return
	fi
	text=$(tpp_preview "$name")
	mkdir -p "${PREVIEW_CACHE_FILE%/*}" && write_file "$PREVIEW_CACHE_FILE" "$text"
	printf '%s\n' "$text"
}

# The list. With fzf 0.73 and newer, it shows the check (see run_check),
# which starts before fzf; with older fzf, fzf's load event runs the fetches
# and then loads the status.
run_ui() {
	local self refresh check=0
	local -a load
	self=$(printf '%q' "$SELF")
	if tpp_version_ge "$FZF_VERSION" "$TPP_CHECK_FZF" && TPP_CHECK_DIR=$(mktemp -d); then
		check=1
		export TPP_CHECK_DIR
		# bash runs the exit trap also when SIGHUP or SIGTERM ends it, as
		# when the popup is closed.
		trap end_check EXIT
		tpp_collect_checking >"$TPP_CHECK_DIR/records"
		start_check "$TPP_CHECK_DIR"
		# --id-nth keeps the marks (tab) across the frames' reloads.
		# --no-track: with --id-nth, --track (for example from
		# FZF_DEFAULT_OPTS) can delay or drop keys while the frames reload
		# (seen with fzf 0.74).
		load=(--id-nth 1 --no-track --bind "every(0.1):transform(cat $(printf '%q' "$TPP_CHECK_DIR")/action)")
		refresh="r:execute-silent($self recheck)+rebind(every(0.1))"
	else
		load=(--bind "load:reload-sync($self rows --fetch)+unbind(load)")
		refresh="r:reload-sync($self rows --fetch)"
	fi
	if ((check)); then
		tpp_format_rows <"$TPP_CHECK_DIR/records"
	else
		tpp_collect_checking | tpp_format_rows
	fi |
		fzf --multi --ansi --no-sort --layout=reverse --disabled \
			--delimiter $'\t' --with-nth 2.. --header-lines 1 \
			--prompt '' --info default --no-separator --header "$(header)" \
			--preview "$self preview {1}" --preview-window 'down,50%,wrap' \
			"${load[@]}" \
			--bind 'change:clear-query' \
			--bind 'j:down' \
			--bind 'k:up' \
			--bind 'J:preview-down' \
			--bind 'K:preview-up' \
			--bind 'ctrl-d:preview-half-page-down' \
			--bind 'ctrl-u:preview-half-page-up' \
			--bind "enter:execute($self update {+1})+reload-sync($self rows)" \
			--bind "u:execute($self update {+1})+reload-sync($self rows)" \
			--bind "U:execute($self update all)+reload-sync($self rows)" \
			--bind "a:execute($self add)+reload-sync($self rows)" \
			--bind "d:execute($self remove {+1})+reload-sync($self rows)" \
			--bind "i:execute($self install)+reload-sync($self rows)" \
			--bind "c:execute($self clean)+reload-sync($self rows)" \
			--bind "$refresh" \
			--bind 'q:abort' >/dev/null
	return 0
}

main() {
	local cmd=${1-ui}
	(($#)) && shift
	tpp_disable_credential_helpers
	if [[ $cmd == ui ]]; then
		check_dependencies
		tpp_init || fail_and_exit "$TPP_MSG_CANNOT_START"
		run_ui
		return
	fi
	tpp_init || exit 1
	case $cmd in
	# The actions write to the terminal themselves: fzf before 0.53 gives an
	# execute'd command fzf's own stdout, which run_ui sends to /dev/null.
	# Here, and not in the bindings, because fzf runs a binding's command
	# with the user's $SHELL, which need not understand a redirection.
	# A running check ends first: its fetches must not run git beside the
	# action's, and its frames must not replace the rows the action's reload
	# loads.
	update | install | clean | add | remove)
		[[ -n ${TPP_CHECK_DIR-} ]] && stop_check "$TPP_CHECK_DIR"
		exec >/dev/tty 2>&1
		;;
	esac
	case $cmd in
	rows)
		[[ ${1-} == --fetch ]] && tpp_fetch_all
		tpp_collect | tpp_format_rows
		;;
	preview) cmd_preview "$1" ;;
	check) run_check "${1-}" ;;
	recheck) cmd_recheck ;;
	update) cmd_update "$@" ;;
	install) cmd_install ;;
	clean) cmd_clean ;;
	add) cmd_add ;;
	remove) cmd_remove "$@" ;;
	*)
		tpp_err "$(tpp_msg_unknown_command "$cmd")"
		exit 2
		;;
	esac
}

main "$@"
