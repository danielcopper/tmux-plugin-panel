#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

DIM=$'\033[2m' BOLD=$'\033[1m' YELLOW=$'\033[33m' RESET=$'\033[0m'

setup() {
	load test_helper
	tpp_setup
	standard_env
}

teardown() {
	tpp_teardown
}

# messages_in <file>...: the messages the catalogue files define, sorted: the
# variables TPP_MSG_* and the functions tpp_msg_*.
messages_in() {
	bash -c '
		for file; do source "$file" || exit 1; done
		compgen -v TPP_MSG_
		compgen -A function tpp_msg_
	' _ "$@" | LC_ALL=C sort
}

@test "every catalogue defines the messages of the English one, and no others" {
	local english file
	english=$(messages_in "$TPP_ROOT/scripts/lang/en.sh")
	[ -n "$english" ]
	[ -f "$TPP_ROOT/scripts/lang/de.sh" ]
	for file in "$TPP_ROOT"/scripts/lang/*.sh; do
		[ "$(messages_in "$file")" = "$english" ] || {
			echo "${file##*/} differs from en.sh (< en.sh, > ${file##*/}):"
			diff <(printf '%s\n' "$english") <(messages_in "$file")
			return 1
		}
	done
}

# lang_for [<VAR>=<value>...]: the language the panel picks when, of the
# locale variables, only these are set. Its stderr is dropped, where bash
# may warn about a locale this machine does not have (see german in
# test_helper.bash).
lang_for() {
	(
		unset LC_ALL LC_MESSAGES LANG LANGUAGE
		(($#)) && declare -x "$@"
		bash -c 'source "$1/scripts/lib.sh" && printf "%s\n" "$TPP_LANG"' _ "$TPP_ROOT"
	) 2>/dev/null
}

@test "the language is the language part of the locale" {
	[ "$(lang_for LANG=de_DE.UTF-8)" = de ]
	[ "$(lang_for LANG=de_AT.UTF-8)" = de ]
	[ "$(lang_for LANG=de_DE@euro)" = de ]
	[ "$(lang_for LANG=de)" = de ]
	[ "$(lang_for LANG=en_US.UTF-8)" = en ]
}

@test "LC_ALL comes before LC_MESSAGES and LANG, LC_MESSAGES before LANG, empty ones are skipped" {
	[ "$(lang_for LC_ALL=C LANG=de_DE.UTF-8)" = en ]
	[ "$(lang_for LC_ALL=de_DE.UTF-8 LANG=en_US.UTF-8)" = de ]
	[ "$(lang_for LC_ALL=en_US.UTF-8 LC_MESSAGES=de_DE.UTF-8)" = en ]
	[ "$(lang_for LC_MESSAGES=de_DE.UTF-8 LANG=en_US.UTF-8)" = de ]
	[ "$(lang_for LC_MESSAGES=C LANG=de_DE.UTF-8)" = en ]
	[ "$(lang_for LC_ALL= LC_MESSAGES= LANG=de_DE.UTF-8)" = de ]
}

@test "C, POSIX and no locale at all are English" {
	[ "$(lang_for LANG=C)" = en ]
	[ "$(lang_for LC_ALL=C.UTF-8)" = en ]
	[ "$(lang_for LANG=POSIX)" = en ]
	[ "$(lang_for)" = en ]
}

@test "a language without a catalogue falls back to English" {
	[ "$(lang_for LANG=fr_FR.UTF-8)" = en ]
	[ "$(lang_for LANG=../../de)" = en ]
	# LANG, not LC_ALL: see german in test_helper.bash.
	unset LC_ALL
	LANG=fr_FR.UTF-8 run bash -c 'source "$1/scripts/lib.sh" && printf "%s\n" "$TPP_MSG_STATUS_PINNED" "$(tpp_msg_removed alpha)"' _ "$TPP_ROOT"
	[ "$status" -eq 0 ]
	[ "$output" = $'pinned\nremoved alpha' ]
}

@test "a message the chosen catalogue lacks is shown in English" {
	cp -R "$TPP_ROOT/scripts" "$TEST_ROOT/copy"
	grep -v -e '^TPP_MSG_STATUS_PINNED=' -e '^tpp_msg_removed()' "$TPP_ROOT/scripts/lang/de.sh" \
		>"$TEST_ROOT/copy/lang/de.sh"
	unset LC_ALL
	LANG=de_DE.UTF-8 run bash -c 'source "$1/lib.sh" && printf "%s\n" "$TPP_LANG" "$TPP_MSG_STATUS_PINNED" "$(tpp_msg_removed alpha)" "$TPP_MSG_STATUS_NOT_INSTALLED"' \
		_ "$TEST_ROOT/copy"
	[ "$status" -eq 0 ]
	[ "$output" = $'de\npinned\nremoved alpha\nnicht installiert' ]
}

# fake_fzf: a fake fzf first on PATH that records the arguments of the
# list's invocation in $TEST_ROOT/fzf-argv, each ended by a NUL (the header
# has several lines), and the rows it is given in $TEST_ROOT/fzf-input.
fake_fzf() {
	cat >"$TEST_ROOT/bin/fzf" <<EOF
#!/usr/bin/env bash
[[ \$1 == --version ]] && { echo "999.0.0 (fake)"; exit 0; }
printf '%s\0' "\$@" >"$TEST_ROOT/fzf-argv"
cat >"$TEST_ROOT/fzf-input"
EOF
	chmod +x "$TEST_ROOT/bin/fzf"
}

# fzf_option <name>: the value the fake fzf got for option <name>.
fzf_option() {
	local arg previous=
	while IFS= read -r -d '' arg; do
		if [[ $previous == "$1" ]]; then
			printf '%s\n' "$arg"
			return 0
		fi
		previous=$arg
	done <"$TEST_ROOT/fzf-argv"
	return 1
}

@test "the list's header in English: the paths, two lines of key hints, and the note when the file is not sourced" {
	fake_fzf
	run "$TPP_ROOT/scripts/panel.sh"
	[ "$status" -eq 0 ]
	local header
	header=$(fzf_option --header)
	[ "$header" = "plugins ~/.config/tmux/plugins/   file ~/.config/tmux/plugins.conf
enter/u update · U all · a add · d remove · i install · c clean · r refresh · tab mark · q quit
j/k move · J/K scroll preview · ctrl-d/ctrl-u scroll preview by half a page" ]
	printf "run '%s/tpm/tpm'\n" "$PLUGIN_DIR" >"$TMUX_CONF"
	run "$TPP_ROOT/scripts/panel.sh"
	[ "$status" -eq 0 ]
	header=$(fzf_option --header)
	[ "$header" = "plugins ~/.config/tmux/plugins/   file ~/.config/tmux/plugins.conf
enter/u update · U all · a add · d remove · i install · c clean · r refresh · tab mark · q quit
j/k move · J/K scroll preview · ctrl-d/ctrl-u scroll preview by half a page
${YELLOW}~/.config/tmux/plugins.conf is not sourced from ~/.config/tmux/tmux.conf${RESET}" ]
}

@test "the list speaks German under a German locale: header, column header, statuses" {
	fake_fzf
	make_remote alpha
	clone_plugin alpha
	declare_plugin "$(remote_url alpha)"
	declare_plugin someone/missing
	run german "$TPP_ROOT/scripts/panel.sh"
	[ "$status" -eq 0 ]
	local header
	header=$(fzf_option --header)
	[ "$header" = "Plugins ~/.config/tmux/plugins/   Datei ~/.config/tmux/plugins.conf
enter/u aktualisieren · U alle · a hinzufügen · d entfernen
i installieren · c aufräumen · r neu laden · tab markieren · q beenden
j/k bewegen · J/K Vorschau scrollen · ctrl-d/ctrl-u Vorschau um eine halbe Seite scrollen" ]
	run cat "$TEST_ROOT/fzf-input"
	[[ ${lines[0]} == $'\t'"${DIM}Plugin "*"Status "*"Installierter Commit${RESET}" ]]
	[[ ${lines[1]} == alpha$'\t'*"wird geprüft…"* ]]
	[[ ${lines[2]} == missing$'\t'*"nicht installiert"* ]]
}

@test "no German key hint line is wider than the English first one" {
	fake_fzf
	run "$TPP_ROOT/scripts/panel.sh"
	[ "$status" -eq 0 ]
	local -a english_lines german_lines
	local line
	while IFS= read -r line; do english_lines+=("$line"); done < <(fzf_option --header)
	run german "$TPP_ROOT/scripts/panel.sh"
	[ "$status" -eq 0 ]
	while IFS= read -r line; do german_lines+=("$line"); done < <(fzf_option --header)
	# The first header line holds the paths; the key hints follow.
	[ "${#english_lines[1]}" -eq 95 ]
	[ "${#german_lines[@]}" -eq 4 ]
	for line in "${german_lines[@]:1}"; do
		[ "${#line}" -le "${#english_lines[1]}" ] || {
			echo "${#line} characters: $line"
			return 1
		}
	done
}

@test "the German status column is as wide as its longest status word" {
	declare_plugin someone/missing
	mkdir -p "$PLUGIN_DIR/orphan"
	make_remote pinned
	push_commit pinned dev
	clone_plugin pinned dev
	declare_plugin "someone/pinned#dev"
	run german "$TPP_ROOT/scripts/panel.sh" rows
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 4 ]
	# The status column starts two columns after the longest name,
	# someone/missing; "nicht installiert" and "nicht eingetragen", the
	# longest German status words, have 17 characters, and two spaces follow.
	# The age of the pinned plugin is git's, in German or English, so only
	# the part before it is compared.
	local i visible expected
	local -a names=(Plugin someone/missing orphan someone/pinned)
	local -a statuses=(Status "nicht installiert" "nicht eingetragen" gepinnt)
	for i in 0 1 2 3; do
		visible=$(printf '%s' "${lines[i]#*$'\t'}" | sed $'s/\033\\[[0-9;]*m//g')
		printf -v expected '%-17s%-19s' "${names[i]}" "${statuses[i]}"
		[ "${visible:0:36}" = "$expected" ]
		[[ ${visible:36:1} != ' ' ]]
	done
}

@test "the preview speaks German under a German locale" {
	declare_plugin someone/missing
	run german "$TPP_ROOT/scripts/panel.sh" preview missing
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "${DIM}someone/${RESET}${BOLD}missing${RESET}" ]
	# "eingetragen", the longest label, has 11 characters.
	[ "${lines[1]}" = "eingetragen  someone/missing" ]
	[ "${lines[2]}" = "in           $PANEL_FILE" ]
	[ "${lines[3]}" = "Repo         https://github.com/someone/missing" ]
	[ "${lines[4]}" = "nicht installiert" ]
	mkdir -p "$PLUGIN_DIR/orphan"
	run german "$TPP_ROOT/scripts/panel.sh" preview orphan
	[ "$status" -eq 0 ]
	[ "${lines[1]}" = "eingetragen  nirgends (nicht eingetragen)" ]
	[ "${lines[2]}" = "Pfad         $PLUGIN_DIR/orphan" ]
}

@test "a German confirmation takes j for yes" {
	mkdir -p "$PLUGIN_DIR/orphan"
	local panel
	panel=$(printf '%q' "$TPP_ROOT/scripts/panel.sh")
	# j and enter answer the question, x is the key for "Press any key".
	run bash -c 'printf "j\rx" | SHELL=/bin/bash timeout 30 script -qec "$1 $2 clean" /dev/null' _ "$GERMAN_ENV" "$panel"
	[ "$status" -eq 0 ]
	[[ $output == *"Verzeichnisse ohne Eintrag:"*"Von TPM entfernen lassen? [j/N]"*'"orphan" clean success'* ]]
	[[ $output == *"Beliebige Taste drücken, um zur Liste zurückzukehren."* ]]
	[ ! -e "$PLUGIN_DIR/orphan" ]
}

@test "a German confirmation takes JA in capitals" {
	mkdir -p "$PLUGIN_DIR/orphan"
	local panel
	panel=$(printf '%q' "$TPP_ROOT/scripts/panel.sh")
	run bash -c 'printf "JA\rx" | SHELL=/bin/bash timeout 30 script -qec "$1 $2 clean" /dev/null' _ "$GERMAN_ENV" "$panel"
	[ "$status" -eq 0 ]
	[[ $output == *"Von TPM entfernen lassen? [j/N]"*'"orphan" clean success'* ]]
	[ ! -e "$PLUGIN_DIR/orphan" ]
}

@test "the missing-commands error is singular for one command, plural for two" {
	run bash -c 'source "$1/scripts/lib.sh" && tpp_msg_missing_commands git && echo && tpp_msg_missing_commands git fzf' _ "$TPP_ROOT"
	[ "$status" -eq 0 ]
	[ "$output" = $'missing required command: git\nmissing required commands: git fzf' ]
	unset LC_ALL
	LANG=de_DE.UTF-8 run bash -c 'source "$1/scripts/lib.sh" && tpp_msg_missing_commands git && echo && tpp_msg_missing_commands git fzf' _ "$TPP_ROOT"
	[ "$status" -eq 0 ]
	[ "$output" = $'benötigter Befehl fehlt: git\nbenötigte Befehle fehlen: git fzf' ]
}

# age_under <VAR>=<value>...: the age column tpp_collect gives for the only
# plugin, with LC_ALL unset and these variables set.
age_under() {
	(
		unset LC_ALL
		declare -x "$@"
		bash -c 'source "$1/scripts/lib.sh"; tpp_init; tpp_collect' _ "$TPP_ROOT"
	) | cut -f 3
}

@test "the age column is English under an English panel where git would say it in German" {
	make_remote alpha
	clone_plugin alpha
	declare_plugin "$(remote_url alpha)"
	local english german
	english=$(LC_ALL=C git -C "$PLUGIN_DIR/alpha" log -1 --format=%cr)
	# An English locale with LANGUAGE=de: the panel is English, git's
	# messages are German.
	german=$(env -u LC_ALL LANG=en_US.UTF-8 LANGUAGE=de git -C "$PLUGIN_DIR/alpha" log -1 --format=%cr)
	if [[ $german == "$english" ]]; then
		skip "git gives no German age here (needs git's German catalogue and the en_US.UTF-8 locale)"
	fi
	[ "$(age_under LANG=en_US.UTF-8 LANGUAGE=de)" = "$english" ]
	[ "$(lang_for LANG=en_US.UTF-8 LANGUAGE=de)" = en ]
}

@test "the age column is German under a German panel where git would say it in English" {
	make_remote alpha
	clone_plugin alpha
	declare_plugin "$(remote_url alpha)"
	local english german
	english=$(LC_ALL=C git -C "$PLUGIN_DIR/alpha" log -1 --format=%cr)
	german=$(env -u LC_ALL LANG=de_DE.UTF-8 git -C "$PLUGIN_DIR/alpha" log -1 --format=%cr)
	if [[ $german == "$english" ]]; then
		skip "git gives no German age here (needs git's German catalogue and the de_DE.UTF-8 locale)"
	fi
	# A German locale with LANGUAGE=en: the panel is German, git's messages
	# are English.
	[ "$(age_under LANG=de_DE.UTF-8 LANGUAGE=en)" = "$german" ]
	[ "$(lang_for LANG=de_DE.UTF-8 LANGUAGE=en)" = de ]
}
