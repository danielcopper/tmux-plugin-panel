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
	printf '\n%s' "${1:-Press any key to return to the list.}"
	read -rsn1 _ </dev/tty
	printf '\n'
}

fail_and_exit() {
	tpp_err "$1"
	pause "Press any key to close."
	exit 1
}

confirm() {
	local answer
	printf '%s [y/N] ' "$1"
	read -r answer </dev/tty
	[[ $answer == [yY] || $answer == [yY][eE][sS] ]]
}

check_dependencies() {
	local cmd missing=() version
	for cmd in git fzf; do
		command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
	done
	if ((${#missing[@]})); then
		fail_and_exit "missing required command(s): ${missing[*]}"
	fi
	version=$(fzf --version 2>/dev/null)
	version=${version%% *}
	if ! tpp_version_ge "$version" "$TPP_MIN_FZF"; then
		fail_and_exit "fzf $TPP_MIN_FZF or newer is required (found ${version:-unknown})"
	fi
}

reload_tmux_config() {
	[[ -f $TPP_USER_CONF ]] || return 0
	tmux source-file "$TPP_USER_CONF" || tpp_err "reloading $TPP_USER_CONF failed"
}

warn_if_not_sourced() {
	tpp_panel_file_sourced && return 0
	printf '\nNote: %s is not sourced from %s, so TPM does not see its plugins.\n' \
		"$TPP_PANEL_FILE" "$TPP_USER_CONF"
	printf "Add this line before \"run '…/tpm/tpm'\":  source-file %s\n" "$TPP_PANEL_FILE"
}

cmd_update() {
	if (($# == 0)); then
		return 0
	fi
	clear_screen
	printf 'Updating: %s\n\n' "$*"
	"$TPP_TPM_DIR/bin/update_plugins" "$@"
	reload_tmux_config
	pause
}

cmd_install() {
	clear_screen
	printf 'Installing missing plugins\n\n'
	"$TPP_TPM_DIR/bin/install_plugins"
	reload_tmux_config
	pause
}

cmd_clean() {
	local undeclared
	clear_screen
	undeclared=$(tpp_collect_checking | awk -F '\t' '$2 == "not declared" { print "  " $1 }')
	if [[ -z $undeclared ]]; then
		pause "Nothing to clean. Press any key to return to the list."
		return
	fi
	printf 'Directories without a declaration:\n%s\n\n' "$undeclared"
	if confirm "Let TPM remove them?"; then
		"$TPP_TPM_DIR/bin/clean_plugins"
		reload_tmux_config
	fi
	pause
}

cmd_add() {
	local input spec
	clear_screen
	printf 'Add a plugin to %s\n' "$TPP_PANEL_FILE"
	printf 'owner/repo, a GitHub URL or any git URL, optionally with #branch\n\n'
	read -rp 'plugin: ' input </dev/tty
	if [[ -z $input ]]; then
		return
	fi
	if spec=$(tpp_add "$input"); then
		printf "\nAdded: set -g @plugin '%s'\n" "$spec"
		warn_if_not_sourced
		printf '\n'
		"$TPP_TPM_DIR/bin/install_plugins"
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
			printf 'tpm is not removed here.\n'
		elif source=$(tpp_declared_outside_panel_file "$name"); then
			printf '%s is declared in %s, remove the line there.\n' "$name" "$source"
		else
			removable+=("$name")
		fi
	done
	if ((${#removable[@]} == 0)); then
		pause
		return
	fi
	printf '\nRemove: %s\n' "${removable[*]}"
	if ! confirm "Delete their lines in $TPP_PANEL_FILE and their directories?"; then
		return
	fi
	for name in "${removable[@]}"; do
		tpp_remove "$name" || failed=1
	done
	reload_tmux_config
	((failed)) && printf '\nSome plugins were not removed, see above.\n'
	pause
}

header() {
	local plugin_dir=${TPP_PLUGIN_DIR/#$HOME/\~} panel_file=${TPP_PANEL_FILE/#$HOME/\~}
	printf 'plugins %s   file %s\n' "$plugin_dir" "$panel_file"
	printf 'enter/u update · U all · a add · d remove · i install · c clean · r refresh · tab mark · q quit\n'
	printf 'j/k move · J/K scroll preview · ctrl-d/ctrl-u scroll preview by half a page'
	if ! tpp_panel_file_sourced; then
		printf '\n\033[33m%s is not sourced from %s\033[0m' "$panel_file" "${TPP_USER_CONF/#$HOME/\~}"
	fi
}

run_ui() {
	local self
	self=$(printf '%q' "$SELF")
	tpp_collect_checking | tpp_format_rows |
		fzf --multi --ansi --no-sort --layout=reverse --disabled \
			--delimiter $'\t' --with-nth 2.. \
			--prompt '' --info hidden --header "$(header)" \
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
	if [[ $cmd == ui ]]; then
		check_dependencies
		tpp_init || fail_and_exit "cannot start"
		run_ui
		return
	fi
	tpp_init || exit 1
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
		tpp_err "unknown command: $cmd"
		exit 2
		;;
	esac
}

main "$@"
