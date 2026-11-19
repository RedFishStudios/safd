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
- Client entry scripts under `src/Client` (StarterPlayerScripts) must use `--@localscript`. A `--@script:client`
  Script there runs twice (once in StarterPlayerScripts, once in the PlayerScripts copy).
- Docs: https://iron-stag-games.github.io/lync/

## Workflow

1. Run `lync serve` in this folder (port 34874). The **Lync** plugin in Studio connects to `localhost:34874`.
   Port 34873, the default, is used by a different project's Lync server (`Desktop\starducks`).
   An empty port box in the plugin means 34873, which connects Studio to the WRONG project.
   Lync adds and updates instances but does not remove stale ones. After a bad sync, delete any extras
   in the three folders (for example via MCP `execute_luau`) before saving the place.
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
- `ReplicatedStorage.Assets` (not Lync-managed, saved in the .rbxl): `Animals/<Id>` (48 animals, 8 per biome, all from the user's
  animal bundle zip: never use the reference place's AnimalPack. The 18 added later share a skeleton with one of the
  first 30 and reuse its uploaded clips: Config.AnimationIds) and `Treadmills/BasicTreadmill`. Source files: `../assets/*.rbxm`.
  Also `TreadmillTiers/<Model>` (the 16 tier treadmills) and `RefUI` (PlotUpgrade / TreadmillUpgrade sign models and
  the AreaTitle banner frame), imported from the reference place `[NEW] Feed and Rob Animals.rbxl`.
- Progression (speed points -> walk speed curve, treadmill/base tiers and prices) is copied from that reference place
  into `src/Shared/Progression.luau`.
- At runtime the server moves `Workspace.Bases` templates/BaseLayout to ServerStorage and builds
  `Workspace.PlayerBases.Base1..7`, plus `WildAnimals`, `BaseAnimals` and `ReplicatedStorage.MapInfo`/`Remotes`.
  Each base is a wooden fence pen built in code like the reference's (BaseService `setBaseModel`): 5 in the row
  facing the white line, 2 beside the row's ends facing inward. The BaseLvl models are no longer used.
- In a Studio playtest, Ctrl + W/A/S/D triggers Studio shortcuts before the game sees them: Ctrl+A select all
  (freezes Studio for seconds on this map; Studio's log shows `SelectAllComponentLog`), Ctrl+S save, Ctrl+D
  duplicate (clones a selected character). No game code can block them; the published game is unaffected. Slide
  also works on C, and in Studio a toast says so when Ctrl is pressed.
- `Workspace.SAFD_Boundaries` (saved in the place): invisible walls around the whole play area (behind the bases,
  both sides, the far end) and `SafetyFloor` pieces just under the biome floors (top 0.95 vs the floor's 1.0),
  which fill holes where decorations with collisions off stood in for floor (Candyland). Parts max out at 2048
  studs, so long pieces are split. `Workspace.SAFD_EdgeFloors` are the older 140-wide side floors.
- Map scenery is chunk unions (2026-11-19): every plain brick in `Workspace.Levels.*` and `Non_functional_spawn_assets`
  was merged per 64-stud cell into one solid union (PreciseConvexDecomposition) and one walk-through union, under each
  level's `Chunks.All` model (780 unions; one union per prop was 4,100 and made the map load slowly: every union is a
  mesh download). Walk-through: the artists' small leaf models (fit in 6.5 studs, or at most 4 wide and 10 tall, or
  flat), thin/tiny bricks and all pathway decor. The original bricks are in
  `../Revanoire - stud mining commission - resized.rbxl` and Roblox version history. Don't rely on Studio undo for
  `UnionAsync` work: it yields mid-recording and undo only half-reverts it. `Workspace.StreamingMinRadius` is 160.
- Unused leftovers from the original map (`Ores`, `Treadmills`) were moved to `ServerStorage.SAFD_Unused`.
- DataStore needs the place published (and Studio API access on); until then data is not saved.
