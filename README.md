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
- [fzf](https://github.com/junegunn/fzf) 0.36 or newer; 0.73 or newer shows each
  plugin's check as it happens (see Usage)
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

When it opens, and again after `r`, the panel fetches every installed plugin
in parallel. With fzf 0.73 or newer, a plugin's status shows `checking ⠋`, with
the spinner turning, while its fetch runs, and its real status as soon as its
own fetch has ended. With older fzf the list shows `checking…` until all the
fetches are done, and fzf's spinner turns in the line above the header
meanwhile.
Each fetch is cut off after 10 seconds when `timeout` or `gtimeout` is
available. An action started while the fetches run (with fzf 0.73 or newer)
stops them first; the plugins whose fetch it stopped show the status of their
last fetch, and `r` fetches again.

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

While TPM installs, updates or cleans, a spinner shows; `ctrl-c` cancels
TPM. A prompt on the terminal, such as ssh asking for a key's passphrase, can
be answered; the spinner pauses while it waits. A prompt that shows what you
type, such as ssh asking to confirm an unknown host key, can be answered too;
on Linux the spinner may draw over the start of its line.
After every change the panel reloads your tmux config and refreshes the list.
An update ends with one line per plugin: its old and new commit,
`already up to date`, or `update failed`. Updating all plugins lists the
declared plugins installed as git checkouts. TPM's output follows when an
update failed or TPM reported an error, and replaces the list when there was
no plugin to update. Install, add and clean show TPM's output. Either stays
until you press a key.

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

## Language

The panel speaks English and German. It takes the language from the first of
`LC_ALL`, `LC_MESSAGES` and `LANG` that is set and not empty: a locale whose
language part is `de` (`de_DE.UTF-8`, `de_AT.UTF-8`, …) is German; any other
language, `C` and `POSIX` are English. `LANGUAGE` is not read.

The age in the last column is git's own wording, asked for in the panel's
language; git words it in German when it has its German translation and the
locale is installed. TPM's output, and the git messages in it, are shown as
TPM prints them. The key names in the header (`enter`, `ctrl-d`, …) stay as
they are.

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
- **Credential helpers**: TPM clones a plugin declared as owner/repo from
  `https://git::@github.com/owner/repo`, with empty credentials in the URL,
  which git would otherwise hand to your credential helper to store after
  every successful clone, fetch or pull. Every git command the panel starts,
  its own and those of TPM's scripts, runs without credential helpers for
  that URL form only (an empty `credential.https://git@github.com.helper`,
  added to the environment through `GIT_CONFIG_COUNT`, which needs git
  2.31). Other users and hosts keep your helpers.

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
shellcheck -x tmux-plugin-panel.tmux scripts/*.sh scripts/lang/*.sh test/*.bash test/*.bats
```

Every test runs its own tmux server on a private socket with a temporary
`HOME`, and uses local git repositories as plugin remotes. Your tmux server,
your plugins and the network are not touched. The tests run under the
`C.UTF-8` locale, so the panel speaks English in them unless a test sets
another language.

To add a language, copy `scripts/lang/en.sh` to `scripts/lang/<code>.sh`,
where `<code>` is the language part of the locale (`fr` for `fr_FR.UTF-8`),
and translate the messages; a test checks that the new file defines exactly
the messages of `en.sh`.

Two tests of the age column need the `de_DE.UTF-8` and `en_US.UTF-8` locales
and git's German translation, and skip without them.

## License

[MIT](LICENSE)
