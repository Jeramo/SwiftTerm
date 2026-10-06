Raw 80x24 PTY output captured from tmux 3.7b and Zellij 0.45.1 on 2026-09-09.

The fixture program printed a plain URL, a URL wrapping across rows, and an OSC 8 label, with xterm mouse modes 1000 and 1006 enabled. Default fixtures use default hyperlink settings; hyperlinks fixtures enable OSC 8 output for the client.

The label target emitted by the program was https://example.com/docs;edition=2?foo=1;bar=2#section. Zellij 0.45.1 truncates this target at its first semicolon before forwarding it to the terminal. The fixture preserves that upstream behavior. Plain URLs retain semicolons.
