# tmux-plugin-panel

A popup for managing [TPM](https://github.com/tmux-plugins/tpm) plugins. It
lists every plugin with its update status, shows the commits an update would
bring, and lets you update, add, remove, install and clean plugins from one
place.

It does not replace TPM. Installing, updating and cleaning run through TPM's
own scripts; the panel adds the overview, and it writes new declarations to a
file of its own instead of editing your `tmux.conf`.

## Requirements

- tmux 3.2 or newer (for `display-popup`)
- TPM
- bash, git
- [fzf](https://github.com/junegunn/fzf) 0.36 or newer
- optional: `timeout` (GNU coreutils; `gtimeout` on macOS) to bound the
  fetch of each plugin when the panel opens

## Installation

Add the plugin to your tmux config and source the panel's file **before** the
line that runs TPM, so TPM sees the plugins the panel adds:

```tmux
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'danielcopper/tmux-plugin-panel'

source-file -q ~/.config/tmux/plugins.conf

run '~/.config/tmux/plugins/tpm/tpm'
```

Then press `prefix + I` to let TPM install it.

The panel's file does not have to exist yet; the panel creates it when you add
the first plugin. `-q` keeps tmux quiet while it is missing. If the file is not
sourced, the panel says so in its header.

## Usage

Press `prefix + P` to open the panel.

When it opens, the panel fetches every installed plugin in parallel and shows
`checking…` until the fetches are done; then the list shows the real status.

| Key            | Action                                                     |
| -------------- | ---------------------------------------------------------- |
| `enter` or `u` | update the selected plugins                                |
| `tab`          | mark a plugin, to act on several at once                   |
| `U`            | update all plugins                                         |
| `a`            | add a plugin                                               |
| `d`            | remove the selected plugins                                |
| `i`            | install missing plugins                                    |
| `c`            | clean: remove plugin directories that have no declaration  |
| `r`            | fetch again and refresh the list                           |
| `q` or `esc`   | close the panel                                            |

After every change the panel reloads your tmux config and refreshes the list.
The output of TPM is shown until you press a key.

The preview under the list shows where a plugin is declared, its directory and
repository, and for an installed plugin the commits an update would bring.

### Status

| Status           | Meaning                                                     |
| ---------------- | ----------------------------------------------------------- |
| `✓`              | up to date with its upstream branch                         |
| `↓N`             | N commits behind upstream: an update brings them in         |
| `↑N`             | N local commits that are not upstream                       |
| `not installed`  | declared, but there is no directory yet (`i` installs it)   |
| `not declared`   | a directory without a declaration (`c` cleans it)           |
| `pinned`         | detached HEAD, or declared with a `#branch` suffix          |
| `no upstream`    | the checked-out branch does not track a remote branch       |
| `not a git repo` | the plugin directory is not a git checkout                  |

The last column is the age of the plugin's current commit.

### Adding a plugin

`a` asks for the plugin. Accepted forms:

- `owner/repo`
- a GitHub URL: `https://github.com/owner/repo`, `git@github.com:owner/repo.git`, …
- any other git URL, kept as it is: `https://gitlab.com/owner/repo.git`
- any of the above with a branch: `owner/repo#branch`

GitHub URLs are stored in TPM's short form `owner/repo`. A plugin whose name
is already declared anywhere is refused. The panel appends
`set -g @plugin '<plugin>'` to its file and runs TPM's install.

### Removing a plugin

`d` deletes the plugin's line from the panel's file and deletes the plugin's
directory. It only removes lines from its own file: a plugin that is declared
in `tmux.conf` or another file is left alone, and the panel tells you which
file to edit. TPM itself is never removed.

## Options

| Option               | Default                        | Meaning                                  |
| -------------------- | ------------------------------ | ---------------------------------------- |
| `@plugin-panel-key`  | `P`                            | key (in the prefix table) opening the panel |
| `@plugin-panel-file` | `~/.config/tmux/plugins.conf`  | the file the panel writes declarations to   |

```tmux
set -g @plugin-panel-key 'M-p'
set -g @plugin-panel-file '~/.config/tmux/my-plugins.conf'
```

The panel refuses to write when `@plugin-panel-file` points at your
`tmux.conf`.

## How it works with TPM

- **Plugin directory**: the same as TPM's: `TMUX_PLUGIN_MANAGER_PATH` from the
  tmux environment if set, otherwise `~/.config/tmux/plugins/` when your config
  is `~/.config/tmux/tmux.conf` (respecting `XDG_CONFIG_HOME`), otherwise
  `~/.tmux/plugins/`. The header shows the path in use.
- **Declarations**: read with TPM's own helpers and rules: `set -g @plugin`
  lines in `/etc/tmux.conf`, in your `tmux.conf` and in the files it sources
  (one level deep).
- **Install, update, clean**: `bin/install_plugins`, `bin/update_plugins` and
  `bin/clean_plugins` from TPM.
- **Status**: the panel's own; it runs `git fetch` and compares with the
  upstream branch using git plumbing commands.

## Limitations

- Letters are bound to actions, so typing does not filter the list.
- Removing a plugin does not undo what it already set up in the running tmux
  server (key bindings, options); restart tmux for a clean state.
- `c` runs TPM's clean, and TPM decides what is removed: it keeps a directory
  whose name appears anywhere in the list of declared plugins.
- TPM updates a plugin with `git pull`, which fails for a detached HEAD.
- Without `timeout` or `gtimeout`, a remote that does not answer delays the
  list until git gives up.
- Declarations are found the way TPM finds them: nested `source-file` lines
  and paths with variables other than `~` and `$HOME` are not followed.

## Development

The tests use [bats-core](https://github.com/bats-core/bats-core) and need a
TPM checkout to copy into their temporary setups:

```sh
TPM_SRC=~/.config/tmux/plugins/tpm bats test/
shellcheck -x tmux-plugin-panel.tmux scripts/*.sh test/*.bash test/*.bats
```

Every test runs its own tmux server on a private socket with a temporary
`HOME`, and uses local git repositories as plugin remotes. Your tmux server,
your plugins and the network are not touched.

## License

[MIT](LICENSE)
