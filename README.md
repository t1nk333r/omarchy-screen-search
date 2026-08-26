# Screen Search

Understand anything on your screen. A native Omarchy (`omarchy-shell`) plugin
that adds OCR and Circle-to-Search: select a screen region, then search, copy,
translate, open a link, decode a QR, or reverse-image-search it — from a bar
magnifier, a keybind, or the CLI.

## Modes

- **Circle to Search** — freeze the screen, box something, act on the image:
  Search (with your provider), OCR, Translate, Copy, Save, QR, or *Search with…*
  another provider.
- **OCR** — extract text from a region into a result card: Copy, Search,
  Translate, and **Open URL** when a link is recognised. Arabic and mixed
  scripts are preserved (install `tesseract-data-ara`).

## Bar magnifier (󰍉)

| Click | Action |
|-------|--------|
| Left | Circle to Search |
| Middle | OCR screen region |
| Right | Menu: modes · search-clipboard · provider switcher · settings |

Switching provider from the right-click menu takes effect immediately — no
restart. The choice is stored inline on the widget's entry in
`~/.config/omarchy/shell.json`, the single source of truth every part reads.

## Keybindings (added by `install.sh`)

| Binding | Action |
|---------|--------|
| `SUPER + SHIFT + PRINT` | Circle to Search |
| `SUPER + CTRL + PRINT` | OCR (result OSD) — replaces the stock `omarchy-capture-text` bind; the stock command is still `omarchy capture text` |
| `SUPER + CTRL + ALT + PRINT` | Search the clipboard's text |

## CLI

```
screen-search                 # your default mode
screen-search circle | ocr    # summon the OSD (headless fallback if the shell is down)
screen-search search "query"  # text search with the current provider
screen-search visual FILE.png # visual search (see below)
screen-search clipboard       # search whatever text is on the clipboard
screen-search provider [id]   # print or set the default provider
screen-search providers       # list providers and their capabilities
```

## Providers

| Provider | Text | Visual |
|----------|:----:|:------:|
| Google | ✓ | ✓ (Lens) |
| Bing | ✓ | ✓ |
| Yandex | ✓ | ✓ |
| Brave | ✓ | — |
| DuckDuckGo | ✓ | — |
| TinEye | — | ✓ (reverse image) |

## Visual search & privacy

Screen Search never uploads anything on its own. For visual search it copies
the captured PNG to the clipboard (marked *sensitive*, so clipboard history
skips it) and opens the provider's upload page; you paste it there. The moment
of consent is your pressing **Search** — merely opening Circle to Search sends
nothing.

- Captures live only in `$XDG_RUNTIME_DIR/screen-search/` (private, on tmpfs),
  are deleted when the OSD closes, on cancel, and on failure, and any orphans
  are swept on the next run. Only **Save** writes a copy to your Pictures.
- OCR runs locally (tesseract). Recognised text and capture paths are never
  logged or shown in notifications. QR values go only to the clipboard,
  marked sensitive.
- A later, opt-in "temporary public upload" mode (one-tap `uploadbyurl` search)
  is specified in `~/.config/omarchy/plans/002-ephemeral-upload-visual-search.md`;
  it will show a public-host warning before every upload. Not enabled here.

## Install / uninstall

```
./install.sh              # deps, enable widget, keybindings, CLI symlink, first-run provider
./uninstall.sh            # remove integration, keep files
./uninstall.sh --purge    # also delete the plugin directory
```

Shared packages installed for the tool are never removed on uninstall.

## Tests

```
bash tests/run.sh         # fully offline; network/clipboard/browser are faked
```

## License

MIT — see [LICENSE](LICENSE).
