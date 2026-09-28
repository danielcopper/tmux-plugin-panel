#!/usr/bin/env bash
#
# TPM entry point: binds the key that opens the plugin panel.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib.sh
source "$CURRENT_DIR/scripts/lib.sh"

main() {
	local key
	if ! tpp_tmux_version_ok; then
		tmux display-message "tmux-plugin-panel: tmux $TPP_MIN_TMUX or newer is required"
		return 0
	fi
	key=$(tpp_tmux_option @tmux-plugin-panel-key P)
	tmux bind-key "$key" display-popup -E -w 80% -h 70% \
		"$(printf '%q' "$CURRENT_DIR/scripts/panel.sh")"
}

main
