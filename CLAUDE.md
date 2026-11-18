# SAFD — Roblox game

Roblox game built with AI help. Code lives in this repo and is synced into Roblox Studio with **Lync**.
The map/build lives in the place file, which is **outside the repo**: `../Revanoire - stud mining commission - resized.rbxl`.

## Layout

```
src/Server  -> ServerScriptService.Server              (server code)
src/Client  -> StarterPlayer.StarterPlayerScripts.Client (client code)
src/Shared  -> ReplicatedStorage.Shared                (modules used by both)
default.project.json   Lync project (serves on port 34874)
rokit.toml             pinned toolchain (lync, selene, stylua, luau-lsp)
.mcp.json              Roblox Studio MCP server (built into Studio)
```

Only those three subfolders are Lync-managed. Everything else in the place (the Workspace map, Lighting, etc.)
is edited in Studio, or through the Studio MCP, and saved in the .rbxl. Lync never touches it.

## Lync script conventions (NOT Rojo suffixes)

Lync picks the script type from a directive on the **first line** of the file, not from the file name:

| First line            | Result                        |
|-----------------------|-------------------------------|
| _(none)_              | ModuleScript                  |
| `--@script:server`    | Script, RunContext = Server   |
| `--@script:client`    | Script, RunContext = Client   |
| `--@localscript`      | LocalScript                   |
| `--@disabled`         | marks the script disabled     |

- Use the `.luau` extension. To turn a folder into a script with children, put the code in `Init.luau` inside it.
- Docs: https://iron-stag-games.github.io/lync/

## Workflow

1. Run `lync serve` in this folder (port 34874). The **Lync** plugin in Studio connects to `localhost:34874`.
   Port 34873, the default, was already in use by another Lync server on this machine.
2. Edit files in `src/`. They sync live into Studio.
3. Use the Roblox Studio MCP (`execute_luau`, `search_game_tree`, `inspect_instance`, `start_stop_play`,
   `get_console_output`, `screen_capture`, ...) to inspect the map, playtest, and read output.
   `execute_luau` needs `datamodel_type: "Edit"` (or a Play datamodel during a playtest).
4. Don't edit Lync-managed scripts directly in Studio. The next sync overwrites them; change the files instead.
5. Save the place in Studio (or with MCP `save_place`) after any map changes, since those aren't in git.

## Checks

```bash
selene src
stylua --check src     # or: stylua src
```

Formatting: tabs, 120 columns, double quotes (see `stylua.toml`). Lint: `selene.toml` (std = roblox).

## Git / GitHub

- Remote: https://github.com/RedFishStudios/safd (`gh` is logged in as RedFishStudios). Default branch `main`.
- Place files (`*.rbxl`) are git-ignored. Commit only when asked.

## Current place contents (snapshot 2026-11-19)

The map already exists. It looks like a mining / training simulator:
- `Workspace.Ores` (ore models: iron, gold, emerald, stone/deepslate variants)
- `Workspace.Bases` (BaseLvl1..10 + BaseLayout), `Workspace.Levels` (Level1_Grassy_Meadows ... Level6_Candyland)
- `Workspace.Treadmills` (Treadmill1..10), `Workspace.Spawn_elements` (Update_board, Free_item_section,
  Weight_stand, Speed_stand, Leaderboards, Danger_line, ...)
- Only existing code: `StarterCharacterScripts.LocalScript`, which sets WalkSpeed = 150 (a test leftover).
