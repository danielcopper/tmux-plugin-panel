# shellcheck shell=bash
#
# Functions shared by the panel and the tests. Sourcing this file only
# defines constants and functions. tpp_init asks the tmux server for the plugin
# directory and options, and sources TPM's helpers; call it before anything
# that reads declarations or plugin directories.
#
# Globals set by tpp_init:
#   TPP_PLUGIN_DIR  plugin directory, with a trailing slash
#   TPP_TPM_DIR     TPM checkout inside it
#   TPP_USER_CONF   the user's tmux config file, as TPM finds it
#   TPP_PANEL_FILE  the one file the panel writes declarations to

TPP_FETCH_TIMEOUT=10
TPP_MIN_TMUX=3.2
TPP_PLUGIN_LINE_RE='^[ \t]*set(-option)? +-g +@plugin'

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
		tpp_err "TPM not found in $TPP_TPM_DIR"
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
		printf '%s\t%s\n' "$spec" "$option option"
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

tpp_git() {
	local dir=$1
	shift
	LC_ALL=C GIT_TERMINAL_PROMPT=0 git -C "$dir" "$@"
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

# Age of the local HEAD commit, "-" when there is none. Never empty: the
# records are read with IFS=tab, which would collapse an empty field.
tpp_age() {
	local age=''
	tpp_is_git_checkout "$1" && age=$(git -C "$1" log -1 --format=%cr 2>/dev/null)
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

# Fetches every installed plugin in parallel. Each fetch is bounded by
# TPP_FETCH_TIMEOUT seconds when a timeout command is available.
tpp_fetch_all() {
	local dir timeout_cmd ssh_cmd
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
			GIT_SSH_COMMAND=$ssh_cmd tpp_git "$dir" fetch --quiet </dev/null >/dev/null 2>&1 &
		fi
	done
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
# rows are unchanged.
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

# Turns records from tpp_collect into fzf rows: "name<TAB>display".
tpp_format_rows() {
	local -a names statuses ages
	local name status age _spec _source width=10 i pad
	while IFS=$'\t' read -r name status age _spec _source; do
		[[ -n $name ]] || continue
		names+=("$name")
		statuses+=("$status")
		ages+=("$age")
		((${#name} > width)) && width=${#name}
	done
	for i in "${!names[@]}"; do
		name=${names[i]}
		status=${statuses[i]}
		printf -v pad '%*s' $((width - ${#name} + 2)) ''
		printf '%s\t%s%s%s' "$name" "$name" "$pad" "$(tpp_status_color "$status")"
		printf -v pad '%*s' $((16 - ${#status})) ''
		printf '%s\033[0m%s\033[2m%s\033[0m\n' "$status" "$pad" "${ages[i]}"
	done
}

# Normalises user input to a declaration TPM accepts. GitHub URLs in any
# common form become "owner/repo"; other git URLs are kept as they are.
# An optional "#branch" suffix is carried over.
tpp_normalize_spec() {
	local input=$1 url branch='' path spec
	input="${input#"${input%%[![:space:]]*}"}"
	input="${input%"${input##*[![:space:]]}"}"
	if [[ -z $input ]]; then
		tpp_err "no plugin given"
		return 1
	fi
	if [[ $input == *[[:space:]\'\"\\\;]* ]]; then
		tpp_err "invalid plugin '$input': spaces, quotes and semicolons are not allowed"
		return 1
	fi
	url=${input%%#*}
	if [[ $input == *#* ]]; then
		branch=${input#*#}
		if [[ -z $branch || $branch == *#* ]]; then
			tpp_err "invalid branch in '$input'"
			return 1
		fi
	fi
	case $url in
	https://github.com/* | http://github.com/* | https://www.github.com/* | git://github.com/* | \
		ssh://git@github.com/* | git@github.com:* | github.com/*)
		path=${url#*github.com}
		path=${path#[:/]}
		path=${path%/}
		path=${path%.git}
		spec=$path
		if [[ ! $spec =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
			tpp_err "invalid GitHub URL '$url': expected github.com/owner/repo"
			return 1
		fi
		;;
	*://* | *@*:*)
		spec=${url%/}
		;;
	*)
		spec=${url%.git}
		if [[ ! $spec =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
			tpp_err "invalid plugin '$url': expected owner/repo or a git URL"
			return 1
		fi
		;;
	esac
	case $(tpp_plugin_name "$spec") in
	"" | . | ..)
		tpp_err "invalid plugin '$url': no repository name"
		return 1
		;;
	esac
	printf '%s%s\n' "$spec" "${branch:+#$branch}"
}

# Refuses to write when the panel file is the user's tmux config.
tpp_panel_file_writable() {
	if [[ $TPP_PANEL_FILE == "$TPP_USER_CONF" || ($TPP_PANEL_FILE -ef $TPP_USER_CONF) ]]; then
		tpp_err "@tmux-plugin-panel-file points at $TPP_USER_CONF; the panel never edits the tmux config"
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
		tpp_err "'$name' is already declared as '${existing%%$'\t'*}' in ${existing#*$'\t'}"
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
		tpp_err "invalid plugin name '$name'"
		return 1
		;;
	tpm)
		tpp_err "refusing to remove tpm"
		return 1
		;;
	esac
	if [[ -z $TPP_PLUGIN_DIR || $TPP_PLUGIN_DIR == / ]]; then
		tpp_err "plugin directory is not set"
		return 1
	fi
	if source=$(tpp_declared_outside_panel_file "$name"); then
		tpp_err "'$name' is declared in $source, remove the line there"
		return 1
	fi
	tpp_panel_file_declares "$name" && had_line=1
	dir="${TPP_PLUGIN_DIR%/}/$name"
	[[ -e $dir || -L $dir ]] && had_dir=1
	if ((!had_line && !had_dir)); then
		printf 'nothing to remove for %s\n' "$name"
		return 0
	fi
	if ((had_line)); then
		tpp_remove_declaration "$name" || return 1
	fi
	if ((had_dir)); then
		# No trailing slash: a symlinked plugin directory loses the link only.
		rm -rf -- "$dir" || return 1
	fi
	printf 'removed %s\n' "$name"
}

# Preview text for one plugin.
tpp_preview() {
	local name=$1 decl spec='' source='' dir url
	dir="$TPP_PLUGIN_DIR$name"
	if decl=$(tpp_find_declaration "$name"); then
		spec=${decl%%$'\t'*}
		source=${decl#*$'\t'}
	fi
	printf '%s\n\n' "$name"
	if [[ -n $spec ]]; then
		printf 'declared  %s\n' "$spec"
		printf 'in        %s\n' "$source"
	else
		printf 'declared  nowhere (not declared)\n'
	fi
	if [[ ! -d $dir ]]; then
		url=${spec%%#*}
		[[ $url =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] && url="https://github.com/$url"
		printf 'repo      %s\n' "$url"
		printf '\nnot installed\n'
		return
	fi
	printf 'path      %s\n' "$dir"
	if ! tpp_is_git_checkout "$dir"; then
		printf '\nnot a git repository\n'
		return
	fi
	url=$(tpp_git "$dir" remote get-url origin 2>/dev/null)
	printf 'repo      %s\n' "${url:-(no origin)}"
	if ! tpp_git "$dir" rev-parse -q --verify '@{u}' >/dev/null; then
		printf '\nno upstream branch\n'
		return
	fi
	local pending
	pending=$(git -C "$dir" log --oneline --no-decorate 'HEAD..@{u}' 2>/dev/null)
	if [[ -n $pending ]]; then
		printf '\npending commits:\n%s\n' "$pending"
	else
		printf '\nno pending commits\n'
	fi
}
