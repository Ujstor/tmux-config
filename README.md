# tmux-config

The tmux configuration used across the fleet. Portable by design: the same
`.tmux.conf` has to work on WSL, on a Linux desktop (X11 or Wayland) and on a
headless server reached over SSH, so nothing in it assumes a Windows host, an X
server or a graphical session at all.

```bash
curl -sSL https://raw.githubusercontent.com/Ujstor/tmux-config/master/install.sh | bash
```

It is also installed — together with the neovim and bash configs, for your user
**and** for root — by the one bootstrap command in
[Ujstor/linux-devops-tools](https://github.com/Ujstor/linux-devops-tools).

The symlink is not the whole install. `~/.tmux.conf` on its own is **inert**:
every `set -g @plugin` line in it is a no-op without `~/.tmux/plugins/tpm`, so
there is no theme, no `tmux-resurrect` and no `tmux-yank` — which is what binds
`y` in copy mode. `install.sh` installs tmux, TPM, every plugin and `~/tmux.sh`,
non-interactively — also when it is run from inside a tmux session. It backs up
anything it replaces and refuses to overwrite a symlink it did not make; a
symlink into its own checkout counts as installed. `--keep-config` leaves
`~/.tmux.conf` alone altogether, which is how linux-devops-tools runs it, since
it places that symlink itself. A re-run writes nothing: an existing TPM checkout is
pulled only with `--update`.

Prefix is <kbd>Ctrl</kbd>+<kbd>Space</kbd>.

## Copying

Copy mode is vi-mode. Everything below sends the selection to the **system**
clipboard of whatever machine you are sitting at — the backend is resolved at
yank time, not at config-parse time, so the same file works when you attach from
Windows Terminal today and over SSH to a Debian VM tomorrow:

`~/.local/bin/clip` → WSL `clip.exe` → Wayland `wl-copy` → X11 `xclip`/`xsel` →
OSC 52. The last one is what survives a plain SSH hop; tmux emits it itself.

| key | what it does |
|---|---|
| <kbd>prefix</kbd> <kbd>[</kbd> | enter copy mode |
| <kbd>v</kbd> / <kbd>C-v</kbd> | start a selection / toggle rectangle |
| <kbd>y</kbd> | yank to the system clipboard, and flash how much |
| <kbd>prefix</kbd> <kbd>P</kbd> | paste the **system** clipboard into the pane, as a bracketed paste — and say so when this host has no readable clipboard, instead of pasting tmux's last buffer |
| <kbd>prefix</kbd> <kbd>]</kbd> | paste tmux's own buffer |
| drag | select and yank, in a normal shell pane |
| <kbd>Alt</kbd>/<kbd>Ctrl</kbd> + drag | select and yank **inside a full-screen app** |
| <kbd>prefix</kbd> <kbd>m</kbd> | toggle tmux's mouse off, for your terminal's own selection |

Every yank flashes a green `YANK` message in the status line with the line count,
the byte count and which backend took it — so a yank is never silent, and a yank
that went nowhere says so.

### Selecting inside k9s, lazygit, htop

Dragging inside a full-screen app used to do nothing, and that was not a bug in
the app. tmux ships this default:

```tmux
bind -T root MouseDrag1Pane if -F '#{||:#{alternate_on},#{pane_in_mode},#{mouse_any_flag}}' \
     'send-keys -M' 'copy-mode -M'
```

k9s sets **both** `alternate_on` (it draws on the alternate screen) and
`mouse_any_flag` (its toolkit turns mouse reporting on), so the condition is true
and every drag is forwarded to k9s. tmux never enters copy mode, so there is
nothing to mark and nothing to yank.

Hold <kbd>Alt</kbd> or <kbd>Ctrl</kbd> while dragging. A modified drag is a
different key as far as tmux is concerned, so it reaches neither that default nor
the application. Both are bound because terminals disagree about which one they
keep for themselves — Windows Terminal takes <kbd>Alt</kbd>+drag for block
selection, most X11/Wayland terminals take neither. Use whichever your terminal
lets through, or <kbd>prefix</kbd> <kbd>m</kbd> and use the terminal's own
selection.

The keyboard route — <kbd>prefix</kbd> <kbd>[</kbd>, then <kbd>v</kbd> and
<kbd>y</kbd> — has always worked in these apps and still does.

## Panes and windows

| key | what it does |
|---|---|
| <kbd>prefix</kbd> <kbd>v</kbd> / <kbd>b</kbd> | split right / split down, in the current directory |
| <kbd>prefix</kbd> <kbd>c</kbd> | new window, in the current directory |
| <kbd>prefix</kbd> <kbd>x</kbd> | kill pane |
| <kbd>prefix</kbd> <kbd>h</kbd> <kbd>j</kbd> <kbd>k</kbd> <kbd>l</kbd> | move between panes |
| <kbd>C-h</kbd> <kbd>C-j</kbd> <kbd>C-k</kbd> <kbd>C-l</kbd> | move between panes **and** neovim splits (vim-tmux-navigator) |
| <kbd>prefix</kbd> <kbd>q</kbd> / <kbd>a</kbd> | main-horizontal / main-vertical layout (`~/tmux.sh`) |
| <kbd>prefix</kbd> <kbd>e</kbd> / <kbd>w</kbd> | file-tree sidebar / sidebar with focus |
| <kbd>prefix</kbd> <kbd>r</kbd> | reload this config |
| <kbd>prefix</kbd> <kbd>I</kbd> | install / update plugins |
| <kbd>prefix</kbd> <kbd>C-s</kbd> / <kbd>C-r</kbd> | save / restore sessions (tmux-resurrect) |

## Sessions and logout

tmux-continuum saves every 15 minutes and tmux-resurrect restores on
<kbd>prefix</kbd> <kbd>C-r</kbd>. Its `@continuum-boot` is deliberately **off**: it
installs a systemd user unit whose stop action is `tmux kill-server`, and without
lingering systemd stops it seconds after your last login session ends — every
session, and every job running in one, went with it. Once the option is gone,
continuum disables that unit again on its next start.

## Requirements

tmux **3.2 or newer**. The config uses `#{E:…}` format expansion and
`terminal-features`, neither of which exists before that. Ubuntu 22.04 ships
3.2a, Debian 12 ships 3.3a and Ubuntu 24.04 ships 3.4, so the distro package
clears the bar nearly everywhere; `install.sh --build-tmux` builds a pinned tmux
into `/usr/local` when it does not.
