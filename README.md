# tmux-plugin-panel

A popup for managing [TPM](https://github.com/tmux-plugins/tpm) plugins. It
lists every plugin with its update status, shows the commits an update would
bring, and lets you update, add, remove, install and clean plugins from one
place.

It does not replace TPM. Installing, updating and cleaning run through TPM's
own scripts. The panel adds the overview, writes new declarations to a file of
its own instead of editing your `tmux.conf`, and removes single plugins itself.

## Requirements

- tmux 3.2 or newer (for `display-popup`)
- TPM
- bash, git
- [fzf](https://github.com/junegunn/fzf) 0.36 or newer
- optional: `timeout` (GNU coreutils; `gtimeout` on macOS) to bound each
  plugin's fetch

## Installation

Add the plugin and a line that sources the panel's file to your tmux config.
TPM finds the declarations in that file through the `source-file` line. Put
both above the line that runs TPM, which TPM wants at the very bottom:

```tmux
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'danielcopper/tmux-plugin-panel'

source-file -q ~/.config/tmux/plugins.conf

run '~/.config/tmux/plugins/tpm/tpm'
```

The `run` line above fits a config at `~/.config/tmux/tmux.conf`; with
`~/.tmux.conf` it is `run '~/.tmux/plugins/tpm/tpm'`. Keep your existing TPM
line either way.

Then press `prefix + I` to let TPM install it.

The panel's file does not have to exist yet; the panel creates it when you add
the first plugin. `-q` keeps tmux quiet while it is missing. If the file is not
sourced, the panel says so in its header.

## Usage

Press `prefix + P` to open the panel.

When it opens, the panel fetches every installed plugin in parallel and shows
`checking…` until the fetches are done; then the list shows the real status.
Each fetch is cut off after 10 seconds when `timeout` or `gtimeout` is
available.

| Key                 | Action                                                                                                  |
| ------------------- | ------------------------------------------------------------------------------------------------------- |
| `enter` or `u`      | update the selected plugins                                                                             |
| `tab`               | mark a plugin, to act on several at once                                                                |
| `U`                 | update all plugins                                                                                      |
| `a`                 | add a plugin                                                                                            |
| `d`                 | remove the selected plugins                                                                             |
| `i`                 | install missing plugins                                                                                 |
| `c`                 | offers to clean: lists the directories without a declaration and lets TPM remove them (see Limitations) |
| `r`                 | fetch again and refresh the list                                                                        |
| `j` / `k`           | move the selection down / up                                                                            |
| `J` / `K`           | scroll the preview down / up by a line                                                                  |
| `ctrl-d` / `ctrl-u` | scroll the preview down / up by half a page                                                             |
| `q` or `esc`        | close the panel                                                                                         |

After every change the panel reloads your tmux config and refreshes the list.
The output of TPM is shown until you press a key.

The preview under the list shows where a plugin is declared, its directory and
repository, and for an installed plugin the commits an update would bring.

### Status

| Status           | Meaning                                                                                                  |
| ---------------- | -------------------------------------------------------------------------------------------------------- |
| `✓`              | up to date with its upstream branch                                                                      |
| `↓N`             | N commits behind upstream: an update brings them in                                                      |
| `↑N`             | N local commits that are not upstream                                                                    |
| `↑N ↓M`          | both: the local branch and upstream have diverged                                                        |
| `not installed`  | declared, but there is no directory yet (`i` installs it)                                                |
| `not declared`   | a directory without a declaration (`c` offers to clean it)                                               |
| `pinned`         | not compared with upstream: declared with `#branch` or `#tag`, or a detached HEAD from a manual checkout |
| `no upstream`    | the checked-out branch does not track a remote branch                                                    |
| `not a git repo` | the plugin directory is not a git checkout                                                               |

The last column, `installed commit`, is the age of the plugin's current commit.

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

| Option                    | Default                       | Meaning                                     |
| ------------------------- | ----------------------------- | ------------------------------------------- |
| `@tmux-plugin-panel-key`  | `P`                           | key (in the prefix table) opening the panel |
| `@tmux-plugin-panel-file` | `~/.config/tmux/plugins.conf` | the file the panel writes declarations to   |

Set them above the line that runs TPM:

```tmux
set -g @tmux-plugin-panel-key 'M-p'
set -g @tmux-plugin-panel-file '~/.config/tmux/my-plugins.conf'
source-file -q ~/.config/tmux/my-plugins.conf
```

When you change the file, source that file instead of `plugins.conf`. The
panel refuses to write when `@tmux-plugin-panel-file` points at your
`tmux.conf`.

## How it works with TPM

- **Plugin directory**: the same as TPM's: `TMUX_PLUGIN_MANAGER_PATH` from the
  tmux environment if set; otherwise `$XDG_CONFIG_HOME/tmux/plugins/` (default
  `~/.config/tmux/plugins/`) when the file `$XDG_CONFIG_HOME/tmux/tmux.conf`
  exists; otherwise `~/.tmux/plugins/`. The header shows the path in use.
- **Declarations**: read with TPM's own helpers and rules: `set -g @plugin`
  lines in `/etc/tmux.conf`, in your `tmux.conf` and in the files it sources.
- **Install, update, clean**: `bin/install_plugins`, `bin/update_plugins` and
  `bin/clean_plugins` from TPM.
- **Add and remove**: the panel's own. Adding appends a line to the panel's
  file and then runs TPM's install; removing deletes the line and the
  plugin's directory.
- **Status**: the panel's own; it runs `git fetch` and compares with the
  upstream branch using git plumbing commands.

## Limitations

- The list cannot be filtered by typing; letters are keys for actions.
- Removing a plugin does not undo what it already set up in the running tmux
  server (key bindings, options); restart tmux for a clean state.
- `c` runs TPM's clean, and TPM decides what is removed: it keeps a directory
  whose name appears anywhere in the list of declared plugins.
- TPM updates a plugin with `git pull`, which fails for a detached HEAD.
- Without `timeout` or `gtimeout`, a remote that does not answer delays the
  list until git gives up.
- Declarations are found the way TPM finds them: only files that your config
  sources directly are read (one level deep, nested `source-file` lines are
  not followed), and paths with variables other than `~` and `$HOME` are not
  expanded.

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
