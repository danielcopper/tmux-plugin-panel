# shellcheck shell=bash
#
# Functions shared by the panel and the tests. Sourcing this file only
# defines constants and functions, and loads the messages in the panel's
# language (TPP_LANG, see tpp_language). tpp_init asks the tmux server for
# the plugin directory and options, and sources TPM's helpers; call it before
# anything that reads declarations or plugin directories.
#
# Globals set by tpp_init:
#   TPP_PLUGIN_DIR  plugin directory, with a trailing slash
#   TPP_TPM_DIR     TPM checkout inside it
#   TPP_USER_CONF   the user's tmux config file, as TPM finds it
#   TPP_PANEL_FILE  the one file the panel writes declarations to

TPP_FETCH_TIMEOUT=10
TPP_MIN_TMUX=3.2
TPP_PLUGIN_LINE_RE='^[ \t]*set(-option)? +-g +@plugin'
TPP_SPINNER_FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
TPP_LANG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lang"

# The language the panel speaks: the language part of the first of LC_ALL,
# LC_MESSAGES and LANG that is not empty ("de" for de_DE.UTF-8), when
# TPP_LANG_DIR has a catalogue for it; "en" otherwise, and for C and POSIX.
tpp_language() {
	local locale=${LC_ALL:-${LC_MESSAGES:-${LANG:-}}} lang
	lang=${locale%%[_.@]*}
	case $lang in
	"" | *[!a-z]*) lang=en ;;
	esac
	[[ -f $TPP_LANG_DIR/$lang.sh ]] || lang=en
	printf '%s\n' "$lang"
}

# The messages: the English ones, then those of the panel's language over
# them, so a message the language's catalogue lacks is shown in English.
TPP_LANG=$(tpp_language)
# shellcheck source=scripts/lang/en.sh
source "$TPP_LANG_DIR/en.sh"
if [[ $TPP_LANG != en ]]; then
	# Any catalogue in TPP_LANG_DIR; shellcheck is pointed at the German one.
	# shellcheck source=scripts/lang/de.sh
	source "$TPP_LANG_DIR/$TPP_LANG.sh"
fi

tpp_err() {
	printf 'tmux-plugin-panel: %s\n' "$*" >&2
}

# Expands a leading "~" or "$HOME" the same way TPM's _manual_expansion does.
tpp_expand_path() {
	local path="${1/#\~/$HOME}"
	printf '%s\n' "${path/#\$HOME/$HOME}"
}

tpp_tmux_option() {
	local value
	value=$(tmux show-option -gqv "$1" 2>/dev/null)
	printf '%s\n' "${value:-$2}"
}

# tpp_version_ge <have> <want>: true when version <have> >= <want>.
# Compares up to three numeric components; letters ("3.3a") are ignored.
tpp_version_ge() {
	local -a have want
	local i h w
	IFS=. read -ra have <<<"$1"
	IFS=. read -ra want <<<"$2"
	for i in 0 1 2; do
		h=${have[i]:-0}
		w=${want[i]:-0}
		h=${h%%[!0-9]*}
		w=${w%%[!0-9]*}
		h=$((10#${h:-0}))
		w=$((10#${w:-0}))
		((h > w)) && return 0
		((h < w)) && return 1
	done
	return 0
}

# tpp_tmux_version_ok <tmux -V output>: true when tmux is new enough for
# display-popup. Builds without a version number ("tmux master") pass.
tpp_tmux_version_ok() {
	local version=$1
	[[ $version =~ ([0-9]+\.[0-9]+) ]] || return 0
	tpp_version_ge "${BASH_REMATCH[1]}" "$TPP_MIN_TMUX"
}

# Prints the plugin directory the way TPM resolves it: the tmux global
# environment variable TMUX_PLUGIN_MANAGER_PATH if set, otherwise the default
# TPM's own `tpm` script sets (XDG location when the config lives there, else
# ~/.tmux/plugins/). Always ends with a slash.
tpp_plugin_dir() {
	local env_line dir xdg_tmux="${XDG_CONFIG_HOME:-$HOME/.config}/tmux"
	env_line=$(tmux show-environment -g TMUX_PLUGIN_MANAGER_PATH 2>/dev/null) || env_line=
	if [[ $env_line == TMUX_PLUGIN_MANAGER_PATH=?* ]]; then
		dir=$(tpp_expand_path "${env_line#*=}")
	elif [[ -f $xdg_tmux/tmux.conf ]]; then
		dir="$xdg_tmux/plugins/"
	else
		dir="$HOME/.tmux/plugins/"
	fi
	[[ $dir == */ ]] || dir="$dir/"
	printf '%s\n' "$dir"
}

tpp_init() {
	TPP_PLUGIN_DIR=$(tpp_plugin_dir)
	TPP_TPM_DIR="${TPP_PLUGIN_DIR}tpm"
	if [[ ! -f $TPP_TPM_DIR/scripts/helpers/plugin_functions.sh ]]; then
		tpp_err "$(tpp_msg_tpm_not_found "$TPP_TPM_DIR")"
		return 1
	fi
	# TPM's helpers: _get_user_tmux_conf, _sourced_files, _manual_expansion,
	# plugin_name_helper, tpm_plugins_variable_name.
	# shellcheck source=/dev/null
	source "$TPP_TPM_DIR/scripts/helpers/plugin_functions.sh"
	TPP_USER_CONF=$(_get_user_tmux_conf)
	TPP_PANEL_FILE=$(tpp_expand_path "$(tpp_tmux_option @tmux-plugin-panel-file "$HOME/.config/tmux/plugins.conf")")
}

# Name of the plugin directory for a declaration, as TPM derives it.
tpp_plugin_name() {
	plugin_name_helper "${1%%#*}"
}

# The config files TPM reads declarations from: /etc/tmux.conf, the user's
# config and every file it sources (one level), each listed once.
# The source lines are split into words and globbed exactly as TPM does in
# `for file in $(_sourced_files); do cat $(_manual_expansion "$file")`, so a
# line with several paths or a trailing comment gives the same files as TPM.
# Words that are not files (such as "#") are printed too; the callers drop
# them (the -f test in tpp_declarations, the path comparison in
# tpp_panel_file_sourced). A relative word resolves against the panel's
# working directory (the popup starts in the pane's directory), which need
# not be the directory TPM ran in.
tpp_config_files() {
	{
		printf '%s\n' /etc/tmux.conf "$TPP_USER_CONF"
		local IFS=$' \t\n' word file
		for word in $(_sourced_files); do
			for file in $(_manual_expansion "$word"); do
				printf '%s\n' "$file"
			done
		done
	} | awk '!seen[$0]++'
}

# Prints "spec<TAB>file" for every @plugin declaration in one file, parsed
# with the same pattern TPM's tpm_plugins_list_helper uses.
tpp_declarations_in() {
	awk -v file="$1" -v re="$TPP_PLUGIN_LINE_RE" '
		$0 ~ re { gsub(/'\''/, ""); gsub(/"/, ""); if ($4 != "") print $4 "\t" file }
	' "$1" 2>/dev/null
}

# Prints "spec<TAB>source" for every declaration TPM would act on.
tpp_declarations() {
	local spec file option="${tpm_plugins_variable_name:-@tpm_plugins}"
	for spec in $(tpp_tmux_option "$option" ""); do
		printf '%s\t%s\n' "$spec" "$(tpp_msg_option_source "$option")"
	done
	while IFS= read -r file; do
		[[ -f $file ]] && tpp_declarations_in "$file"
	done < <(tpp_config_files)
}

# tpp_find_declaration <name>: prints "spec<TAB>source" of the first
# declaration whose plugin name is <name>; false when there is none.
tpp_find_declaration() {
	local name=$1 spec source
	while IFS=$'\t' read -r spec source; do
		[[ -n $spec ]] || continue
		if [[ $(tpp_plugin_name "$spec") == "$name" ]]; then
			printf '%s\t%s\n' "$spec" "$source"
			return 0
		fi
	done < <(tpp_declarations)
	return 1
}

# tpp_declared_outside_panel_file <name>: prints the source of the first
# declaration of <name> that is not in the panel file; false when none.
tpp_declared_outside_panel_file() {
	local spec source
	while IFS=$'\t' read -r spec source; do
		[[ -n $spec ]] || continue
		[[ $source == "$TPP_PANEL_FILE" || ($source -ef $TPP_PANEL_FILE) ]] && continue
		if [[ $(tpp_plugin_name "$spec") == "$1" ]]; then
			printf '%s\n' "$source"
			return 0
		fi
	done < <(tpp_declarations)
	return 1
}

# TPM's GitHub URLs as a credential.<url> pattern: TPM clones a plugin
# declared as owner/repo from https://git::@github.com/owner/repo, user "git"
# with an empty password at github.com over https.
TPP_TPM_CREDENTIAL_URL=https://git@github.com

# Makes every git process started from here on, the panel's own and those of
# TPM's scripts, run without credential helpers for TPM's GitHub URLs: an
# empty credential.<url>.helper for TPP_TPM_CREDENTIAL_URL clears the list of
# helpers for the URLs it matches. After every successful clone, fetch or
# pull, git hands the empty credentials in those URLs to the user's helpers
# to store; some (libsecret, KWallet) print an error for them. Other users
# and hosts keep their helpers. The setting is appended to the entries
# already in GIT_CONFIG_COUNT, and not added again when it is already the
# last entry, as it is when a subcommand inherits the environment of the
# list. GIT_CONFIG_COUNT needs git 2.31; older git ignores it. A
# GIT_CONFIG_COUNT that is not a number is left alone, git refuses to run
# with it anyway.
tpp_disable_credential_helpers() {
	local count=${GIT_CONFIG_COUNT:-0} key value setting="credential.$TPP_TPM_CREDENTIAL_URL.helper"
	[[ $count =~ ^[0-9]+$ ]] || return 0
	count=$((10#$count))
	if ((count > 0)); then
		key=GIT_CONFIG_KEY_$((count - 1))
		value=GIT_CONFIG_VALUE_$((count - 1))
		[[ ${!key-} == "$setting" && -z ${!value-} ]] && return 0
	fi
	export "GIT_CONFIG_KEY_$count=$setting" "GIT_CONFIG_VALUE_$count=" \
		"GIT_CONFIG_COUNT=$((count + 1))"
}

tpp_git() {
	local dir=$1
	shift
	LC_ALL=C GIT_TERMINAL_PROMPT=0 git -C "$dir" "$@"
}

# tpp_git_localized <dir> <arg>...: git for text the panel shows as git
# words it, in the panel's language: for English under LC_ALL=C, which git
# obeys over LANGUAGE; for another language with LANGUAGE set to it, which
# git obeys when the locale git finds in LC_ALL, LC_MESSAGES or LANG is
# installed (without it, git speaks English).
tpp_git_localized() {
	local dir=$1
	shift
	if [[ $TPP_LANG == en ]]; then
		LC_ALL=C git -C "$dir" "$@"
	else
		LANGUAGE=$TPP_LANG git -C "$dir" "$@"
	fi
}

# True when <dir> is the top level of its own git repository, so a plugin
# directory inside a dotfiles repo is not mistaken for a checkout.
tpp_is_git_checkout() {
	local top real
	top=$(tpp_git "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
	real=$(cd "$1" 2>/dev/null && pwd -P) || return 1
	[[ $top == "$real" ]]
}

# tpp_status <dir> <spec>: status of an installed, declared plugin.
tpp_status() {
	local dir=$1 spec=$2 behind ahead status=
	if ! tpp_is_git_checkout "$dir"; then
		echo "not a git repo"
		return
	fi
	if [[ $spec == *#* ]] || ! tpp_git "$dir" symbolic-ref -q HEAD >/dev/null; then
		echo "pinned"
		return
	fi
	if ! tpp_git "$dir" rev-parse -q --verify '@{u}' >/dev/null; then
		echo "no upstream"
		return
	fi
	behind=$(tpp_git "$dir" rev-list --count 'HEAD..@{u}')
	ahead=$(tpp_git "$dir" rev-list --count '@{u}..HEAD')
	((ahead > 0)) && status="↑$ahead"
	((behind > 0)) && status="${status:+$status }↓$behind"
	echo "${status:-✓}"
}

# Age of the local HEAD commit, as git words it in the panel's language, "-"
# when there is none. Never empty: the records are read with IFS=tab, which
# would collapse an empty field.
tpp_age() {
	local age=''
	tpp_is_git_checkout "$1" && age=$(tpp_git_localized "$1" log -1 --format=%cr 2>/dev/null)
	printf '%s\n' "${age:--}"
}

# tpp_ssh_command <dir>: the ssh command git would use for <dir>, in git's
# order (GIT_SSH_COMMAND, core.sshCommand, GIT_SSH, ssh), with
# "-o BatchMode=yes" appended so ssh fails instead of prompting over the fzf
# screen. plink and tortoiseplink reject -o, so a program whose name contains
# "plink" is left as it is.
tpp_ssh_command() {
	local cmd=${GIT_SSH_COMMAND-} program
	if [[ -z $cmd ]]; then
		cmd=$(git -C "$1" config core.sshCommand) || cmd=''
	fi
	if [[ -n $cmd ]]; then
		program=${cmd%%[[:space:]]*}
	elif [[ -n ${GIT_SSH-} ]]; then
		cmd=$(printf '%q' "$GIT_SSH")
		program=$GIT_SSH
	else
		cmd=ssh
		program=ssh
	fi
	[[ ${program##*/} == *plink* ]] || cmd="$cmd -o BatchMode=yes"
	printf '%s\n' "$cmd"
}

tpp_timeout_cmd() {
	if command -v timeout >/dev/null 2>&1; then
		echo timeout
	elif command -v gtimeout >/dev/null 2>&1; then
		echo gtimeout
	fi
}

# Starts a fetch of every git checkout in the plugin directory, all in
# parallel in the background, and returns without waiting for them. Each
# fetch is bounded by TPP_FETCH_TIMEOUT seconds when a timeout command is
# available. Sets the arrays TPP_FETCH_PIDS and TPP_FETCH_NAMES:
# TPP_FETCH_PIDS[i] is the process of the fetch of the plugin in directory
# TPP_FETCH_NAMES[i]. The process is the timeout command, which on SIGTERM
# passes the signal on to the fetch and everything the fetch started, or
# without one git itself.
tpp_fetch_start() {
	local dir timeout_cmd ssh_cmd
	TPP_FETCH_PIDS=()
	TPP_FETCH_NAMES=()
	timeout_cmd=$(tpp_timeout_cmd)
	for dir in "$TPP_PLUGIN_DIR"*/; do
		[[ -d $dir ]] || continue
		tpp_is_git_checkout "$dir" || continue
		ssh_cmd=$(tpp_ssh_command "$dir")
		if [[ -n $timeout_cmd ]]; then
			GIT_SSH_COMMAND=$ssh_cmd LC_ALL=C GIT_TERMINAL_PROMPT=0 \
				"$timeout_cmd" -k 2 "$TPP_FETCH_TIMEOUT" \
				git -C "$dir" fetch --quiet </dev/null >/dev/null 2>&1 &
		else
			GIT_SSH_COMMAND=$ssh_cmd LC_ALL=C GIT_TERMINAL_PROMPT=0 \
				git -C "$dir" fetch --quiet </dev/null >/dev/null 2>&1 &
		fi
		TPP_FETCH_PIDS+=("$!")
		dir=${dir%/}
		TPP_FETCH_NAMES+=("${dir##*/}")
	done
}

# Fetches every installed plugin in parallel (see tpp_fetch_start) and waits
# for all the fetches.
tpp_fetch_all() {
	tpp_fetch_start
	wait
}

# Prints one record per plugin, sorted by name:
#   name<TAB>status<TAB>age<TAB>spec<TAB>source
# Every declared plugin is listed once (the first declaration of a name wins),
# and so is every directory in the plugin directory without a declaration,
# as "not declared" (tpm itself is left out). age is "-" when unknown; spec
# and source are empty for undeclared directories. tpp_collect_checking
# prints the same rows without running git for the status: a declared plugin
# that is installed gets "checking…" (shown while the fetch runs); the other
# rows are unchanged. status is the same in every language; tpp_status_text
# gives the text the list shows for it.
tpp_collect() {
	tpp_collect_records status
}

tpp_collect_checking() {
	tpp_collect_records checking
}

# tpp_collect_records <status|checking>: the implementation of both.
tpp_collect_records() {
	local checking=0 decls spec source name dir status age
	[[ $1 == checking ]] && checking=1
	decls=$(tpp_declarations)
	{
		local seen=$'\n'
		while IFS=$'\t' read -r spec source; do
			[[ -n $spec ]] || continue
			name=$(tpp_plugin_name "$spec")
			[[ $seen == *$'\n'"$name"$'\n'* ]] && continue
			seen+="$name"$'\n'
			dir="$TPP_PLUGIN_DIR$name"
			age=-
			if [[ ! -d $dir ]]; then
				status="not installed"
			elif ((checking)); then
				status="checking…"
				age=$(tpp_age "$dir")
			else
				status=$(tpp_status "$dir" "$spec")
				age=$(tpp_age "$dir")
			fi
			printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$status" "$age" "$spec" "$source"
		done <<<"$decls"
		for dir in "$TPP_PLUGIN_DIR"*/; do
			[[ -d $dir ]] || continue
			name=$(basename "$dir")
			[[ $name == tpm || $seen == *$'\n'"$name"$'\n'* ]] && continue
			age=$(tpp_age "$dir")
			printf '%s\t%s\t%s\t\t\n' "$name" "not declared" "$age"
		done
	} | LC_ALL=C sort -t $'\t' -k1,1
}

tpp_status_color() {
	case $1 in
	✓) printf '\033[32m' ;;
	*↓*) printf '\033[33m' ;;
	*↑*) printf '\033[36m' ;;
	"not installed") printf '\033[31m' ;;
	"not declared") printf '\033[35m' ;;
	pinned) printf '\033[34m' ;;
	*) printf '\033[2m' ;;
	esac
}

# tpp_status_text <status>: the text the list shows for a status from
# tpp_collect: the symbols (✓, ↑N, ↓M) as they are, the words in the panel's
# language. In the check's frames (fzf 0.73 and newer, see panel.sh) the
# status of a plugin whose fetch runs is "checking <mark>", shown as
# tpp_msg_status_checking <mark>; run_check puts the spinner's current frame
# in place of the mark.
tpp_status_text() {
	case $1 in
	"checking…") printf '%s\n' "$TPP_MSG_STATUS_CHECKING" ;;
	"checking "*) printf '%s\n' "$(tpp_msg_status_checking "${1#checking }")" ;;
	"not installed") printf '%s\n' "$TPP_MSG_STATUS_NOT_INSTALLED" ;;
	"not declared") printf '%s\n' "$TPP_MSG_STATUS_NOT_DECLARED" ;;
	pinned) printf '%s\n' "$TPP_MSG_STATUS_PINNED" ;;
	"no upstream") printf '%s\n' "$TPP_MSG_STATUS_NO_UPSTREAM" ;;
	"not a git repo") printf '%s\n' "$TPP_MSG_STATUS_NOT_GIT" ;;
	*) printf '%s\n' "$1" ;;
	esac
}

# tpp_status_width: the width of the list's status column: its longest
# status word or its header, whichever is longer, and two spaces. The counts
# (↑N ↓M) are not measured: with up to five digits each they are narrower
# than the longest English or German status word.
# The width does not depend on the rows, so it stays the same when the
# checking rows give way to the real status.
tpp_status_width() {
	local text width=0
	for text in "$TPP_MSG_COLUMN_STATUS" "$TPP_MSG_STATUS_CHECKING" \
		"$(tpp_msg_status_checking "${TPP_SPINNER_FRAMES[0]}")" "$TPP_MSG_STATUS_NOT_INSTALLED" \
		"$TPP_MSG_STATUS_NOT_DECLARED" "$TPP_MSG_STATUS_PINNED" "$TPP_MSG_STATUS_NO_UPSTREAM" \
		"$TPP_MSG_STATUS_NOT_GIT"; do
		((${#text} > width)) && width=${#text}
	done
	printf '%s\n' $((width + 2))
}

# tpp_github_path <url>: for a GitHub URL in any common form, prints the
# path after the host without a trailing slash or ".git" (owner/repo for a
# well-formed URL); false for any other input.
tpp_github_path() {
	local path
	case $1 in
	https://github.com/* | http://github.com/* | https://www.github.com/* | git://github.com/* | \
		ssh://git@github.com/* | git@github.com:* | github.com/*) ;;
	*) return 1 ;;
	esac
	path=${1#*github.com}
	path=${path#[:/]}
	path=${path%/}
	printf '%s\n' "${path%.git}"
}

# tpp_display_name <spec>: the name the list shows for a declaration: the
# spec without its "#branch", with a GitHub URL shortened to owner/repo.
# Other URLs are shown as declared.
tpp_display_name() {
	local spec=${1%%#*} path
	if path=$(tpp_github_path "$spec") && [[ $path =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
		spec=$path
	fi
	printf '%s\n' "$spec"
}

# tpp_label <name> <spec>: the name the list and the preview show for the
# plugin in directory <name>: tpp_display_name of its declaration, or <name>
# itself when there is no declaration (empty <spec>).
tpp_label() {
	if [[ -n $2 ]]; then
		tpp_display_name "$2"
	else
		printf '%s\n' "$1"
	fi
}

# tpp_style_label <label> <spec>: <label> from tpp_label with ANSI styles:
# owner/repo with "owner/" dim and "repo" bold; the directory name of a
# plugin without a declaration (empty <spec>) bold; any other URL plain.
tpp_style_label() {
	local label=$1
	if [[ -z $2 ]]; then
		printf '\033[1m%s\033[0m\n' "$label"
	elif [[ $label =~ ^([A-Za-z0-9_.-]+/)([A-Za-z0-9_.-]+)$ ]]; then
		printf '\033[2m%s\033[0m\033[1m%s\033[0m\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
	else
		printf '%s\n' "$label"
	fi
}

# Turns records from tpp_collect into fzf rows: "name<TAB>display". The
# display starts with the styled tpp_label; the column is padded to the
# widest label as shown, without its escape codes. The status follows as
# tpp_status_text, in a column tpp_status_width wide. The first line is the
# dim column header, with the same widths and an empty name; the panel runs
# fzf with --header-lines=1, so it is shown above the rows and cannot be
# selected.
tpp_format_rows() {
	local -a names labels label_widths statuses ages
	local name status age spec _source label width=10 status_width text i pad
	status_width=$(tpp_status_width)
	while IFS=$'\t' read -r name status age spec _source; do
		[[ -n $name ]] || continue
		label=$(tpp_label "$name" "$spec")
		names+=("$name")
		labels+=("$(tpp_style_label "$label" "$spec")")
		label_widths+=("${#label}")
		statuses+=("$status")
		ages+=("$age")
		((${#label} > width)) && width=${#label}
	done
	((${#TPP_MSG_COLUMN_PLUGIN} > width)) && width=${#TPP_MSG_COLUMN_PLUGIN}
	printf -v pad '%*s' $((width + 2 - ${#TPP_MSG_COLUMN_PLUGIN})) ''
	printf '\t\033[2m%s%s' "$TPP_MSG_COLUMN_PLUGIN" "$pad"
	printf -v pad '%*s' $((status_width - ${#TPP_MSG_COLUMN_STATUS})) ''
	printf '%s%s%s\033[0m\n' "$TPP_MSG_COLUMN_STATUS" "$pad" "$TPP_MSG_COLUMN_AGE"
	for i in "${!names[@]}"; do
		status=${statuses[i]}
		text=$(tpp_status_text "$status")
		printf -v pad '%*s' $((width - label_widths[i] + 2)) ''
		printf '%s\t%s%s%s' "${names[i]}" "${labels[i]}" "$pad" "$(tpp_status_color "$status")"
		printf -v pad '%*s' $((status_width - ${#text})) ''
		printf '%s\033[0m%s\033[2m%s\033[0m\n' "$text" "$pad" "${ages[i]}"
	done
}

# Normalises user input to a declaration TPM accepts. GitHub URLs in any
# common form become "owner/repo"; other git URLs are kept as they are.
# An optional "#branch" suffix is carried over.
tpp_normalize_spec() {
	local input=$1 url branch='' spec
	input="${input#"${input%%[![:space:]]*}"}"
	input="${input%"${input##*[![:space:]]}"}"
	if [[ -z $input ]]; then
		tpp_err "$TPP_MSG_NO_PLUGIN_GIVEN"
		return 1
	fi
	if [[ $input == *[[:space:]\'\"\\\;]* ]]; then
		tpp_err "$(tpp_msg_invalid_characters "$input")"
		return 1
	fi
	url=${input%%#*}
	if [[ $input == *#* ]]; then
		branch=${input#*#}
		if [[ -z $branch || $branch == *#* ]]; then
			tpp_err "$(tpp_msg_invalid_branch "$input")"
			return 1
		fi
	fi
	if spec=$(tpp_github_path "$url"); then
		if [[ ! $spec =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
			tpp_err "$(tpp_msg_invalid_github_url "$url")"
			return 1
		fi
	elif [[ $url == *://* || $url == *@*:* ]]; then
		spec=${url%/}
	else
		spec=${url%.git}
		if [[ ! $spec =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
			tpp_err "$(tpp_msg_invalid_plugin "$url")"
			return 1
		fi
	fi
	case $(tpp_plugin_name "$spec") in
	"" | . | ..)
		tpp_err "$(tpp_msg_no_repository_name "$url")"
		return 1
		;;
	esac
	printf '%s%s\n' "$spec" "${branch:+#$branch}"
}

# Refuses to write when the panel file is the user's tmux config.
tpp_panel_file_writable() {
	if [[ $TPP_PANEL_FILE == "$TPP_USER_CONF" || ($TPP_PANEL_FILE -ef $TPP_USER_CONF) ]]; then
		tpp_err "$(tpp_msg_panel_file_is_config "$TPP_USER_CONF")"
		return 1
	fi
}

# True when TPM reads the panel file, i.e. the user's config sources it.
tpp_panel_file_sourced() {
	local file
	while IFS= read -r file; do
		[[ $file == "$TPP_PANEL_FILE" || ($file -ef $TPP_PANEL_FILE) ]] && return 0
	done < <(tpp_config_files)
	return 1
}

# tpp_add <input>: appends a declaration for <input> to the panel file.
# Prints the normalised spec on success.
tpp_add() {
	local spec name existing
	spec=$(tpp_normalize_spec "$1") || return 1
	name=$(tpp_plugin_name "$spec")
	if existing=$(tpp_find_declaration "$name"); then
		tpp_err "$(tpp_msg_already_declared "$name" "${existing%%$'\t'*}" "${existing#*$'\t'}")"
		return 1
	fi
	tpp_panel_file_writable || return 1
	mkdir -p "$(dirname "$TPP_PANEL_FILE")" || return 1
	if [[ -s $TPP_PANEL_FILE && -n $(tail -c 1 "$TPP_PANEL_FILE") ]]; then
		printf '\n' >>"$TPP_PANEL_FILE" || return 1
	fi
	printf "set -g @plugin '%s'\n" "$spec" >>"$TPP_PANEL_FILE" || return 1
	printf '%s\n' "$spec"
}

# True when the panel file declares plugin <name>.
tpp_panel_file_declares() {
	local spec _source
	[[ -f $TPP_PANEL_FILE ]] || return 1
	while IFS=$'\t' read -r spec _source; do
		[[ $(tpp_plugin_name "$spec") == "$1" ]] && return 0
	done < <(tpp_declarations_in "$TPP_PANEL_FILE")
	return 1
}

# Removes every declaration of plugin <name> from the panel file. The file
# is rewritten in place so a symlinked file stays a symlink.
tpp_remove_declaration() {
	local name=$1 tmp
	[[ -f $TPP_PANEL_FILE ]] || return 0
	tpp_panel_file_writable || return 1
	tmp=$(mktemp "${TPP_PANEL_FILE}.XXXXXX") || return 1
	if ! awk -v target="$name" -v re="$TPP_PLUGIN_LINE_RE" '
		$0 ~ re {
			line = $0
			gsub(/'\''/, "", line); gsub(/"/, "", line)
			split(line, f)
			spec = f[4]; sub(/#.*/, "", spec); sub(/\/+$/, "", spec)
			n = split(spec, parts, "/"); name = parts[n]; sub(/\.git$/, "", name)
			if (name == target) next
		}
		{ print }
	' "$TPP_PANEL_FILE" >"$tmp"; then
		rm -f "$tmp"
		return 1
	fi
	cat "$tmp" >"$TPP_PANEL_FILE"
	local rc=$?
	rm -f "$tmp"
	return $rc
}

# tpp_remove <name>: removes the plugin's declaration from the panel file and
# deletes its directory. A plugin declared anywhere else is left alone, panel
# file line included, and a hint names the file to edit. tpm itself is never
# removed. Surrounding whitespace in <name> is ignored; when there is neither
# a line nor a directory, it says "nothing to remove" and succeeds.
tpp_remove() {
	local name=$1 source dir had_line=0 had_dir=0
	name="${name#"${name%%[![:space:]]*}"}"
	name="${name%"${name##*[![:space:]]}"}"
	case $name in
	"" | . | .. | */* | *$'\n'*)
		tpp_err "$(tpp_msg_invalid_name "$name")"
		return 1
		;;
	tpm)
		tpp_err "$TPP_MSG_REFUSE_TPM"
		return 1
		;;
	esac
	if [[ -z $TPP_PLUGIN_DIR || $TPP_PLUGIN_DIR == / ]]; then
		tpp_err "$TPP_MSG_NO_PLUGIN_DIR"
		return 1
	fi
	if source=$(tpp_declared_outside_panel_file "$name"); then
		tpp_err "$(tpp_msg_declared_elsewhere "$name" "$source")"
		return 1
	fi
	tpp_panel_file_declares "$name" && had_line=1
	dir="${TPP_PLUGIN_DIR%/}/$name"
	[[ -e $dir || -L $dir ]] && had_dir=1
	if ((!had_line && !had_dir)); then
		printf '%s\n' "$(tpp_msg_nothing_to_remove "$name")"
		return 0
	fi
	if ((had_line)); then
		tpp_remove_declaration "$name" || return 1
	fi
	if ((had_dir)); then
		# No trailing slash: a symlinked plugin directory loses the link only.
		rm -rf -- "$dir" || return 1
	fi
	printf '%s\n' "$(tpp_msg_removed "$name")"
}

# tpp_head <dir>: the commit checked out in plugin directory <dir>; false
# when <dir> is not a git checkout.
tpp_head() {
	tpp_is_git_checkout "$1" || return 1
	tpp_git "$1" rev-parse -q --verify HEAD
}

# tpp_update_heads <all|name...>: prints "name<TAB>head<TAB>spec" for the
# plugins an update with the same arguments reports on, sorted by name. For
# "all": every declared plugin whose directory is a git checkout (TPM's
# update of all plugins skips a directory where `git remote` fails; outside
# an enclosing repository that is the same set, and tpp_update_summary shows
# TPM's output for a failed one it does not list). Otherwise: the named ones,
# each with head "-" when it has no commit (no directory, or not a git
# checkout). head is the commit checked out; spec is the first declaration
# of the plugin, empty when there is none. Unlike tpp_collect it reads no
# ages: the update needs only the commits.
tpp_update_heads() {
	local decls spec _source name names head seen=$'\n' declared=''
	decls=$(tpp_declarations)
	while IFS=$'\t' read -r spec _source; do
		[[ -n $spec ]] || continue
		name=$(tpp_plugin_name "$spec")
		[[ $seen == *$'\n'"$name"$'\n'* ]] && continue
		seen+="$name"$'\n'
		declared+="$name"$'\t'"$spec"$'\n'
	done <<<"$decls"
	if [[ $1 == all ]]; then
		names=$(cut -f 1 <<<"$declared" | LC_ALL=C sort)
	else
		names=$(for name; do tpp_plugin_name "${name%%#*}"; done | LC_ALL=C sort -u)
	fi
	while IFS= read -r name; do
		[[ -n $name ]] || continue
		if ! head=$(tpp_head "$TPP_PLUGIN_DIR$name"); then
			[[ $1 == all ]] && continue
			head=-
		fi
		spec=$(awk -F '\t' -v n="$name" '$1 == n { print $2; exit }' <<<"$declared")
		printf '%s\t%s\t%s\n' "$name" "$head" "$spec"
	done <<<"$names"
}

# tpp_update_summary <heads> <log> <status>: the result of TPM's update, one
# line per plugin in the file <heads> (from tpp_update_heads, written before
# the update): the plugin's name as the list shows it, then (the words in
# the panel's language)
#   "<old> → <new>"       the short commits, when its HEAD moved;
#   "already up to date"  when it did not;
#   "update failed"       when TPM's output in the file <log> says
#                         "update fail" for it, when it is not installed, or
#                         when TPM exited with a <status> other than 0 and
#                         its HEAD did not move.
# TPM's whole output follows when an update failed, when TPM's output says
# "update fail" for any plugin (also one not listed: TPM also pulls in a plain
# directory inside an enclosing repository), when TPM exited with a status
# other than 0, or when there is no plugin to list.
tpp_update_summary() {
	local heads=$1 log=$2 rc=$3 name old spec new dir label result failed=0 width=0 i pad
	local -a labels widths results
	while IFS=$'\t' read -r name old spec; do
		[[ -n $name ]] || continue
		dir="$TPP_PLUGIN_DIR$name"
		new=-
		if [[ $old != - ]]; then
			new=$(tpp_head "$dir") || new=-
		fi
		if [[ $old == - || $new == - ]] || grep -qxF "  \"$name\" update fail" "$log"; then
			result=$TPP_MSG_UPDATE_FAILED
			failed=1
		elif [[ $new != "$old" ]]; then
			result="$(tpp_git "$dir" rev-parse --short "$old") → $(tpp_git "$dir" rev-parse --short "$new")"
		elif ((rc)); then
			result=$TPP_MSG_UPDATE_FAILED
			failed=1
		else
			result=$TPP_MSG_UP_TO_DATE
		fi
		label=$(tpp_label "$name" "$spec")
		labels+=("$(tpp_style_label "$label" "$spec")")
		widths+=("${#label}")
		results+=("$result")
		((${#label} > width)) && width=${#label}
	done <"$heads"
	for i in "${!labels[@]}"; do
		printf -v pad '%*s' $((width - widths[i] + 2)) ''
		printf '%s%s%s\n' "${labels[i]}" "$pad" "${results[i]}"
	done
	grep -qE '^  ".*" update fail$' "$log" && failed=1
	if ((failed || rc || ${#labels[@]} == 0)); then
		((${#labels[@]})) && printf '\n'
		cat "$log"
	fi
	return 0
}

# tpp_preview_field <width> <label> <value>: one line of the preview: <label>
# padded to <width> characters, then two spaces and <value>.
tpp_preview_field() {
	local pad
	printf -v pad '%*s' $(($1 + 2 - ${#2})) ''
	printf '%s%s%s\n' "$2" "$pad" "$3"
}

# Preview text for one plugin. The values follow their labels in one column,
# two spaces after the longest label.
tpp_preview() {
	local name=$1 decl spec='' source='' dir url label width=0
	for label in "$TPP_MSG_PREVIEW_DECLARED" "$TPP_MSG_PREVIEW_IN" "$TPP_MSG_PREVIEW_PATH" "$TPP_MSG_PREVIEW_REPO"; do
		((${#label} > width)) && width=${#label}
	done
	dir="$TPP_PLUGIN_DIR$name"
	if decl=$(tpp_find_declaration "$name"); then
		spec=${decl%%$'\t'*}
		source=${decl#*$'\t'}
	fi
	printf '%s\n\n' "$(tpp_style_label "$(tpp_label "$name" "$spec")" "$spec")"
	if [[ -n $spec ]]; then
		tpp_preview_field "$width" "$TPP_MSG_PREVIEW_DECLARED" "$spec"
		tpp_preview_field "$width" "$TPP_MSG_PREVIEW_IN" "$source"
	else
		tpp_preview_field "$width" "$TPP_MSG_PREVIEW_DECLARED" "$TPP_MSG_PREVIEW_NOWHERE"
	fi
	if [[ ! -d $dir ]]; then
		url=${spec%%#*}
		[[ $url =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] && url="https://github.com/$url"
		tpp_preview_field "$width" "$TPP_MSG_PREVIEW_REPO" "$url"
		printf '\n%s\n' "$TPP_MSG_STATUS_NOT_INSTALLED"
		return
	fi
	tpp_preview_field "$width" "$TPP_MSG_PREVIEW_PATH" "$dir"
	if ! tpp_is_git_checkout "$dir"; then
		printf '\n%s\n' "$TPP_MSG_PREVIEW_NOT_GIT"
		return
	fi
	url=$(tpp_git "$dir" remote get-url origin 2>/dev/null)
	# TPM clones an owner/repo declaration from
	# https://git::@github.com/owner/repo, with credentials in the URL so
	# git does not prompt for any; the preview shows it without "git::@".
	# Any other URL is shown as it is.
	url=${url/#https:\/\/git::@github.com\//https://github.com/}
	tpp_preview_field "$width" "$TPP_MSG_PREVIEW_REPO" "${url:-$TPP_MSG_PREVIEW_NO_ORIGIN}"
	if ! tpp_git "$dir" rev-parse -q --verify '@{u}' >/dev/null; then
		printf '\n%s\n' "$TPP_MSG_PREVIEW_NO_UPSTREAM"
		return
	fi
	local pending
	pending=$(git -C "$dir" log --oneline --no-decorate 'HEAD..@{u}' 2>/dev/null)
	if [[ -n $pending ]]; then
		printf '\n%s\n%s\n' "$TPP_MSG_PREVIEW_PENDING" "$pending"
	else
		printf '\n%s\n' "$TPP_MSG_PREVIEW_NO_PENDING"
	fi
}

# tpp_spinner <message> <owner>: the spinner line of tpp_spin, run in the
# background: "<message> ⠋", with the frame turning every 0.1 s until it is
# killed, process <owner> is gone, or the terminal it started on is gone. It
# draws nothing while the terminal's modes differ from those it started with:
# a program asking for a passphrase (ssh) turns echo off while it waits for
# the answer. Every redraw saves and restores the cursor (ESC 7, ESC 8), so a
# prompt printed on the spinner's line keeps its cursor where the answer
# goes. Without a terminal at the start (no /dev/tty), it draws every frame
# and does not check the terminal's modes.
tpp_spinner() {
	local message=$1 owner=$2 modes now i=1
	modes=$(stty -g 2>/dev/null </dev/tty)
	printf '\r%s %s' "$message" "${TPP_SPINNER_FRAMES[0]}"
	while sleep 0.1 && kill -0 "$owner" 2>/dev/null; do
		if [[ -n $modes ]]; then
			now=$(stty -g 2>/dev/null </dev/tty) || return 0
			[[ $now == "$modes" ]] || continue
		fi
		printf '\0337\r%s %s\0338' "$message" "${TPP_SPINNER_FRAMES[i++ % ${#TPP_SPINNER_FRAMES[@]}]}" ||
			return 0
	done
}

# tpp_spin <message> <log> <command> [<arg>...]: runs <command> in the
# foreground with its output (stdout and stderr) in the file <log>, while
# tpp_spinner shows "<message> ⠋" in the background; then clears the line.
# Returns the command's exit status.
#
# The command gets a process group of its own, which a child shell with job
# control (set -m) makes the terminal's foreground group, as an interactive
# shell does: a prompt the command shows on the terminal (ssh asking for a
# passphrase) can read the answer, and Ctrl-C reaches the command's group
# only. The child shell is needed because bash, with job control on, answers
# a foreground job killed by Ctrl-C by interrupting itself. Whatever is left
# in the group afterwards (TPM's background jobs ignore SIGINT) is sent
# SIGTERM, then SIGCONT so that a member stopped by job control (for example
# by SIGTTIN) wakes up and receives it.
tpp_spin() {
	# The owner is taken here: the words of a background command are expanded
	# in the forked child, where $BASHPID would be the spinner's own pid.
	# $$ (bash 3.2 has no BASHPID) is the script's shell, which runs tpp_spin.
	local message=$1 log=$2 owner=$$ group spinner rc
	shift 2
	group=$(mktemp) || return 1
	tpp_spinner "$message" "$owner" &
	spinner=$!
	bash -c 'set -m; log=$1; shift; "$@" >"$log" 2>&1 & echo "$!" >"$0"; fg %% >/dev/null' \
		"$group" "$log" "$@"
	rc=$?
	if [[ -s $group ]]; then
		kill -TERM -- "-$(<"$group")" 2>/dev/null
		kill -CONT -- "-$(<"$group")" 2>/dev/null
	fi
	rm -f "$group"
	kill "$spinner" 2>/dev/null
	wait "$spinner" 2>/dev/null
	printf '\r\033[K'
	return "$rc"
}
