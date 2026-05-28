# FFXI-FFXIVHotbar

GSUI-styled editor for [aregowe/XIVHotbar2](https://github.com/aregowe/XIVHotbar2)
keybind files. Click a slot, pick a command/action/target from a dropdown,
hit Save. Writes back to your per-job `.lua` file with an automatic `.bak`
backup, then fires `//xivhotbar reload` so the new binding shows up
immediately on the in-game hotbar.

Built so you don't have to alt-tab out to a text editor every time you
want to add or swap a single hotbar slot.

## Requires

- Windower 4
- [XIVHotbar2](https://github.com/aregowe/XIVHotbar2) installed and
  working with a per-character data folder, e.g.
  `Windower/addons/XIVHotbar2/data/<Character>/<job>.lua`

## Install

```
cd path\to\Windower\addons
git clone https://github.com/mullerdane85-hash/FFXI-FFXIVHotbar.git
```

Then in-game:

```
//lua load FFXI-FFXIVHotbar
```

To autoload, add `lua load FFXI-FFXIVHotbar` to `scripts/init.txt`.

## Usage

Press `H` (chat-aware — passes through to chat while typing) or run
`//xh` to toggle the window.

The window shows your **three hotbars × twelve slots** for the current
job. Each slot displays its action label and command type tag. Empty
slots show a `—`.

1. **Click any slot** — opens the edit panel at the bottom showing the
   slot's current cmd / action / target / label.
2. **Click `Cmd ▾`, `Action ▾`, or `Target ▾`** — opens a dropdown
   picker. The Action picker is populated from your actually-known
   spells, your job-level-eligible abilities, weaponskills, and usable
   items currently in your bags. Picking an action auto-fills a
   sensible default command type and target.
3. **Click `Save`** — writes the change back to the `.lua` file with
   a `.bak` saved under `FFXI-FFXIVHotbar/data/backups/<filename>.<timestamp>.bak`,
   then auto-fires `//xivhotbar reload`.
4. **Clear** wipes the slot (writes a `--{...}` commented-out
   placeholder so XIVHotbar2's slot ordering stays intact).
5. **Cancel** discards your edit and closes the panel.

Drag the window by its title bar. Position persists across reloads.

### Macros

For slots whose **Cmd** is `macro`, the Action picker lists your own
reusable macros instead of game actions. These live in a plain-text file
you edit in any text editor:

```
FFXI-FFXIVHotbar/data/macros.txt
```

One macro per line, `Name = command body`. Lines starting with `#` or
`--` are comments. Write normal game commands (keep the leading slash).
For multi-step macros, separate commands with `;` and use `wait N` for a
delay:

```
Sneak = /ma "Sneak" <me>
Pull  = /p Pulling <t> ; /ws "Combo" <t>
Buffs = /ma "Protect" <me> ; wait 5 ; /ma "Shell" <me>
```

Run `//xh macros` to see the file path and everything currently defined.
After editing the file, pick `macro` as the Cmd, open the Action picker,
and choose your macro by name — its name becomes the slot label.

> **Why the slot shows `input /ma ...`:** XIVHotbar2 runs a `macro` slot as
> `//<action>`, so a bare `/ma "Sneak" <me>` would become `///ma ...` and
> fail. The editor wraps each game command as `input /...` so it executes
> correctly (`//input /ma "Sneak" <me>`). Steps without a leading slash are
> left as-is and run as Windower commands (e.g. `gs c ...`).

## Commands

| Command | What |
|---|---|
| `//xh` (or `//ffxihotbar`) | Toggle the window (same as H key) |
| `//xh show` / `//xh hide` | Explicit show/hide |
| `//xh reload` | Re-read the keybind file from disk |
| `//xh where` | Show the file paths the locator is trying |
| `//xh macros` | Show the macro library and its file path |
| `//xh help` | Command list |

## Visual style

Matches the GSUI / FFXIJSE addons — 3px blue border, dark title bar,
hotbar grid with `Consolas 10pt` text. Active slots have a filled blue
background; empty slots are slate; the currently-selected slot gets a
green tint.

## What it doesn't do (yet)

- **No multi-job tabs.** Edits the current main-job file only. Switching
  job in-game re-reads the new file automatically (on the `job change`
  event).
- **No spell icons in slots.** Just text. Adding the icon pipeline (same
  one GSUI uses) would be a follow-up.
- **No drag-to-rearrange.** Click each slot you want to change.
- **No filter search in the Action dropdown.** It lists every known
  action sorted alphabetically. Keyboard search will be added later.
- **No undo button.** Use the `.bak` files in `data/backups/` to restore
  manually if needed (just copy them over the live file).

## Credits

- **aregowe** for the original XIVHotbar2 addon. This editor only
  modifies the keybind files; the actual hotbar rendering and command
  execution is all XIVHotbar2.
- The locator / writer / dropdown code patterns are reused from the
  author's other Windower addons (FFXIJSE, GSUI2).
