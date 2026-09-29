# shellcheck shell=bash
# shellcheck disable=SC2034 # the messages are read by lib.sh and panel.sh
#
# The German messages. See en.sh for how a catalogue is built.

TPP_MSG_HINT_UPDATE='aktualisieren'
TPP_MSG_HINT_ALL='alle'
TPP_MSG_HINT_ADD='hinzufügen'
TPP_MSG_HINT_REMOVE='entfernen'
TPP_MSG_HINT_INSTALL='installieren'
TPP_MSG_HINT_CLEAN='aufräumen'
TPP_MSG_HINT_REFRESH='neu laden'
TPP_MSG_HINT_MARK='markieren'
TPP_MSG_HINT_QUIT='beenden'
TPP_MSG_HINT_MOVE='bewegen'
TPP_MSG_HINT_SCROLL='Vorschau scrollen'
TPP_MSG_HINT_SCROLL_HALF='Vorschau um eine halbe Seite scrollen'
TPP_MSG_HINT_LINES='4 5 3'
tpp_msg_header() { printf 'Plugins %s   Datei %s' "$1" "$2"; }
tpp_msg_not_sourced() { printf '%s wird in %s nicht eingebunden' "$1" "$2"; }

TPP_MSG_COLUMN_PLUGIN='Plugin'
TPP_MSG_COLUMN_STATUS='Status'
TPP_MSG_COLUMN_AGE='Installierter Commit'
TPP_MSG_STATUS_CHECKING='wird geprüft…'
TPP_MSG_STATUS_NOT_INSTALLED='nicht installiert'
TPP_MSG_STATUS_NOT_DECLARED='nicht eingetragen'
TPP_MSG_STATUS_PINNED='gepinnt'
TPP_MSG_STATUS_NO_UPSTREAM='kein Upstream'
TPP_MSG_STATUS_NOT_GIT='kein Git-Repo'

TPP_MSG_PREVIEW_DECLARED='eingetragen'
TPP_MSG_PREVIEW_IN='in'
TPP_MSG_PREVIEW_PATH='Pfad'
TPP_MSG_PREVIEW_REPO='Repo'
TPP_MSG_PREVIEW_NOWHERE='nirgends (nicht eingetragen)'
TPP_MSG_PREVIEW_NOT_GIT='kein Git-Repository'
TPP_MSG_PREVIEW_NO_ORIGIN='(kein origin)'
TPP_MSG_PREVIEW_NO_UPSTREAM='kein Upstream-Branch'
TPP_MSG_PREVIEW_PENDING='ausstehende Commits:'
TPP_MSG_PREVIEW_NO_PENDING='keine ausstehenden Commits'
tpp_msg_option_source() { printf 'Option %s' "$1"; }

TPP_MSG_PRESS_KEY_RETURN='Beliebige Taste drücken, um zur Liste zurückzukehren.'
TPP_MSG_PRESS_KEY_CLOSE='Beliebige Taste drücken, um zu schließen.'
TPP_MSG_CONFIRM_CHOICES='[j/N]'
TPP_MSG_CONFIRM_YES='j ja y yes'
TPP_MSG_INTERRUPTED='Abgebrochen.'
TPP_MSG_UP_TO_DATE='bereits aktuell'
TPP_MSG_UPDATE_FAILED='Aktualisierung fehlgeschlagen'
TPP_MSG_INSTALLING_MISSING='Fehlende Plugins werden installiert'
TPP_MSG_NOTHING_TO_CLEAN='Nichts aufzuräumen. Beliebige Taste drücken, um zur Liste zurückzukehren.'
TPP_MSG_CLEAN_LIST='Verzeichnisse ohne Eintrag:'
TPP_MSG_CLEAN_CONFIRM='Von TPM entfernen lassen?'
TPP_MSG_CLEANING='Wird aufgeräumt'
TPP_MSG_ADD_FORMS='owner/repo, eine GitHub-URL oder eine beliebige Git-URL, optional mit #branch'
TPP_MSG_ADD_PROMPT='Plugin: '
TPP_MSG_ADDED='Hinzugefügt:'
TPP_MSG_TPM_NOT_REMOVED='tpm wird hier nicht entfernt.'
TPP_MSG_SOME_NOT_REMOVED='Einige Plugins wurden nicht entfernt, siehe oben.'
tpp_msg_updating() {
	if (($1 == 1)); then
		printf '1 Plugin wird aktualisiert'
	else
		printf '%s Plugins werden aktualisiert' "$1"
	fi
}
tpp_msg_installing() { printf '%s wird installiert' "$1"; }
tpp_msg_add_title() { printf 'Plugin zu %s hinzufügen' "$1"; }
tpp_msg_note_not_sourced() { printf 'Hinweis: %s wird in %s nicht eingebunden, daher sieht TPM die Plugins darin nicht.' "$1" "$2"; }
tpp_msg_add_source_line() { printf "Diese Zeile vor \"run '…/tpm/tpm'\" einfügen:  source-file %s" "$1"; }
tpp_msg_remove_elsewhere() { printf '%s ist in %s eingetragen, bitte die Zeile dort entfernen.' "$1" "$2"; }
tpp_msg_remove_list() { printf 'Entfernen: %s' "$1"; }
tpp_msg_remove_confirm() { printf 'Die zugehörigen Zeilen in %s und die Verzeichnisse löschen?' "$1"; }

TPP_MSG_CANNOT_START='Start nicht möglich'
TPP_MSG_UNKNOWN_VERSION='unbekannt'
TPP_MSG_NO_PLUGIN_GIVEN='kein Plugin angegeben'
TPP_MSG_REFUSE_TPM='tpm wird nicht entfernt'
TPP_MSG_NO_PLUGIN_DIR='Plugin-Verzeichnis ist nicht gesetzt'
tpp_msg_tmux_too_old() { printf 'tmux %s oder neuer wird benötigt' "$1"; }
tpp_msg_fzf_too_old() { printf 'fzf %s oder neuer wird benötigt (gefunden: %s)' "$1" "$2"; }
tpp_msg_missing_commands() {
	if (($# == 1)); then
		printf 'benötigter Befehl fehlt: %s' "$1"
	else
		printf 'benötigte Befehle fehlen: %s' "$*"
	fi
}
tpp_msg_tpm_not_found() { printf 'TPM in %s nicht gefunden' "$1"; }
tpp_msg_reload_failed() { printf 'Neuladen von %s fehlgeschlagen' "$1"; }
tpp_msg_unknown_command() { printf 'unbekannter Befehl: %s' "$1"; }
tpp_msg_invalid_characters() { printf "ungültiges Plugin '%s': Leerzeichen, Anführungszeichen und Semikolons sind nicht erlaubt" "$1"; }
tpp_msg_invalid_branch() { printf "ungültiger Branch in '%s'" "$1"; }
tpp_msg_invalid_github_url() { printf "ungültige GitHub-URL '%s' (erwartet: github.com/owner/repo)" "$1"; }
tpp_msg_invalid_plugin() { printf "ungültiges Plugin '%s' (erwartet: owner/repo oder eine Git-URL)" "$1"; }
tpp_msg_no_repository_name() { printf "ungültiges Plugin '%s': kein Repository-Name" "$1"; }
tpp_msg_panel_file_is_config() { printf '@tmux-plugin-panel-file zeigt auf %s; das Panel bearbeitet die tmux-Konfiguration nie' "$1"; }
tpp_msg_already_declared() { printf "'%s' ist bereits als '%s' in %s eingetragen" "$1" "$2" "$3"; }
tpp_msg_invalid_name() { printf "ungültiger Plugin-Name '%s'" "$1"; }
tpp_msg_declared_elsewhere() { printf "'%s' ist in %s eingetragen, bitte die Zeile dort entfernen" "$1" "$2"; }
tpp_msg_nothing_to_remove() { printf 'nichts zu entfernen für %s' "$1"; }
tpp_msg_removed() { printf '%s entfernt' "$1"; }
