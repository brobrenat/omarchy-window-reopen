# Window Reopen

Undo for closed windows in [Omarchy](https://omarchy.org) (Hyprland). Close a window by mistake, press a key, and the app comes back.

- `SUPER + W` "closes" the window: it disappears but keeps running, hidden.
- `SUPER + ALT + W` brings back the last closed window exactly as you left it: same terminal folder, scrollback, running programs, unsaved text. Press again to go further back.

Hidden windows are really closed after 10 minutes, or when more than 5 are waiting (oldest first). Reopening one of those relaunches the app fresh with the same command, arguments and folder; its contents are gone by then.

Terminals (foot, Alacritty, kitty, Ghostty) come back as close as possible even after the real close:

- **tmux**: the session keeps running, so the new terminal reattaches it: same windows, folder and screen.
- **herdr**: same, via herdr's persistent session.
- **plain shell**: a new shell opens in the folder you had `cd`'d into; scrollback and running commands are gone.

Web apps (WhatsApp, Discord and other `omarchy-launch-webapp` apps) share one Chromium process, so when relaunched they start from their desktop entry instead of the process command line.

Note: a hidden window is still running, so a playing video or a running command keeps going until it is really closed.

Change the timeout with `WINDOW_REOPEN_TTL` (seconds) in the keybinding, e.g. `WINDOW_REOPEN_TTL=1800 .../window-reopen close`.

## Install

```bash
omarchy plugin add https://github.com/brobrenat/omarchy-window-reopen.git --enable
```

Then add this to `~/.config/hypr/bindings.lua`:

```lua
-- window-reopen: begin
hl.unbind("SUPER + W")
o.bind("SUPER + W", "Close window", "~/.config/omarchy/plugins/io.github.brobrenat.window-reopen/bin/window-reopen close")
o.bind("SUPER + ALT + W", "Reopen closed window", "~/.config/omarchy/plugins/io.github.brobrenat.window-reopen/bin/window-reopen reopen")
-- window-reopen: end
```

## Uninstall

1. Bring back any hidden windows first: press `SUPER + ALT + W` until it says "Nothing to reopen". Windows still hidden after removal stay hidden until their timer closes them.
2. Delete the block between `-- window-reopen: begin` and `-- window-reopen: end` in `~/.config/hypr/bindings.lua`. `SUPER + W` returns to Omarchy's normal close.
3. Remove the plugin. Its history lives in `$XDG_RUNTIME_DIR/window-reopen` and is wiped at logout.

```bash
omarchy plugin remove io.github.brobrenat.window-reopen
```

## Commands

```bash
window-reopen close    # hide the focused window (really closed after the timeout)
window-reopen reopen   # bring back the most recently closed window
window-reopen list     # show remembered windows, newest last
```

History lives in `$XDG_RUNTIME_DIR/window-reopen/history` (usually `/run/user/<uid>`): readable only by you and wiped at logout. It contains the full command lines of closed windows, so it is never written to permanent storage.

## Testing

`tests/live-test.sh` runs on a live Hyprland session. It opens and closes only its own marked windows, so it is safe to run while you work.

## Requirements

Omarchy 4 (Hyprland with Lua config). Uses `hyprctl`, `jq`, `xdg-terminal-exec`, `uwsm-app`, `notify-send` and `setsid`, which all ship with Omarchy. `tmux` and `herdr` are optional: they are only used when a closed terminal was running them. No root access, extra packages or network access.

## License

MIT
