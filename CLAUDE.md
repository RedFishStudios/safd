# SAFD — Roblox game

Roblox game built with AI help. Code lives in this repo and is synced into Roblox Studio with **Lync**.
The map/build lives in the place file, which is **outside the repo**: `../Revanoire - stud mining commission - resized.rbxl`.

## Layout

```
src/First   -> ReplicatedFirst.First                    (the loading screen: runs before anything else)
src/Server  -> ServerScriptService.Server              (server code)
src/Client  -> StarterPlayer.StarterPlayerScripts.Client (client code)
src/Shared  -> ReplicatedStorage.Shared                (modules used by both)
default.project.json   Lync project (serves on port 34874)
rokit.toml             pinned toolchain (lync, selene, stylua, luau-lsp)
.mcp.json              Roblox Studio MCP server (built into Studio)
```

Only those four subfolders are Lync-managed (Lync reads default.project.json at startup: restart `lync serve` after
changing it). Everything else in the place (the Workspace map, Lighting, etc.)
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
   in those folders (for example via MCP `execute_luau`) before saving the place.
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
- Slide is on SHIFT (and C, gamepad B) since 2026-11-20 (it was Ctrl: in Studio Ctrl + W/A/S/D ran Studio's shortcuts).
  StarterPlayer.EnableMouseLockOption is false (saved in the place) so Shift never toggles shift lock.
- `Workspace.SAFD_Boundaries` (saved in the place): invisible walls around the whole play area (behind the bases,
  both sides, the far end) and `SafetyFloor` pieces just under the biome floors (top 0.95 vs the floor's 1.0),
  which fill holes where decorations with collisions off stood in for floor (Candyland). Parts max out at 2048
  studs, so long pieces are split. `Workspace.SAFD_EdgeFloors` are the older 140-wide side floors.
- Map scenery is plain bricks again (2026-11-20): the 780 chunk unions (2026-11-19) each had to be downloaded after
  joining, so the map popped in for minutes. Each union was replaced by its original bricks (from
  `../Revanoire - stud mining commission - resized.rbxl`), under each level's `Chunks.All.<Solid_|Decor_>x,z,kind`
  models: solid ones collide, Decor ones (walk-through) have CanCollide/CanQuery/CanTouch/CastShadow off. Same
  classification as before: walk-through = any artists' model that fits in 5.2 studs, is at most 4 wide and 10 tall, or
  at most 3.2 tall, thin (<= 1.05 across) and tiny bricks, and all pathway decor. About 110k parts in Workspace (they
  arrive with the place, so nothing pops in; ~180 MB physics + ~80 MB graphics memory per client). Bricks don't merge
  (nearly every one is a different size). Trimmed 2026-11-20: 12.6k decor bricks in standalone clusters (touching bricks)
  no bigger than 3.5 studs (crumbs, pebbles, petals) were deleted for phone memory. 45 of the artists' own unions remain. Pieces that can't be merged (see-through,
  textured, meshes) are solid only when big (>= 12 tall, or >= 6 across and >= 4 tall, or >= 7.5 tall).
- Ground must stay solid: large pieces (20+ studs across) in the levels and spawn decor are solid except the
  scenic `Plane*` backdrops (20+ tall) and the `Text` signs; invisible ones keep the original map's setting (the
  biome side walls are solid). A rebuild once turned the spawn floor (227x535) off and players fell through.
- Runtime-built parts (run course, disaster wall, hazards, intro) use `Shared/MapStyle`: Plastic + the place's
  "2022 Stud" MaterialVariant, like the map's bricks. Never leave Roblox's realistic materials on them.
- Unused leftovers from the original map (`Ores`, `Treadmills`) were moved to `ServerStorage.SAFD_Unused`.
- Loading (2026-11-20): `Workspace.StreamingEnabled` is OFF, so the whole map arrives before you play (with it on, the
  3000-stud map popped in for minutes). `First/Loading` shows a loading screen and holds the character until the map,
  its meshes/textures (PreloadAsync) and the download queue are done, then sets the client attribute `WorldReady`. The animals' KeyframeSequences live in
  `ServerStorage.AnimalAnimSaves` (they were ~97k instances in ReplicatedStorage, all sent to every client).
- Animals (2026-11-20 re-sort, all from the user's zip): Meadow Chicken Corgi Bunny Goat Cow Horse Griffin Pegasus;
  Tundra Puffin Akita Yak Wolf PolarBear Caladrius Mammoth Fenrir; Dunes Meerkat Armadillo FennecFox Jackal Cobra Caracal
  Manticore Sphinx; Hellscape Salamander Hellhound ShadowWolf Dimetrodon Cerberus Cockatrice Phoenix Dragon; Toxic
  (radioactive: SurfaceAppearance tinted green in Assets, attribute Radioactive -> glow + sparks in Shared/AnimalFactory)
  Beetle Gecko Crocodile GiantSpider Chupacabra Ankylosaurus Triceratops Hydra; Candyland Hamster BichonFrise Axolotl
  Toucan Flamingo Unicorn Simurgh Qilin. New ones reuse the clips of a rig-mate (Config.AnimationIds "like" table).
  Removed ones stay valid for saves (`Config.Retired`: no longer spawn, keep their income). Wild size = Rarity.Size
  (Epic 5x, Legendary 6.5x ...), in your base = Rarity.BaseSize (`Config.baseAnimalHeight`).
- Run home (Client/RunCourse, obby rework 2026-11-20): NO fences or set path, every obstacle reaches right across
  `Config.PlayAreaX`. Obstacles are built from each biome's own things (THEMES[b]: Round cylinders or blocks, Main /
  Accent / Lip colours, Liquid, Wall, Step): Meadow logs/fence/mud/stumps, Tundra ice blocks/icy water/ice wall/floes,
  Dunes sandstone/quicksand/temple wall, Hellscape obsidian + lava seams/lava, Toxic pipes/barrels/acid, Candy canes/
  chocolate/cookies. Kinds (ACTIONS weights): Jump (2.6 low piece with bright top, or a kill strip ~0.3 s wide: Pit
  zone slows you, bridge after 2 misses), Slide (two 9-tall pieces stacked from 3.4 to ~22, over even a
  double jump's ~14; Gate zone slows you unless sliding; prompt BLINKS), Swing (a piece on ropes swinging at head
  height, "HeadBar": ignored while sliding), Sweeper (knee-high arms round posts), Steps (platforms over a long kill
  strip, "JUMP!" per row), Movers (two 7-tall walls sliding sideways, 16-wide gap, slowed unless in the gap:
  "GO THROUGH THE GAP!"), Double (9.5 wall: one jump ~6.4, double ~14; `forceDouble` per run, sometimes none). Added 2026-11-20 (user: "more variations"): Hurdles (2-4 low bars in a
  row), Weave (two staggered rows of 11-tall pillars), Pounders ("Smasher" blocks slamming down out of step; caught under
  one: slowed), Bridge (3 narrow planks along a kill strip, sometimes shifted halfway), Combo (low bar then a
  "HeadBar" at 3.4-6.6: slide or jump it), Bounce (neon pad zone "Pad" throws you over a 16-tall wall; zone "Back"
  slows you through the wall if you miss it). Sets of
  2-3 about 1 s apart, then a breather (`c.spacing`). Screen prompt only (`SAFD_RunPrompt`; 2026-11-22, user: "top of the screen
  near the middle": centred at y 0.27, 0.42 x 0.085, above your character's head; not the very top edge (too high for
  kids) and not low under the character (tried 2026-11-21). The tutorial line sits under it at y 0.33, Skip at 0.41), ~2 s ahead at
  your WalkSpeed; "DODGE!" while a projectile's circle (`Hazards.targets`) is near you. No world signs. hideScenery also hides
  scenery in the 30 studs before each obstacle; wild egg labels only show within 45 studs during a run (Client/EggVisuals).
  LUCK badges: BillboardGui only (invisible anchor part, AlwaysOnTop must stay OFF: on top, billboards never drew in
  this place): round gradient badge (x2 green, x3 blue, x4 purple, x5 gold: they MULTIPLY), thick outline, huge "xN"; pickup
  radius 4.6. Never right in front of an obstacle (user 2026-11-20): over it (jump height 8.6, double-jump height, over
  a bounce wall) or in the open after it (`c.afterRing`, placed by spawnNext halfway into the gap), plus trails of 3-4
  in the breathers. Picked up (2026-11-21): the badge drops in with a bounce just under the LUCK counter (top right, never over the
  way ahead), one fast glockenspiel chime per point of luck (x2 = 2 chimes, x5 = 5) climbing a scale, the badge and
  counter bumping on each, then it hops into the counter with sparkles and a bling. RunRing fires at pickup.
  Falling scenery: `RunCourse.prepare()` (Disaster.init, background) clusters each level's `Chunks.All` bricks by touch:
  trees (anywhere in PlayAreaX, 10-45 tall, <= 30 wide, not see-through, narrow trunk OR slim like a pine; on the valley floor or a low mound they topple, up on the hill steps they tumble down like props; Meadow 17, Tundra 14, Dunes 16, Hellscape 4, Toxic 10, Candy 14) and hill props
  (small bricks on the hill steps beside the valley, clusters 2.5-20 tall, <= 16 wide). Studio prints the counts per
  level, and per run how many went over. In a run EVERY cached tree within 70 studs sideways goes when it's
  6..clamp(speed*1.8, 30, 75) ahead (hill props: within 150 sideways, a bit closer), 0.12-0.3 s stagger: shake + creak
  + dust over a red strip (0.7 s), topple; most fall beside you, ~30% across (only with time to see it: "JUMP!" and an
  invisible "Trunk" box). Hill props shake and tumble down to the valley edge. CanCollide off while down; `c.moved`
  puts every brick back in RunCourse.destroy. Disaster's own hillside topple stays off (`ToppleInterval` 1e9).
  Projectiles (Config.HazardThemes per biome, 3-5 kinds each: Pumpkin, Beehive, Snowman, Urn, Skull, Obsidian, Tire,
  SludgeBucket, Donut, Cookie added 2026-11-20): one every 0.6-1.1 s (35% with a second), max 5 circles (radius <= 7), no arrows (removed:
  distracting); never on an obstacle (`RunCourse.busyAt`). Wall (2026-11-21): ALWAYS forms at the egg's biome's own
  far end (it used to form inside the next biome); close to the end it holds still for a head start
  ((WallStartDistance 40 - gap) / speed + WallFarEndHeadStart 2.5 s). Speed = WallSpeed x RunWallFactor 0.8. WallSpeed
  18/28/38/48/58/68 and Progression.walkSpeed (cubic between biomes) make the RecommendedSpeed matter: obstacles cost
  ~20% of your speed, so at the recommended speed you get home (bot playtest at 1.1K in the Tundra: the wall held ~38
  studs back), at 200 speed in the Tundra (walk 25 vs wall 22.4 minus obstacles) it catches you.
  Each biome's disaster (Client/DisasterLooks, rebuilt 2026-11-21 in the style of the user's reference picture of a
  blocky landslide): tilted broken-off earth slabs with a thick cap dripping over the front, stepped faces, rubble
  heaps, big boulders, snapped logs, a solid bank of dust-puff blocks on the ground and small cubes arcing over the top,
  per biome: Meadow LANDSLIDE (orange earth, grass, lavender rocks, logs), Tundra AVALANCHE (blue ice, snow tops, pine
  logs), Dunes SANDSTORM (sandstone, sand tops, pillars, a towering sand-billow wall), Hellscape LAVA FLOOD (basalt,
  neon lava tops, obsidian, burning logs), Toxic TOXIC SLUDGE (murky rock, slime tops, barrels), Candyland CHOCOLATE
  FLOOD (chocolate, pink frosting, gumballs, candy canes). ~650 parts, all moved with one BulkMoveTo (0.73 ms a frame);
  phones / low graphics get a lighter build (isLite). An unturned WedgePart slopes DOWN towards -Z (tested). Studio
  screen captures don't draw particles. Pictures: screenshots/2026-11-21b (git-ignored).
  During the run ChaseFx.hideUi keeps the prompts,
  egg pickup prompts ("ProximityPrompts"), the hatch screen and phone controls (TouchGui, ContextActionGui).
  Mix now (2026-11-20, user): Jump, Slide, Zigzag (1-2 red strips zigzagging right across, jump each where it crosses
  you; Pit zone with `strips` legs), Double (70% two of the biome's pieces stacked to 9.5: logs, ice blocks, sandstone,
  obsidian, pipes, candy canes; a double jump reaches ~14.8), Movers, Weave, Combo, Bounce. OFF (weight 0): Steps
  (platforms over a strip), Bridge, Hurdles (3 logs in a row), Sweeper, Swing, Pounders. No badge trails in the
  breathers (never 3 badges in a row): one badge per obstacle at most, over it or after it.
  OBSTACLES ARE SOLID, TOUCHING NEVER SLOWS (user 2026-11-20, latest): bars, walls, pillars, moving walls and the
  bounce wall are CanCollide true (you must jump / double jump / weave / bounce); the slide stacks and head bars are
  `slideBlock`s: solid except while you slide (they close again only once you are out from under them). The ONLY slow
  is standing ON a strip: Pit zones raycast straight down from your middle (`onStrip`) and only count the KillStrip
  itself, never a plank or platform over it. Strips are red (Hellscape deep dark red); obstacles keep biome colours.
  Projectile hits only flash OUCH. Sweeper, Swing and Pounders are off (weight 0): solid moving pieces would shove you.
  Bridge planks 9 wide, step pads 10 across. The wall kills only when your whole body is in it (middle 1.2 past the
  front of its main slab).
  Wild eggs are walk-through (CanCollide off, Server/AnimalService). Performance (2026-11-20 playtest, full Candyland
  run): 60 fps average, worst mid-run frame 65 ms. The map scenery index (`indexScenery`) is built in the background
  by prepare(); built on the first run it froze the game ~0.7 s.
- Trail Shop: the yellow tent (Weight_stand); the red tent (Speed_stand) is Sell Pets. Floating titles: Client/ShopTitles.
  Config.Trails = the reference's 11 trails, prices = the reference's after its price curve ($500, $8K, $210K, $10M,
  $390M, $19B ... $110Qn; 2026-11-21) (x2 .. x10K training multiplier, Look drawn by Server/ShopService on the
  HumanoidRootPart). Clicking "Equipped" keeps it on (it used to unequip silently); equipping shows a toast.
- Nothing past the white line during a run (2026-11-20): no projectiles (Disaster.launchProjectile), no badges
  (RunCourse.ring), no trees falling, and obstacles stop 70 studs before it (c.stopD). The Bounce pad obstacle is off.
- Hatch CUTSCENE (Client/Hatch, 2026-11-21, user spec; replaced the hatch screen): staged in the MIDDLE on the
  SAFE side, x -8, 30 studs back from the white line, FACING THE BIOMES (2026-11-22, user: the shot looks from the
  bases out over the valley; the camera is behind and a little right of / above you, the egg ahead near the line, the
  animal faces you). The stand-in STANDS STRAIGHT: its Animator is removed and every limb is rebuilt from the root
  along its Motor6Ds / accessory Welds with no animation offset (a plain clone kept the running pose). Other players
  are re-hidden every 0.2 s for the whole cutscene (joins / respawns too). Earlier: staged just past
  the white line (x -8, 16 studs on) wherever you crossed (sequence since 2026-11-21: the egg grows on a straw NEST,
  then bursts apart and is GONE; the animal appears above the nest as a solid bright white silhouette (Highlight fill
  white) that shakes while the odds climb, then a flash reveals its colours): a stand-in copy of your character stands there and your
  real character (anchored, hidden on your screen) stays where it stopped; nobody is teleported. Other players,
  floating labels and nearby base animals are hidden; the egg drops in front of the stand-in, the camera beside them. "🍀 Nx Luck" counts up badge by badge while the egg GROWS (ScaleTo, eggScaleFor) in ONE
  continuous, slightly speeding-up growth (2026-11-22, user: it "keeps stopping"; it used to ease to a stop at every
  badge): 0.42 s per badge (1.2-4.5 s), each badge's effects fire as its luck is passed, and it runs straight into the
  pre-explosion swell with no hold (measured: never flat for more than one frame);
  ground light rings, sparkles, pop + pentatonic notes; then it trembles and swells (0.6 s) and EXPLODES (2026-11-21, user: it "looked like it is
  being thrown"): the egg is gone at once, ~46 small shell bits fly straight out from its middle in every direction, a
  white blast ball, shock rings, camera shake (sc.shakeUntil). The silhouette then shakes while the odds climb: 1/1 ..
  1/4 just show (no build-up); from 1/5 up the count starts at 1/5 and climbs to the real odds (round(100 / chance %))
  over 2.6 s + 0.6 s per doubling past 4 (max 8 s), then a 0.6 s held breath before the reveal. Rarity FX: Rare+ sparkles + light, Epic+ Highlight glow, Legendary+ turning light beams;
  words LUCKY! / VERY LUCKY! / SUPER LUCKY! / MEGA LUCKY!! / ULTRA LUCKY!! / INSANE LUCK!!! (Rare .. Secret). Card:
  name (+NEW!), rarity, "1 in N", $/s. Several eggs: one by one. Tap / click / Space skips the waits. It waits for the
  run's own screens to go (LocalDisaster) first. Player attribute SAFD_Cutscene while it plays (Client/Ui.busy).
  Studio hook: player attribute TestHatchHold = seconds to hold the reveal. ScreenGui SAFD_Hatch.Hatch exists while it
  plays (the tutorial waits on it). Sounds: Hatch SOUNDS (free Creator Store audio).
- Tutorial (Client/Tutorial; restyled 2026-11-21 as a copy of Throw Food for Animals', studied from gameplay video):
  ONE line of white text with a black outline near the top (y 0.24, under the run prompts and biome banner), no box, no buttons, no
  step counter. Way finding: a yellow ▼ bobbing over the target (BillboardGui) and a yellow ring on the ground under
  it; for screen buttons a yellow ▼ just above the button. Steps wait for the action; tell-only steps move on after
  ~3.5 s. Order: welcome, base, treadmill, get off, white line, jump / double jump / slide (one line each, before any
  egg), grab an egg, run home (caught: "Oh no! Try again"), hatch, "Tap Animals", "Tap EQUIP", money, trail shop,
  treadmill upgrade, plot upgrade, "Tap ? for help" + "Watch the tutorial again and see the controls here", "You're
  all set! Now go save some eggs!". Plays once (data.SeenTutorial), again from Help (Tutorial.replay) or /tutorial.
  A small "Skip tutorial" pill under the line ends it (counts as done). It only starts at your base (atBase: within
  30 studs of your pen); anywhere else it first says "Go to your base to start the tutorial" and points there. The
  automatic first start also waits for your save (Loaded) and never starts mid-run.
- Help (Client/Help, 2026-11-21: replaced the always-on controls card): a blue "?" tile on the right above the
  Animals tile; its window (beside it) has WATCH TUTORIAL AGAIN and the controls (keyboard or phone wording).
- Phone controls (Client/Moves): the SLIDE button is restyled big and blue, the jump button's size, right beside it.
- Screen scaling rule (2026-11-21, user: "always scaled, also after future changes"): every screen UI of ours is
  sized as a share of the screen (Scale, or SizeConstraint RelativeYY for squares), never pixels / MinSize, so a
  phone shows the same layout as a computer. In Studio, Ui.auditScaling (15 s after start) warns about any SAFD_*
  ScreenGui child sized in pixels (attribute PixelOK to exempt one).
- Leaderboards (Server/LeaderboardService, 2026-11-21): the two Spawn_elements "Leaderboard" signs: the one nearer
  the Sell tent is TOP SPEED, the other MOST TIME PLAYED (data.TimePlayed, counted every second). OrderedDataStores
  SAFD_LB_Speed_v1 / SAFD_LB_Time_v1: every call pcall'd, retried with backoff, only within the request budget;
  writes every 120 s per player when changed + on leave + BindToClose; reads every 60 s; the last good top-10 is kept
  and merged with this server's live players, so a board is never empty or broken. 2026-11-22 (user: "the same
  leaderboard UI as Feed and Rob Animals"): the boards are the reference place's SpeedLeaderboard / PlaytimeLeaderboard
  models (extracted with scratchpad tools/extract.js), saved as Spawn_elements.Leaderboard_Speed / Leaderboard_Time
  (attribute Stat) where the old signs stood, facing spawn; old signs in ServerStorage.SAFD_Unused. The server writes
  the top 10 as JSON to the model's "Rows" attribute; Client/Leaderboards (a copy of the reference's controller) draws
  it plus YOUR POSITION from your attributes Speed / TimePlayed.
- More 2026-11-22 changes (one batch from the user):
  * Run: hideScenery is OFF (it hid single bricks of builds an obstacle overlapped: "half loaded" lava islands).
    Badges only over the valley floor (RunCourse BADGE_X -69..53) and never inside something solid (badgeBlocked:
    shifted towards the middle or skipped). Strict obstacles: Combo's slide bar now reaches 22 (slide only); new
    Tunnel (slide stacks in a row) and TwinWall (two DOUBLE JUMP! walls); weights favour Slide / Tunnel / Double / TwinWall.
  * Hatch numbers in full: Util.commas ("2,000x Luck", "1/1,500", "1 in 2,000", "$1,500/s").
  * Eggs: Config.EggNames per design (Meadow/Daisy, Frostbite/Snowball, Pharaoh/Sunset Dune, Inferno/Dragon,
    Radioactive/Hazmat, Sugar Rush/Sundae; Config.eggName). They spawn as one group (a disc in the middle of the egg
    area, EGG_GAP 6) and every biome is topped up to its Count every 10 s.
  * Map: floating pieces in all biomes moved to SAFD_Backup_HillProps (Floating_*; whole trees a little above the
    ground were set down instead); Hellscape valley-floor bits (FloorBit_*) and 183 Meadow grass stalks (GrassStalks)
    likewise. The white bar in the sky was Workspace.SAFD_PhotoStudio (old screenshot backdrop) -> SAFD_Unused.
    To raycast against decor, switch CanQuery on for the scan and back off after (Decor bricks have it off).
  * Free gift popup only while unclaimed (UIBridge zones). Help: "🐾 Animals" -> "Open your animals"; tutorial says
    Click on computers, Tap on phones.
  * Treadmills only on claimed bases (BaseService: parent nil while a plot is empty).
  * PROGRESSION = the researched one (user: "I did NOT ask for an easier progression ... study Break and Steal an Egg,
    Steal an Egg, Throw Food for Animals and apply the same"; the guessed x3 income / 40% prices were removed). Our
    biomes = Break and Steal an Egg's first six zones (same gates 5/1K/50K/750K/12M/150M, same trails x2..x10K at its
    prices $500/$7.5K/$100K/$1.2M/...). Config.AnimalIncome = its per-pet $/s in the matching zone (our Cosmic = its
    Divine, Secret = its Cosmic/zone top, Eternal = Celestial; a few "est" fill-ins), Config.BaseHatchChances = Steal an
    Egg's per-pet drop rates (Forest/Lake/Desert/Jungle/Snow/Volcano) before luck badges, treadmills = Steal an Egg's
    ladder (+2 free, +5 $15K, +12 $250K, +30 $5M, +80 $120M, +100 $3B ..., the last 6 extrapolated), pen = Break and
    Steal an Egg's (8 slots, $10K, $1M, $45M, then x40), free reward +10K speed, Index pays 100x income, sell 20x
    (Throw Food for Animals). Sources: eldorado.gg, games.gg, bloxodes, allthings.how, rblxguide (community guides; no
    official numbers exist).
  * Base button (Client/HomeButton): an orange copy of the Shop button just above it, only in a biome and not during
    a run / hatch; Net.GoHome -> BaseService.teleportHome (refused while carrying eggs or on the safe side). The pack
    button's colour is its "Border" picture (green frame with checker holes): hidden on Base, so its orange gradient
    shows plain (user: "should not be checkered").
  * Top Speed board icons = the HUD speed icon (rbxassetid://140333781098529).
  * Eggs (later the same day, "not too together ... in the same few rows"): a band right across the valley, about
    three eggs deep (rowDepth), EGG_GAP 9.
  * Obstacles (later the same day, user: "I was wrong about only slide or double jump ... not everything"): new
    Either (a bar 3.4..9.4: slide under OR double jump over, sometimes two close together; "SLIDE or DOUBLE JUMP!";
    weight x2.5 right after a slide-only / double-jump-only one) and Boost (a cyan arrow pad across: zone "Boost" ->
    Movement.boost(1.6, 2.5 s), "SPEED BOOST!"). Strict kinds stay, at lower weights.
- Biome names: the original ones (Grassy Meadows, Snowy Tundra, Sandy Dunes, Fiery Hellscape, Toxic Wasteland, Candyland),
  also on the Index cards (BiomeDiorama). A rename to Sunny Meadows etc. was tried 2026-11-21 and reverted the same day.
- Leaderboard rows show the player's avatar headshot (rbxthumb AvatarHeadShot) between the rank and the name.
- Studio-only test hooks (automated playtests): player attributes TestSlide / TestDoubleJump (Client/Moves),
  TestExitTreadmill (Client/Treadmill), TestObstacle = "Bounce,Weave" (forces those kinds in turn, Client/RunCourse), and ServerStorage.SAFD_TestHook:Invoke(name, "/addmoney 1M" or "__data").
- Lync's Studio plugin can drop its connection (edits then stop syncing): click Plugins > Lync Client > Sync again.
- Eggs (2026-11-20): the biomes hold eggs, not animals. One design per biome, built in code by `Shared/EggFactory`
  (stud bricks; Config.Eggs: Meadow Common 4.5 studs ... Sugar Rush Mythic 30 studs). The user's egg rules: Roblox stud
  style, the biome's colours and things, later biomes more detailed / impressive and bigger, shapes and details clearly
  visible, and NO Neon parts on any egg (2026-11-22: the Inferno egg was redone as basalt with a molten orange top,
  lava drips, chunky orange cracks, horns, a lava pool with rocks; the Radioactive egg as bright green with a bubbling
  slime top, slime drips kept off the radiation sign, a straight hazard band, orbiting + tipped barrels, a slime
  puddle; the Dunes gem is plain plastic now; small fire / spark particles and weak PointLights stay). TWO DESIGNS PER BIOME (2026-11-22, user: "mix and match
  ... only to design"): EggFactory.create(biome, height, design 1|2) (DesignCount 2; attribute Design). 2nd designs:
  Meadow daisy egg, Tundra snowball in a red-white scarf, Dunes sunset sandstone with a gold pyramid and cacti,
  Hellscape red dragon egg with back spikes in gold claws, Toxic metal canister with a slime window / valve / pipes,
  Candy ice-cream egg in a waffle cone with orbiting lollipops. Each wild egg picks one at random (AnimalService
  spawnEgg); the carried egg, the pickup card (RescueFx), the hatch (RunReward info.Designs) and the intro (mixed)
  use the same design; it never changes the hatch odds. Server/AnimalService spawns them
  (`Workspace.WildEggs`, tag WildEgg; Client/EggVisuals wobbles them and spins the halo/barrels), stacks picked-up ones
  on the head (`CarriedEgg_<biome>`) and hatches them at the safe line: one of the biome's 8 animals by
  `Config.hatchChances(biome, luck)` (reworked 2026-11-20, "like Steal an Egg"): luck sets a rarity floor
  (`Config.LuckFloors`: x3 Uncommon+, x6 Rare+, x10 Epic+, x15 Legendary+), and above it each animal's weight is
  `Config.HatchTiers[rarity]` (2nd of a rarity x0.8) x luck ^ (`LuckBoost` 0.25 x rarities above the lowest allowed);
  each biome 100%; no real luck cap (RunMultiplierCap 1000). RETUNED 2026-11-20 to Steal an Egg's progression (user:
  "why is it so easy to get legendary in meadow"): NO floors (Config.LuckFloors = {}). Luck is measured against the biome's good run
  (Config.BiomeLuck {2,3,4,6,8,10}: easy for kids; longer runs from further out collect more): a full run makes the biome's rarest
  animal LuckMaxBoost (3) times likelier, the rarities between less, up to LuckOverBoost (1.5) full runs. Meadow
  Legendary 0.5% at x1, 1.2% at x3; Candy Qilin 0.04% at x1, 0.1% at x28. Eggs spawn in the far 45% of each biome.
  Every obstacle offers one badge (over it or after it). Badge values are capped per biome
  (RunCourse BADGE_CAP: Meadow x2, Tundra x3, Dunes/Hellscape x4, Toxic/Candy x5). Eggs spawn at least 190 studs from
  the safe line (AnimalService MIN_RUN); obstacles: first at speed*0.8, sets of 3-4 ~0.8 s apart, 1.1-1.4 s breathers. Client/Hatch is the hatch screen: the egg grows with every luck ring and everything (size, bounce,
  sounds, shake, suspense, the hatch flash) scales with the luck; the reveal shows the real "% chance!" it had.
  An egg model has a PrimaryPart, so it pivots on `Root.PivotOffset` (its bottom centre), not WorldPivot. Eggs never
  overlap: each has a Footprint attribute (radius incl. wings) and spawns that far + 8 from others, on open floor. The
  pickup prompt sits on an Attachment 3 studs above the egg's bottom (`PromptAt`), reach = Footprint + 9: Roblox only
  shows a prompt whose point is on screen, and at the big eggs' centre it was off the top of the screen.
  After a hatch nothing is put in your hand, and one click places one animal then puts the tool away (Client/Hotbar):
  auto-equip + clicks used to drop whole stacks into the base. Client/Hatch is DisplayOrder 60 (above Offline Cash).
- Luck MULTIPLIES (2026-11-21, user: "x3 then x3 is x9, it should keep growing"): badges x2/x3/x4/x5, the counter,
  the server (run.mult *= value) and the hatch count-up all multiply; RunMultiplierCap 1e15 only keeps it finite;
  numbers show with Util.formatNumber ("LUCK x1.5M"). Rescaled: Config.BiomeLuck = a kid's good run (~70% of the
  badges) per biome {10, 1e3, 5e4, 1e6, 1e7, 5e7}, and hatchChances measures luck on a LOG scale against it
  (log(luck) / log(BiomeLuck)), so the odds at a full run are the same as before (rarest x3, up to x4 at 1.5 runs).
  The badge counts per run are estimates from the run lengths and speeds, not measured. Luck only changes hatch odds,
  never income. Saved animals
  are plain ids; old `Chicken*8` keys and placed `M` are stripped on load (they no longer earn more).
- Index: StarterGui.Index is the reference place's own Index GUI (the old look-alike is in ServerStorage.SAFD_Unused.OldIndex);
  Client/UIBridge fills it with our biomes and 3D animal views, black silhouettes when locked. Each biome's side card
  (2026-11-21, like Throw Food for Animals' cards): the biome's colour with a white border, its short name on top, a
  little block island of the biome in a ViewportFrame (Client/BiomeDiorama: checkered top, drips, the biome's props and
  egg) and "(38%)" discovered at the bottom (refreshIndex). Cards are repainted by the animal's rarity (CARD_COLORS).
  The hotbar slots show each animal's $/s and rarity.
  2026-11-22 (user: "analyse other games' indexes ... add all, completion reward like Throw Food for Animals";
  researched: Steal an Egg per-pet Claim + Claim All + red badge + biome weapon, Throw Food for Animals extra cash
  per completed biome, Brainrot permanent multipliers): a biome with all 8 found shows a gold "🏆 CLAIM $X" on its
  card (Net.ClaimBiomeReward; Config.biomeCompleteReward = 100 x the biome's 8 incomes added up, Meadow $700.6K;
  data.BiomeClaimed["1".."6"]), then "✅ COMPLETE!". The claim lives in a Throw Food for Animals style reward card
  under the animals (UIBridge rewardRow, user: "match the reward, follow Throw Food for Animals"): the pack's n/8
  CollectionProgress bar is narrowed and its weapon picture (a bat) hidden; beside it "Biome Reward", the HUD cash icon,
  the amount, and a button Locked (grey) / CLAIM! (gold) / Done (green, ✅ over the cash). CLAIM ALL (n) in the Index header (Net.ClaimIndexAll: every
  unclaimed per-animal reward at once) and a red count badge on the HUD Index button (unclaimed animal + biome rewards).
- Simple-UI pass (2026-11-21, user: "study Throw Food for Animals ... keep it simple"):
  * My Animals (Client/AnimalsPanel, a copy of Throw Food for Animals'): the "Animals" tile on the right, half way
    down (dark tile, drawn orange paw Ui.paw, "Animals" under it); the window opens right beside it. ON YOUR PLOT
    (PICK UP / SELL), BACKPACK (EQUIP / SELL). ON YOUR BASE n/cap (PICK UP,
    SELL) and BACKPACK (PLACE at a free spot, SELL), EQUIP BEST (the best earners that fit). SELL asks "SURE? $X" first.
    Server: Net.AnimalAction ("PickUp" uid | "SellPlaced" uid | "Sell" id | "Place" id | "EquipBest"),
    AnimalService.pickUp / placeFromMenu (freeSpot: the grid point furthest from the others) / equipBest. The client
    state now has Placed, Capacity, BaseTier, TreadmillLevel.
  * "NEW EQUIPMENT!" popup (Client/BuyNotice, an exact copy of Throw Food for Animals': striped blue band, red X,
    picture tile, YOU CAN NOW BUY, name, green price + blue stat, green UPGRADE, orange timer bar), dropping in at the
    TOP of the screen: the moment you can afford the cheapest unowned trail, the next
    treadmill or the next base: picture, name, price, what it gives, BUY! (buys right there), auto-closes in 9 s, once
    per thing per session. Never during a run / hatch / intro (Ui.busy) or while a window is open (Ui.windowOpen: any
    ScreenGui attribute "...Open" = true) or during the tutorial.
  * Trail Shop: cheapest first (LayoutOrder by price), money buttons GREEN when affordable / owned, RED when not, SOLID
    colours (user: "no stripes": the pack's Gloss + Checker layers are hidden; 2026-11-22 "full red button": the pack's
    yellow-green InnerStroke and the price text's dark green outline are recoloured red on red buttons), the label fills the button, and clicking one you can't afford shows "NOT ENOUGH MONEY! Need $X more" on the card itself
    (no server call). HUD toasts are DisplayOrder 70 now (they showed behind the shops).
  * Danger warning (Client/AreaBanner): walking into a biome under its RecommendedSpeed (not in a run, not in the
    tutorial) stops you with "⚠️ DANGER ZONE! The avalanche here is SUPER fast! Your speed / Needed. Are you brave
    enough to save these eggs?" I'M BRAVE! (Name Brave) / TRAIN FIRST (Name Train: back onto your treadmill). Once per
    biome until you cross the white line. The biome banner is bigger (no "Your speed" line: too cluttered).
  * Shared UI helpers: Client/Ui (text, frame, button, viewport, pop, busy, windowOpen).
- Animal sizes (2026-11-21, "legendary should look huge"; 2026-11-22 "much bigger"): Rarities BaseSize 1, 1.25, 1.6,
  2.2, 4.8 (Legendary), 5.8, 6.8, 7.8, 8.8. In the base (2026-11-22, "extending too much out of the base"): at most
  Config.MaxBaseAnimalHeight 40 tall and Config.MaxBaseAnimalWidth 30 long (the pen is ~38 across; long animals like
  the Axolotl / Crocodile used to reach 56). A Meadow Legendary stands 24 studs.
- Phone: the SLIDE button hides while you're on the treadmill (attribute Training; only the Stop button shows).
- Projectile red circles (Disaster.launchProjectile, 2026-11-22: they landed on trees): x kept over the valley floor
  (-69..53) and only where the ground found is the floor itself (<= floor + 1.5); otherwise moved towards the middle
  or skipped.
- Valley floors decluttered (2026-11-20, user): the props standing on each biome's flat floor (rocks, bones, crystals,
  bushes, flowers, small posts...) were moved, not deleted, to `ServerStorage.SAFD_Backup_ValleyProps/<Level>/`; each
  brick has attribute `SAFD_From` = its old parent's full name, so it can be put back. Trees (green ones, narrow-trunk
  ones, the Hellscape dead trees, Candyland's tall candy trees), hills and hill decorations stay. Version 104 is the
  place from before. Small rocks touching a tree trunk count as part of the tree and stayed. Toxic Wasteland and
  Candyland were cleared again to trees only (thin and tall: <= 13 wide, >= 20 tall), incl. the water tower, the
  gingerbread house, slime splats; chocolate puddles that filled holes were recoloured to floor instead, and
  Candyland's SafetyFloor (SAFD_Boundaries) is now visible pink so floor holes don't show. Later the same day:
  Tundra's small green stalks (not the pines), the Dunes oasis (Level3_POI model + LightPart; the 3 palms that stood on
  its mound were lowered 5.2 studs onto the sand, fronds too) and every Hellscape skeleton on the floor (the POI
  skull mesh, both ribcages, scattered bones and their dark rubble bases; bones are pinkish-tan ~0.8,0.6,0.55) went.
  Then the 4 see-through ice spires standing on the Tundra floor (Prop_IceSpires); the hill ones stay.
  Fences (2026-11-20, user: "remove the fences in all biomes"): Dunes 17 fence models + their 17 lanterns (floor and
  hills), Tundra 30 hill fence pieces (wood 5b443e/6c514a) + 8 broken posts on the floor, Candyland 17 candy-cane
  fences (chunk bricks, as models "CandyCaneFence"), and the Tundra POI floating ice crystal (bottom 41 studs up), all
  in `ServerStorage.SAFD_Backup_ValleyProps/<Level>` with SAFD_From / SAFD_Why. Lamp posts stay. Meadow had none.
  2026-11-21 (user: "floating brown stuff" in the Dunes): 10 single orange blocks (eb7a41, 1.5x1.5x2.2, in pairs 12-16
  studs over the floor, leftovers of the removed fence lanterns in Level3Environment) went to the same backup. To find
  floating pieces, group bricks by bounding-box contact: Decor bricks have CanQuery off, so GetPartBoundsInBox misses them.
- Side hills decluttered (2026-11-21, user: "the sides should have the same amount of stuff as the valley"): on the
  hills (x < -77 or > 61; the valley floor is x -75.5..59.5, the Level*_track parts are ROTATED so use their AABB) all
  props went: rocks, fences, posts, flowers, grass stalks, lanterns, ice spires, ribcages, skulls, lava boulders, cakes,
  candy canes, chocolate rocks, slime blobs. Kept: trees (pines, leafy trees, cacti, dead trees, candy trees), the cliffs
  and hill tops, the hill slopes (Environment Plane*/Cube MeshParts), lava, the WARNING signs. Moved (not deleted) to
  `ServerStorage.SAFD_Backup_HillProps/<Level>/` with SAFD_From / SAFD_Why (~19k bricks + ~140 env models).
  Method: cluster hill bricks by AABB contact; "terrain" = big bricks (>= 12) in the colours making up 90% of the big
  bricks' volume; tree = tall green / tall brown or candy (Toxic: thin pines only, Candy: >= 16 tall, <= 14 wide);
  bits under a tree's crown stay (trunks split off by a big brick). Edge strips at the biome ends were left alone.
- Intro cutscene (Client/IntroCutscene): eggs with sweat drops (the plain 💧 emoji on a BillboardGui since 2026-11-21:
  the glassy ball drop "looked weird"), the hero saves all 8; title "Save Eggs from Disasters".
- Lobby music (Client/LobbyMusic, 2026-11-22): HAPPY, cheerful Christmas music, NEVER sad (user: the calm Christmas
  list was "too calm and sad"; before that calm classical, and the Tchaikovsky Trepak list had loud bursts): 8 free
  Creator Store tracks (APM Jingle Bells jazz piano, Snow Ball Fun, We Wish You A Merry Christmas, Tiptoe Marimba
  Elves, Happy Christmas, Christmas Father's Sled, Jingle Bells instrumental, Christmas Presents; IDs in TRACKS), in turn, EVERYWHERE (spawn, bases, biomes; user
  2026-11-21): it fades out during the chase home (egg carried / LocalDisaster) and the hatch cutscene (SAFD_Cutscene;
  user 2026-11-22), volume x MusicVolume. The red WARNING signs (2 per biome, Environment "Text" MeshParts) were
  removed 2026-11-22 (user), kept in ServerStorage.SAFD_Backup_HillProps/<Level>. Offline Cash: Claim is centred when the x2 button is hidden (UIBridge).
- No loading screen (2026-11-21, user): First/Loading only waits for game.Loaded, sets WorldReady and preloads meshes /
  pictures in the background; Roblox's own short default screen covers the place arriving.
- Admins: the owner (`Config.Admins` / creator) can make admins in game (`/admin`, `/unadmin`, panel tab); they are
  saved in the `SAFD_Admins_v1` DataStore.
- HUD labels: the UI pack's NativeLayout fixes text sizes once; Client/UIBridge keeps the stat labels TextScaled. Never
  set TextWrapped = false on them: that turns TextScaled off too.
- DataStore needs the place published (and Studio API access on); until then data is not saved.
- Automated playtests: `Humanoid:Move` from execute_luau does nothing here, so drive runs with MCP
  `user_keyboard_input` (keyDown W; the camera faces home after an egg pickup) plus a Heartbeat loop that jumps / sets
  TestSlide on the prompt. A bot that jumps on DODGE! cancels its own slide; real players hold slide and pass.
