#!/usr/bin/env bash
#
# The plugin panel. Without arguments it opens the fzf list; the other
# subcommands are what the list's key bindings call.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$CURRENT_DIR/panel.sh"
TPP_MIN_FZF=0.36

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

# hints <key> <action> [<key> <action>...]: one line of key hints, "<key>
# <action>" joined by " · ".
hints() {
	local line=''
	while (($# >= 2)); do
		line+="${line:+ · }$1 $2"
		shift 2
	done
	printf '%s' "$line"
}

header() {
	local plugin_dir=${TPP_PLUGIN_DIR/#$HOME/\~} panel_file=${TPP_PANEL_FILE/#$HOME/\~}
	printf '%s\n' "$(tpp_msg_header "$plugin_dir" "$panel_file")"
	hints enter/u "$TPP_MSG_HINT_UPDATE" U "$TPP_MSG_HINT_ALL" a "$TPP_MSG_HINT_ADD" \
		d "$TPP_MSG_HINT_REMOVE" i "$TPP_MSG_HINT_INSTALL" c "$TPP_MSG_HINT_CLEAN" \
		r "$TPP_MSG_HINT_REFRESH" tab "$TPP_MSG_HINT_MARK" q "$TPP_MSG_HINT_QUIT"
	printf '\n'
	hints j/k "$TPP_MSG_HINT_MOVE" J/K "$TPP_MSG_HINT_SCROLL" ctrl-d/ctrl-u "$TPP_MSG_HINT_SCROLL_HALF"
	if ! tpp_panel_file_sourced; then
		printf '\n\033[33m%s\033[0m' "$(tpp_msg_not_sourced "$panel_file" "${TPP_USER_CONF/#$HOME/\~}")"
	fi
}

run_ui() {
	local self
	self=$(printf '%q' "$SELF")
	tpp_collect_checking | tpp_format_rows |
		fzf --multi --ansi --no-sort --layout=reverse --disabled \
			--delimiter $'\t' --with-nth 2.. --header-lines 1 \
			--prompt '' --info default --no-separator --header "$(header)" \
			--preview "$self preview {1}" --preview-window 'down,50%,wrap' \
			--bind "load:reload-sync($self rows --fetch)+unbind(load)" \
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
			--bind "r:reload-sync($self rows --fetch)" \
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
	update | install | clean | add | remove) exec >/dev/tty 2>&1 ;;
	esac
	case $cmd in
	rows)
		[[ ${1-} == --fetch ]] && tpp_fetch_all
		tpp_collect | tpp_format_rows
		;;
	preview) tpp_preview "$1" ;;
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
