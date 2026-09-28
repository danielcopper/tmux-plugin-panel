# shellcheck shell=bash
# shellcheck disable=SC2034 # the messages are read by lib.sh and panel.sh
#
# The English messages: everything the panel shows. lib.sh sources this file
# first, then the catalogue of the panel's language, which redefines what it
# translates; whatever it leaves out stays English.
#
# A catalogue defines the same names as this file: a TPP_MSG_* variable for a
# fixed text, a tpp_msg_* function for a text with values, which it prints
# without a final newline. A function takes its values as arguments and may
# place them in any order. Key names (enter, ctrl-d, …) are not part of the
# messages.

# The list's header: the key hints, as "<key> <action>".
TPP_MSG_HINT_UPDATE='update'
TPP_MSG_HINT_ALL='all'
TPP_MSG_HINT_ADD='add'
TPP_MSG_HINT_REMOVE='remove'
TPP_MSG_HINT_INSTALL='install'
TPP_MSG_HINT_CLEAN='clean'
TPP_MSG_HINT_REFRESH='refresh'
TPP_MSG_HINT_MARK='mark'
TPP_MSG_HINT_QUIT='quit'
TPP_MSG_HINT_MOVE='move'
TPP_MSG_HINT_SCROLL='scroll preview'
TPP_MSG_HINT_SCROLL_HALF='scroll preview by half a page'
# tpp_msg_header <plugin directory> <panel file>
tpp_msg_header() { printf 'plugins %s   file %s' "$1" "$2"; }
# tpp_msg_not_sourced <panel file> <tmux config>
tpp_msg_not_sourced() { printf '%s is not sourced from %s' "$1" "$2"; }

# The list's columns and statuses. The status column is as wide as the
# longest status word, plus two spaces.
TPP_MSG_COLUMN_PLUGIN='plugin'
TPP_MSG_COLUMN_STATUS='status'
TPP_MSG_COLUMN_AGE='installed commit'
TPP_MSG_STATUS_CHECKING='checking…'
TPP_MSG_STATUS_NOT_INSTALLED='not installed'
TPP_MSG_STATUS_NOT_DECLARED='not declared'
TPP_MSG_STATUS_PINNED='pinned'
TPP_MSG_STATUS_NO_UPSTREAM='no upstream'
TPP_MSG_STATUS_NOT_GIT='not a git repo'

# The preview. The labels are aligned: their column is as wide as the
# longest label, plus two spaces.
TPP_MSG_PREVIEW_DECLARED='declared'
TPP_MSG_PREVIEW_IN='in'
TPP_MSG_PREVIEW_PATH='path'
TPP_MSG_PREVIEW_REPO='repo'
TPP_MSG_PREVIEW_NOWHERE='nowhere (not declared)'
TPP_MSG_PREVIEW_NOT_GIT='not a git repository'
TPP_MSG_PREVIEW_NO_ORIGIN='(no origin)'
TPP_MSG_PREVIEW_NO_UPSTREAM='no upstream branch'
TPP_MSG_PREVIEW_PENDING='pending commits:'
TPP_MSG_PREVIEW_NO_PENDING='no pending commits'
# tpp_msg_option_source <option>: where a plugin declared in TPM's option
# (@tpm_plugins) is declared.
tpp_msg_option_source() { printf '%s option' "$1"; }

# Actions: spinner messages, prompts and results.
TPP_MSG_PRESS_KEY_RETURN='Press any key to return to the list.'
TPP_MSG_PRESS_KEY_CLOSE='Press any key to close.'
# Shown after a question; TPP_MSG_CONFIRM_YES lists the answers that mean
# yes, in lower case, separated by spaces.
TPP_MSG_CONFIRM_CHOICES='[y/N]'
TPP_MSG_CONFIRM_YES='y yes'
TPP_MSG_INTERRUPTED='Interrupted.'
TPP_MSG_UP_TO_DATE='already up to date'
TPP_MSG_UPDATE_FAILED='update failed'
TPP_MSG_INSTALLING_MISSING='Installing missing plugins'
TPP_MSG_NOTHING_TO_CLEAN='Nothing to clean. Press any key to return to the list.'
TPP_MSG_CLEAN_LIST='Directories without a declaration:'
TPP_MSG_CLEAN_CONFIRM='Let TPM remove them?'
TPP_MSG_CLEANING='Cleaning'
TPP_MSG_ADD_FORMS='owner/repo, a GitHub URL or any git URL, optionally with #branch'
TPP_MSG_ADD_PROMPT='plugin: '
TPP_MSG_ADDED='Added:'
TPP_MSG_TPM_NOT_REMOVED='tpm is not removed here.'
TPP_MSG_SOME_NOT_REMOVED='Some plugins were not removed, see above.'
# tpp_msg_updating <count>
tpp_msg_updating() {
	if (($1 == 1)); then
		printf 'Updating 1 plugin'
	else
		printf 'Updating %s plugins' "$1"
	fi
}
# tpp_msg_installing <plugin>
tpp_msg_installing() { printf 'Installing %s' "$1"; }
# tpp_msg_add_title <panel file>
tpp_msg_add_title() { printf 'Add a plugin to %s' "$1"; }
# tpp_msg_note_not_sourced <panel file> <tmux config>
tpp_msg_note_not_sourced() { printf 'Note: %s is not sourced from %s, so TPM does not see its plugins.' "$1" "$2"; }
# tpp_msg_add_source_line <panel file>
tpp_msg_add_source_line() { printf "Add this line before \"run '…/tpm/tpm'\":  source-file %s" "$1"; }
# tpp_msg_remove_elsewhere <plugin> <file>
tpp_msg_remove_elsewhere() { printf '%s is declared in %s, remove the line there.' "$1" "$2"; }
# tpp_msg_remove_list <plugins>
tpp_msg_remove_list() { printf 'Remove: %s' "$1"; }
# tpp_msg_remove_confirm <panel file>
tpp_msg_remove_confirm() { printf 'Delete their lines in %s and their directories?' "$1"; }

# Errors and the results of tpp_remove.
TPP_MSG_CANNOT_START='cannot start'
TPP_MSG_UNKNOWN_VERSION='unknown'
TPP_MSG_NO_PLUGIN_GIVEN='no plugin given'
TPP_MSG_REFUSE_TPM='refusing to remove tpm'
TPP_MSG_NO_PLUGIN_DIR='plugin directory is not set'
# tpp_msg_tmux_too_old <minimum version>
tpp_msg_tmux_too_old() { printf 'tmux %s or newer is required' "$1"; }
# tpp_msg_fzf_too_old <minimum version> <version found>
tpp_msg_fzf_too_old() { printf 'fzf %s or newer is required (found %s)' "$1" "$2"; }
# tpp_msg_missing_commands <command>...
tpp_msg_missing_commands() {
	if (($# == 1)); then
		printf 'missing required command: %s' "$1"
	else
		printf 'missing required commands: %s' "$*"
	fi
}
# tpp_msg_tpm_not_found <directory>
tpp_msg_tpm_not_found() { printf 'TPM not found in %s' "$1"; }
# tpp_msg_reload_failed <tmux config>
tpp_msg_reload_failed() { printf 'reloading %s failed' "$1"; }
# tpp_msg_unknown_command <command>
tpp_msg_unknown_command() { printf 'unknown command: %s' "$1"; }
# tpp_msg_invalid_characters <input>
tpp_msg_invalid_characters() { printf "invalid plugin '%s': spaces, quotes and semicolons are not allowed" "$1"; }
# tpp_msg_invalid_branch <input>
tpp_msg_invalid_branch() { printf "invalid branch in '%s'" "$1"; }
# tpp_msg_invalid_github_url <url>
tpp_msg_invalid_github_url() { printf "invalid GitHub URL '%s': expected github.com/owner/repo" "$1"; }
# tpp_msg_invalid_plugin <input>
tpp_msg_invalid_plugin() { printf "invalid plugin '%s': expected owner/repo or a git URL" "$1"; }
# tpp_msg_no_repository_name <input>
tpp_msg_no_repository_name() { printf "invalid plugin '%s': no repository name" "$1"; }
# tpp_msg_panel_file_is_config <tmux config>
tpp_msg_panel_file_is_config() { printf '@tmux-plugin-panel-file points at %s; the panel never edits the tmux config' "$1"; }
# tpp_msg_already_declared <plugin> <declaration> <file>
tpp_msg_already_declared() { printf "'%s' is already declared as '%s' in %s" "$1" "$2" "$3"; }
# tpp_msg_invalid_name <name>
tpp_msg_invalid_name() { printf "invalid plugin name '%s'" "$1"; }
# tpp_msg_declared_elsewhere <plugin> <file>
tpp_msg_declared_elsewhere() { printf "'%s' is declared in %s, remove the line there" "$1" "$2"; }
# tpp_msg_nothing_to_remove <plugin>
tpp_msg_nothing_to_remove() { printf 'nothing to remove for %s' "$1"; }
# tpp_msg_removed <plugin>
tpp_msg_removed() { printf 'removed %s' "$1"; }
