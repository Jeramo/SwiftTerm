Raw 80x24 PTY output captured from tmux 3.7b and Zellij 0.45.1 on 2026-09-09.

The fixture program printed a plain URL, a URL wrapping across rows, and an OSC 8 label, with xterm mouse modes 1000 and 1006 enabled. Default fixtures use default hyperlink settings; hyperlinks fixtures enable OSC 8 output for the client.

The label target emitted by the program was https://example.com/docs;edition=2?foo=1;bar=2#section. Zellij 0.45.1 truncates this target at its first semicolon before forwarding it to the terminal. The fixture preserves that upstream behavior. Plain URLs retain semicolons.

`widths/` holds the recordings behind WidthModeFixtureTests, made on 2026-10-27, 12x6 or 20x6 (shell: 30x6). Each `<name>.rec` is what the program sent its passive client terminal and `<name>.screen` the screen it meant: `SIZE`, `CURSOR`, `T<row>` text and `C<row>` cell start columns followed by the row's extent.

- `tmux35/`: tmux 3.5a on Debian 13 (glibc widths). Text is `capture-pane -p`, the cursor `#{cursor_x} #{cursor_y}`, and the cell starts where copy mode's `cursor-right` stops on each row (it skips padding).
- `tmux37/`: the same streams through tmux 3.7b from Homebrew on macOS (utf8proc widths), read the same way.
- `zellij/`: zellij 0.43.1 on Debian 13. The screen is the recording drawn by @xterm/headless 6 with the Unicode 11 widths (per code point, as zellij measures); its rows agree with zellij's `dump-screen`, which joins wrapped rows.
- `mosh/`: mosh 1.4.0 on Debian 13, mosh-client drawing mosh-server's screen, read the same way. It equals the program's output drawn from row 1: mosh-server's screen starts with the cursor on the second row.
- `mosh-darwin/`: the same streams plus one of Bengali, Tamil and Kannada vowel signs through mosh 1.4.0 with mosh-server on macOS 27, whose wcwidth gives spacing marks no column. The screen is the recording drawn by the third critic's reference emulator (`refemu.py`) with macOS's own wcwidth table; it equals that emulator drawing the program's output one row down, as mosh-server held it.
- `shell-wcwidth/`: the third critic's recordings of bash and zsh editing lines holding 👍🏽, a ZWJ family, flags, ❤️ and Hindi. The screen is the recording drawn by @xterm/headless 6 with the Unicode 11 widths, and the critic's emulator with glibc's table draws the same.
- `shell/`: bash, zsh and fish editing a line over ssh without a multiplexer, from the W4 critic's set; the screen is the shell's output drawn by @xterm/headless 6 with the Unicode 11 widths, the widths the shell measured with.

The `s*` streams came from the W4 critic's adversarial set, the `m*`, `n*`, `e*` and `t*` streams cover emoji modifiers, variation selectors, ZWJ sequences, Indic and Hangul text and editing at the margins. A few rows hold something tmux keeps in its grid but never sent its client; WidthModeFixtureTests lists them with what was sent.
