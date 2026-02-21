# agents.md — Game2D Project Context

> This file is the canonical reference for all AI agents, developers, and contributors working on this project.
> Update it whenever you discover new gotchas, add systems, or change architecture.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Technology Stack](#2-technology-stack)
3. [Directory & File Tree](#3-directory--file-tree)
4. [Architecture Overview](#4-architecture-overview)
5. [System: World & Arena](#5-system-world--arena)
6. [System: Item System](#6-system-item-system)
7. [System: Entities (Player, Creature, Rat)](#7-system-entities-player-creature-rat)
8. [System: Components](#8-system-components)
9. [System: UI](#9-system-ui)
10. [Networking](#10-networking)
11. [Asset Pipeline & Known Limitations](#11-asset-pipeline--known-limitations)
12. [Godot-Specific Gotchas](#12-godot-specific-gotchas)
13. [Onboarding: How to Run & Extend](#13-onboarding-how-to-run--extend)
14. [Known Issues & TODO](#14-known-issues--todo)
15. [Change Log for Agents](#15-change-log-for-agents)

---

## 1. Project Overview

A multiplayer top-down 2D RPG-style game built with **Godot 4.3** (Mobile renderer, GL Compatibility).

- Tile-based arena with walls and floors.
- Players connect via ENet (host/join via IP).
- Creatures (Rats) are spawned server-side and roam aggressively.
- A grid-based item system allows items to exist on the floor, be picked up, stacked, stored in containers, and managed via inventory UI.
- All gameplay logic is authoritative on the server; clients handle input and visuals.

---

## 2. Technology Stack

| Component     | Detail                                  |
|---------------|-----------------------------------------|
| Engine        | Godot 4.3                               |
| Language      | GDScript                                |
| Renderer      | GL Compatibility (Mobile profile)       |
| Networking    | ENet via Godot's built-in multiplayer   |
| Audio driver  | Dummy (no audio currently)              |
| Platform      | Linux (headless/server supported)       |
| Screen Size   | 1152 × 648                              |

---

## 3. Directory & File Tree

```
Game2D/
├── project.godot                    # Godot project config; main scene = scenes/ui/Main.tscn
├── icon.png.import
├── LICENSE
├── README.md
├── agents.md                        # THIS FILE
│
├── tests/
│   └── test_item_system.gd          # Headless non-GUI tests: stacking, pickup, floor grid, anti-cycle
│
├── assets/
│   ├── dog_cat_rat.png              # Rat/creature spritesheet
│   ├── player.png                   # Player spritesheet
│   ├── player.png.import
│   ├── player_simple.png            # Simple player sprite
│   ├── player_simple.png.import
│   ├── rat_sprite.png               # Rat sprite
│   ├── rat_sprite.png.import
│   ├── sword_normal.png             # Sword icon (32x32 RGBA PNG)
│   ├── sword_normal.png.import      # Import metadata (manually created; .ctex NOT generated)
│   └── tileset.png                  # Tileset
│       tileset.png.import
│
├── scenes/
│   ├── entities/
│   │   ├── Creature.tscn            # Base creature scene (CharacterBody2D + components)
│   │   ├── Floor.tscn               # Floor tile (StaticBody2D or Area2D)
│   │   ├── ItemEntity.tscn          # Floor item entity (Area2D + Sprite2D + CollisionShape2D)
│   │   ├── Player.tscn              # Player scene (CharacterBody2D + components)
│   │   ├── Rat.tscn                 # Rat scene (extends Creature)
│   │   ├── Spawner.tscn             # Creature spawner node
│   │   ├── Wall.tscn                # Wall tile (StaticBody2D)
│   │   └── World.tscn               # Main game world scene
│   └── ui/
│       ├── BattleMenu.tscn          # Draggable creature target selector panel
│       ├── DamageNumber.tscn        # Floating damage label
│       ├── Highlights.tscn          # Entity highlight overlays
│       ├── HPBar.tscn               # HP progress bar
│       ├── Main.tscn                # Entry point (host/join menu)
│       └── PlayerHUD.tscn           # Player HP bar + combat log overlay
│
├── scripts/
│   ├── core/
│   │   ├── CombatComponent.gd       # Handles attack timing, damage, range checks
│   │   ├── FloorGrid.gd             # 2D tile grid: stores item piles per tile
│   │   ├── GameConstants.gd         # Global autoload: tile size, screen size, colours, etc.
│   │   ├── GridService.gd           # Global autoload: tile math, entity registry, tile occupancy
│   │   ├── HealthComponent.gd       # HP, damage, heal, die signals
│   │   ├── ItemMoveController.gd    # Server-side item move/split/merge business logic
│   │   ├── MovementComponent.gd     # Tile-based movement, pathfinding integration, stuck detection
│   │   ├── Spawner.gd               # Server-side timed creature spawner
│   │   ├── VisualsComponent.gd      # Sprite direction, HP bar updates, damage numbers
│   │   └── World.gd                 # Arena generation, player/item spawning; delegates tile math to GridService
│   ├── entities/
│   │   ├── Creature.gd              # Base AI creature: movement, combat, aggression FSM
│   │   ├── ItemEntity.gd            # Floor-placed item (Area2D); texture cached; registers with GridService
│   │   ├── Player.gd                # Player: input, regen, combat targeting, damage log RPC
│   │   └── Rat.gd                   # Rat subclass: sets Aggressive AI, loads rat sprite texture
│   ├── resources/
│   │   ├── ItemData.gd              # Resource: item metadata (id, flags, icon, stack size, etc.)
│   │   ├── ItemInstance.gd          # Resource: live item (data ref, count, container contents)
│   │   ├── gold_coin.tres           # ItemData resource for stackable gold coin
│   │   └── sword.tres               # ItemData resource for the Sword item (icon = null for headless)
│   └── ui/
│       ├── BattleMenu.gd            # Draggable creature list; click to target/untarget
│       ├── ContainerUI.gd           # UI for container items (renders ItemSlot children)
│       ├── DamageNumber.gd          # Floating label: rises and fades on spawn
│       ├── HPBar.gd                 # Colour-gradient HP bar
│       ├── ItemSlot.gd              # Single inventory/container slot; renders icon + qty
│       ├── Main.gd                  # Host/join logic, ENet peer setup
│       └── PlayerHUD.gd             # Polls local player HP; renders log lines
│
└── .godot/
    ├── imported/                    # Engine-generated .ctex compiled textures (do not edit)
    └── global_script_class_cache.cfg
```

---

## 4. Architecture Overview

```
Main.tscn (entry)
  └── World.tscn (game world, Node2D, y_sort)
        ├── Players/              (MultiplayerSpawner target)
        ├── Creatures/            (MultiplayerSpawner target)
        ├── MultiplayerSpawner    (Player spawning)
        ├── FloorGrid             (item data layer, child node)
        ├── ItemMoveController    (item move/split/merge logic, child node)
        ├── Spawner               (Rat spawning, server-only)
        ├── BattleMenu            (UI overlay)
        └── PlayerHUD             (UI overlay)

Autoloads (available globally):
  GameConstants   — constants (tile size, screen size, colours)
  GridService     — tile math, entity registry (ItemEntity map), tile occupancy
```

**Data flow:**
- `Main.gd` sets up ENet peer, then instantiates `World.tscn` on game start.
- `World.gd` runs `_ready()` server-side: generates arena tiles, sets up FloorGrid + ItemMoveController, spawns creatures and test items.
- `Player.gd` handles movement input and combat targeting; RPC for damage numbers and log. Uses `GridService` directly for tile math.
- `Creature.gd` AI runs only on server; uses `MovementComponent` and `CombatComponent`. Caches player list; refreshes every 1s.
- `MovementComponent.gd` caches the world node reference in `_ready()`. Tile math goes through `GridService`. Static collision shape (`CircleShape2D`) is allocated once and reused.
- `ItemMoveController.gd` contains all server-side item move/split/merge logic; owned by World as a child node.
- `GridService` (autoload) maintains an `_item_entity_map` (tile → ItemEntity) for O(1) lookups, replacing linear group scans.

---

## 5. System: World & Arena

**File:** `scripts/core/World.gd`

### Arena Generation
- Tiles span from `(-6, -6)` to `(6, 6)` relative to `center_pos` (`Vector2(576, 324)`).
- Inner 5×5 radius = floor tiles; outer ring = wall tiles.
- All tiles are instantiated as child nodes of an `Environment` Node2D.

### Key Methods

| Method | Signature | Description |
|---|---|---|
| `_generate_arena()` | `()` | Spawns floor/wall tiles procedurally |
| `_setup_astar()` | `()` | Builds AStar2D graph for all floor tiles |
| `_spawn_item_at_tile(path, tile)` | `(String, Vector2i)` | Loads ItemData, creates ItemInstance, spawns ItemEntity on floor at tile |
| `get_astar_path(from, to, exclude)` | `(Vector2, Vector2, Node) -> PackedVector2Array` | AStar2D pathfinding; temporarily disables tiles occupied by entities |
| `get_tile_coords_robust(pos)` | `(Vector2) -> Vector2i` | Backward-compat wrapper — delegates to `GridService.world_to_tile()` |
| `is_tile_occupied(pos, exclude)` | `(Vector2, Node) -> bool` | Backward-compat wrapper — delegates to `GridService.is_tile_occupied()` |

### GridService (autoload)
**File:** `scripts/core/GridService.gd`

All tile math and entity registration lives here. Available globally as `GridService`.

| Method | Description |
|---|---|
| `world_to_tile(pos)` | World Vector2 → tile Vector2i (round-based, drift-safe) |
| `tile_to_world(coords)` | Tile Vector2i → world Vector2 (centre of tile) |
| `is_tile_occupied(pos, exclude)` | True if any player/creature occupies or has reserved that tile |
| `register_item_entity(entity)` | Called by ItemEntity on `_ready()` |
| `unregister_item_entity(entity)` | Called by ItemEntity on `_exit_tree()` |
| `move_item_entity(entity, old, new)` | Updates registry when entity moves tile |
| `get_item_entity_at(tile)` | O(1) lookup by tile; returns null if not found or invalid |

### ItemMoveController
**File:** `scripts/core/ItemMoveController.gd`

Child node of World. Handles item move/split/merge after World validates the RPC.

| Method | Description |
|---|---|
| `execute(entity, item_tile, drop_tile, moving)` | Main entry: tries merge, then split or whole-stack move |
| `try_merge(entity, item_tile, drop_tile, moving)` | Merges into existing compatible stack at dest; returns true on success |
| `split(entity, item_tile, drop_tile, moving)` | Creates a new entity with `moving` units at `drop_tile` |
| `move_whole(entity, item_tile, drop_tile)` | Moves entire stack reference to `drop_tile` |

### FloorGrid
**File:** `scripts/core/FloorGrid.gd`

- Instantiated in `World._ready()` as a child node.
- Stores items as `Dictionary { Vector2i => Array[ItemInstance] }`.
- Items stack automatically if `can_stack_with()` returns true and the pile is not full.
- `move_item_between`: moves by reference (no `duplicate()`); partial moves create a new `ItemInstance` for the split portion.

---

## 6. System: Item System

### ItemData (`scripts/resources/ItemData.gd`)
Pure metadata resource. Fields:

| Field | Type | Description |
|---|---|---|
| `id` | String | Unique identifier (e.g. `"sword"`) |
| `name` | String | Display name |
| `weight` | float | Item weight |
| `icon` | Texture2D\|null | Visual icon — **null is safe and required in headless mode** |
| `is_collectable` | bool | Can be picked up |
| `is_stackable` | bool | Can stack multiple in one slot |
| `max_stack` | int | Maximum per stack |
| `is_consumable` | bool | Consumed on use |
| `is_usable` | bool | Can be activated/used |
| `is_container` | bool | Can contain other items |
| `container_slots` | int | Slot limit (0 = unlimited) |

### ItemInstance (`scripts/resources/ItemInstance.gd`)
Live runtime item. Fields:

| Field | Type | Description |
|---|---|---|
| `data` | ItemData\|null | Points to ItemData definition |
| `count` | int | Stack count |
| `contents` | Array | Child items or nulls (containers only). `null` entries = empty slots. Fixed-length when `container_slots > 0`, growable when 0. |
| `parent_container` | ItemInstance\|null | For anti-cycle traversal (not exported) |

Key methods: `can_stack_with`, `add_to_stack`, `remove_from_stack`, `is_full`, `is_empty`, `can_add_to_container`, `add_to_container`, `remove_from_container`.

**Container slot placement rule** (`add_to_container` / `_place_item`):
1. Scan all slots: if any holds a same-type stackable that is not full, merge into it.
2. Otherwise, find the first null (empty) slot and place there by reference.
3. If no empty slot exists, recurse depth-first into any nested container slots.

**Anti-cycle logic:** `can_add_to_container()` walks the `parent_container` chain upward using a visited set, rejecting the item if it already exists in the ancestor chain.

**Items are always stored by reference** — no `duplicate()` calls in container or floor logic.

### FloorGrid (`scripts/core/FloorGrid.gd`)
Grid of item piles. Key methods:

| Method | Description |
|---|---|
| `get_items_at(pos)` | Returns Array of ItemInstances at tile |
| `has_items_at(pos)` | Returns bool |
| `add_item(pos, item)` | Stores item by reference; stacks onto the **top** (last) pile entry if compatible and not full; otherwise appends as new top |
| `remove_item(pos, item)` | Removes by object identity; no-op if not found |
| `remove_item_at(pos, idx)` | Removes and returns item by index |
| `move_item_between(src, idx, dst, amount)` | Partial or full stack move |
| `clear_tile(pos)` | Removes all items from a tile |
| `clear()` | Empties the entire grid |

### ItemEntity (`scripts/entities/ItemEntity.gd`)
A floor-placed `Area2D` node that wraps an `ItemInstance`. Registers in the `"item_entities"` group and in the `GridService` entity registry on `_ready()`, unregisters on `_exit_tree()`.

- `set_item(new_item)` — assigns instance, invalidates texture cache, and refreshes sprite.
- `update_visual()` — safely sets `sprite.texture`; null-safe (works with no icon).
- **Texture caching:** The PNG is loaded from disk only when `icon_path` changes; the `ImageTexture` is cached in `_cached_texture` and reused on subsequent `update_visual()` calls (e.g. when only the count label updates).
- No auto-pickup on contact. Items are moved only via the drag-and-drop system.

### Drag-and-Drop Item Movement

Items on the floor can be repositioned by the local player using the mouse:

1. **Drag start** (left mouse press): `Player._input()` checks whether the clicked tile is within Chebyshev distance ≤ 1 of the player. If so, it calls `_find_item_entity_at()` (group query on `"item_entities"`) to find an item there. If found, it stores the reference in `_dragged_item_entity` and swallows the event (no walk).
2. **Drag end** (left mouse release): if `_dragged_item_entity` is set, `Player._input()` calls `world.request_move_item.rpc_id(1, entity_path, drop_tile, peer_id)` and clears the drag state.
3. **Server validation** (`World.request_move_item`): runs server-side only; re-checks proximity of the requesting player to the item, validates the drop tile is inside the arena, then updates `floor_grid` and teleports the `ItemEntity` to the new tile position.

No visual ghost is shown during the drag. The item stays at its origin tile until the mouse button is released.

### sword.tres (`scripts/resources/sword.tres`)
A serialized `ItemData` resource for the Sword:
- `icon = null` (deliberately; `sword_normal.png` exists but is not imported as `.ctex`).
- `is_collectable = true`, `is_usable = true`, `is_stackable = false`.

### ContainerUI (`scripts/ui/ContainerUI.gd`)
Control node that renders `ItemSlot` children for a container `ItemInstance`. Call `set_container(item_instance)` to populate.

### ItemSlot (`scripts/ui/ItemSlot.gd`)
Single slot Control. Shows icon and optional quantity label. `_gui_input` is a placeholder for drag-and-drop logic.

---

## 7. System: Entities (Player, Creature, Rat)

### Player (`scripts/entities/Player.gd`)
- `CharacterBody2D` with child components: `HealthComponent`, `MovementComponent`, `CombatComponent`, `VisualsComponent`.
- Arrow keys: tile-step movement via `MovementComponent.try_move()`.
- Left mouse click: requests path from world, calls `MovementComponent.move_to(path)`.
- HP regen loop runs server-side.
- `set_target(enemy)` / `target_enemy_path` for combat targeting.
- `die()` teleports back to center and fully heals.

### Creature (`scripts/entities/Creature.gd`)
- Same component structure as Player.
- AI FSM: `Neutral`, `Aggressive`, `Passive` (set via `aggression_type`).
- Aggressive: pursues nearest player using `get_astar_path`, attacks when in melee range.
- Passive: moves away from nearest player.
- Neutral: moves randomly.
- All AI runs server-side only.

### Rat (`scripts/entities/Rat.gd`)
- Extends `Creature.gd` (via `extends "res://scripts/entities/Creature.gd"`).
- Defaults: `Aggressive`, `move_interval = 0.8`.
- Loads texture via `visuals.load_texture_safe("res://assets/dog_cat_rat.png")`.

---

## 8. System: Components

All components are `Node` children of entity scenes.

### HealthComponent (`scripts/core/HealthComponent.gd`)
- Signals: `health_changed(current, maximum)`, `damaged(amount)`, `healed(amount)`, `died`.
- `take_damage(amount)`, `heal(amount)`, `is_alive()`.

### MovementComponent (`scripts/core/MovementComponent.gd`)
- Tile-step movement using `CharacterBody2D.move_and_slide()`.
- `try_move(direction)` — checks occupancy and static collisions before committing a step.
- `move_to(path)` — follows a `PackedVector2Array` path.
- `teleport(pos)` — instant warp.
- Stuck detection: if entity doesn't move for 0.8s, snaps to nearest grid point.
- **Performance:** world node reference cached in `_ready()`; `CircleShape2D` for static collision checks allocated once and reused.
- Tile math delegated to `GridService` (no `world.get_tile_coords_robust` calls).
- Signals: `movement_started`, `movement_finished`, `direction_changed(direction)`.

### CombatComponent (`scripts/core/CombatComponent.gd`)
- `handle_combat(attacker, target)` — rate-limited by `attack_interval`.
- `perform_attack(target)` — computes `max(0, rand(0, attack) - defense)` damage.
- `is_in_range(attacker, target)` — checks distance vs. `TILE_SIZE * melee_range_multiplier`.
- Signals: `target_changed(new_target)`, `attacked(target, damage)`, `hit_received(amount)`.

### VisualsComponent (`scripts/core/VisualsComponent.gd`)
- Connects to `HealthComponent.health_changed` and `CombatComponent.target_changed`.
- Directional sprite support: configurable rows per direction, horizontal/vertical priority.
- `load_texture_safe(path)` — loads PNG via `Image.load_from_file()` + `ImageTexture.create_from_image()`, bypassing Godot's resource importer entirely. **This is the correct headless-safe texture loading method.**
- `spawn_damage_number(amount, color)` — instantiates `DamageNumber.tscn` at entity position.
- `update_attacker_status(is_being_attacked)` — toggles attacker highlight.

### Spawner (`scripts/core/Spawner.gd`)
- Server-only timed spawner for any `creature_scene: PackedScene`.
- Spawns one creature immediately on `_ready()`, then on timer.
- Tracks `creature_count`; respects `max_creatures`.
- Adds creatures to `world/Creatures` node with `force_readable_name = true`.

---

## 9. System: UI

### Main (`scripts/ui/Main.gd`)
- Entry scene. Host creates ENet server on port 7000; join connects to IP.
- On success, instantiates `World.tscn` and adds to scene tree.

### PlayerHUD (`scripts/ui/PlayerHUD.gd`)
- `CanvasLayer` with HP bar, HP label, and scrolling combat log.
- Polls local player's `HealthComponent` every 0.1s.
- `add_log(text)` keeps last 10 lines.
- Registers in `"hud"` group so Player can call it via `get_first_node_in_group("hud")`.

### BattleMenu (`scripts/ui/BattleMenu.gd`)
- Draggable panel listing all live creatures with HP.
- Click to set player target; click again to deselect.
- Refreshes every 0.5s.

### HPBar (`scripts/ui/HPBar.gd`)
- `ProgressBar` subclass with colour gradient (green → yellow → red).
- `update_hp(current, maximum)` for external updates.

### DamageNumber (`scripts/ui/DamageNumber.gd`)
- `Label` that rises 60px and fades over 1.5s via `Tween`, then frees itself.
- `set_values(amount, color)` to configure before `start_animation()`.

---

## 10. Networking

- **Authority:** Server (`multiplayer.is_server()`) is authoritative for all gameplay: spawning, AI, combat, damage.
- **Clients:** Handle own input, receive synced state via `MultiplayerSpawner` and RPC calls.
- **RPCs used:**
  - `Player.spawn_damage_number.rpc(amount, color)` — all peers show damage numbers.
  - `Player.add_to_log.rpc_id(peer_id, text)` — per-player log messages.
- **MultiplayerSpawner** nodes in `World.tscn` handle Player and Rat scene replication.
- ENet port: `7000`. Default server IP: `127.0.0.1`.

---

## 11. Asset Pipeline & Known Limitations

### How Godot imports assets
Godot 4 requires every PNG to be processed into a `.ctex` binary file stored in `.godot/imported/` before it can be loaded as a `Texture2D` via `load()` or `.tres` references. This processing is **only performed by the Godot GUI editor**, not by headless/server runs.

### Current asset status

| Asset | .import file | .ctex in .godot/imported/ | Status |
|---|---|---|---|
| player.png | Yes | Yes | Fully imported |
| player_simple.png | Yes | Yes | Fully imported |
| rat_sprite.png | Yes | Yes | Fully imported |
| tileset.png | Yes | Yes | Fully imported |
| sword_normal.png | Yes (manual) | **No** | **Not imported — icon set to null** |
| dog_cat_rat.png | No | Yes (loaded via Image API) | Loaded headless-safe via `load_texture_safe()` |

### Headless-safe texture loading
`VisualsComponent.load_texture_safe(path)` loads PNG files directly using:
```gdscript
var img = Image.load_from_file(ProjectSettings.globalize_path(path))
sprite.texture = ImageTexture.create_from_image(img)
```
This bypasses the importer entirely and works in headless/server/CI mode.

**Use this pattern for any new sprite/texture that must work headless.**

### sword_normal.png workaround
`sword.tres` has `icon = null`. The sword spawns on the floor with no visible sprite. To add the icon:
1. Either open the project once in the Godot 4 GUI editor (auto-imports all assets).
2. Or implement icon loading in `ItemEntity.update_visual()` using `load_texture_safe` from VisualsComponent.

---

## 12. Godot-Specific Gotchas

### 1. `class_name` scripts cannot be preloaded — remove `class_name` from instantiated scripts
In Godot 4.3, a script that declares `class_name Foo` **cannot be `preload()`-ed** at parse time — the engine raises "Could not preload/resolve" errors. At the same time, bare `Foo.new()` in a scene script (not an autoload) may also fail if the engine hasn't indexed the class yet.

**The only reliable pattern:** remove `class_name` from any script you need to instantiate via `.new()`, and `preload` it using a distinct variable name:

```gdscript
# ItemInstance.gd — NO class_name declaration
extends Resource
# (no class_name line)

# In the script that needs to create instances:
const _ItemInstance = preload("res://scripts/resources/ItemInstance.gd")
var inst = _ItemInstance.new()
```

Scripts that **only** serve as scene node scripts (attached to a `.tscn`) do not need `class_name` and should not have it unless they are used as type identifiers in other scripts.

**Current scripts without `class_name` (preload to instantiate):**
- `ItemData` — `scripts/resources/ItemData.gd`
- `ItemInstance` — `scripts/resources/ItemInstance.gd`
- `FloorGrid` — `scripts/core/FloorGrid.gd`
- `ItemMoveController` — `scripts/core/ItemMoveController.gd`

**Current scripts with `class_name` (scene node scripts — do not preload):**
- `MovementComponent`, `Creature`, `ItemEntity`, `VisualsComponent`

**Autoloads (use by singleton name, never preload):**
- `GameConstants`, `GridService`

### 2. Custom type hints cause parse errors in headless mode
**Never use user-defined class names as type hints** in function signatures, `@export` fields, or return types.

```gdscript
# BAD — will break in headless/unindexed environments:
func set_item(new_item: ItemInstance): ...
@export var item: ItemInstance

# GOOD — always safe:
func set_item(new_item): ...
@export var item = null
```

### 3. .tres resources referencing unimported images
If a `.tres` file has `[ext_resource type="Texture2D" path="..."]` pointing to an unimported PNG, **the entire resource fails to load**, breaking all code that depends on it. Always set `icon = null` for item resources in headless environments.

### 4. Method signature mismatches crash at runtime
Godot does not warn at parse time if you call a function with the wrong number of arguments—it only errors at runtime. Always verify call sites match method signatures when refactoring.

### 5. World utility methods must always exist
`MovementComponent` calls `world.get_astar_path()`, `world.get_tile_coords_robust()`, and `world.is_tile_occupied()` every physics frame. These must exist in `World.gd` or entities will spam errors. They are currently stubs—implement real logic when ready.

### 6. scene add_child() and script attachment
If a `.tscn` file does not reference a script via `script = ExtResource(...)`, methods defined in that script will not exist on instantiated nodes. Always verify `.tscn` files have their scripts attached.

---

## 13. Onboarding: How to Run & Extend

### Running the game (server + client on same machine)

```bash
# Terminal 1 — Start server (headless)
./tools/godot4 --headless --scene res://scenes/ui/Main.tscn -- --server

# Terminal 2 — Start client
./tools/godot4 --scene res://scenes/ui/Main.tscn
```

Or from the Godot 4 editor: press Play (F5), click Host.

### Adding a new item type

1. Create a new `.tres` in `scripts/resources/` using `ItemData.gd` as the script.
2. Set `id`, `name`, and flags (`is_stackable`, `is_container`, etc.).
3. Set `icon = null` for headless safety (or add icon after editor import).
4. In `World.gd._spawn_test_item_at_tile()` or wherever items spawn, `load()` the `.tres`, create an `ItemInstance`, assign `.data`, and call `floor_grid.add_item()` + spawn an `ItemEntity`.

### Adding a new item behaviour flag

1. Add the `@export var` field to `ItemData.gd`.
2. Use the flag in `ItemInstance.gd` methods or in game logic (e.g., `if item.data.is_poisonous: ...`).
3. Add it to any relevant `.tres` resources.

### Adding a new creature type

1. Create a new scene extending `Creature.tscn`.
2. Create a GDScript extending `Creature.gd` (or `"res://scripts/entities/Creature.gd"`).
3. Override `_ready()` to set `aggression_type`, `move_interval`, and load the texture via `visuals.load_texture_safe(path)`.
4. Register the scene in a `Spawner` node in the world, or instantiate manually in `World.gd`.

### Implementing real pathfinding (AStar2D)

Replace `World._setup_astar()` and `World.get_astar_path()` stubs:
1. In `_setup_astar()`: create an `AStar2D`, add points for each floor tile, connect neighbours.
2. In `get_astar_path(start, end)`: convert world positions to tile IDs, call `astar.get_point_path()`, convert back to world positions, return as `PackedVector2Array`.

### Implementing real tile occupancy

Replace `World.is_tile_occupied(tile_coords)` stub:
1. Iterate nodes in the `Players` and `Creatures` groups.
2. Convert each entity's `global_position` to tile coords via `get_tile_coords_robust()`.
3. Return `true` if any entity occupies `tile_coords` (excluding the caller if needed).

---

## 14. Known Issues & TODO

| # | Issue | Location | Status |
|---|---|---|---|
| 1 | `sword_normal.png` has no `.ctex` — sword spawns invisible | `assets/sword_normal.png` | Open (workaround: icon=null) |
| 2 | ContainerUI and ItemSlot have no associated `.tscn` scenes | `scripts/ui/` | Open |
| 3 | No inventory system on Player (items cannot be held yet) | `scripts/entities/Player.gd` | Open |
| 4 | Drag-and-drop in ItemSlot is a stub | `scripts/ui/ItemSlot.gd` | Open |
| 5 | `tests/test_item_system.gd` cannot be run headless without Godot binary in PATH | `tests/` | Open |

---

## 15. Change Log for Agents

| Date | Agent | Change Summary |
|---|---|---|
| 2026-02-19 | OpenCode | Created all item system scripts: ItemData.gd, ItemInstance.gd, FloorGrid.gd, ItemEntity.gd, ContainerUI.gd, ItemSlot.gd |
| 2026-02-19 | OpenCode | Created sword.tres (icon=null for headless safety) and ItemEntity.tscn |
| 2026-02-19 | OpenCode | Removed all custom type hints (`: ItemInstance`, `: ItemData`, etc.) project-wide |
| 2026-02-19 | OpenCode | Added FloorGrid + ItemInstance preloads and floor_grid init to World.gd |
| 2026-02-19 | OpenCode | Added `_spawn_item_at_tile()` to World.gd; called in `_ready()` to spawn test sword at tile (0,0) |
| 2026-02-19 | OpenCode | Verified and restored real World.gd (full AStar2D, real get_astar_path/is_tile_occupied) |
| 2026-02-19 | OpenCode | Verified all call sites: get_astar_path(3 args) in Creature.gd + Player.gd; is_tile_occupied(2 args) in MovementComponent.gd |
| 2026-02-19 | OpenCode | Created this agents.md |
| 2026-02-19 | OpenCode | Assigned CircleShape2D (radius=12) to ItemEntity.tscn CollisionShape2D |
| 2026-02-19 | OpenCode | Implemented pickup in ItemEntity._on_body_entered(): server-auth, players-group check, floor_grid.remove_item(), queue_free() |
| 2026-02-19 | OpenCode | Fixed FloorGrid.add_item() to store items by reference (removed erroneous .duplicate(true)) |
| 2026-02-19 | OpenCode | Added FloorGrid.remove_item(pos, item) by object identity |
| 2026-02-19 | OpenCode | Normalised indentation in FloorGrid.gd (was mixed tabs/spaces) |
| 2026-02-19 | OpenCode | Created tests/test_item_system.gd: 7 headless non-GUI tests for stacking, floor grid, anti-cycle |
| 2026-02-19 | OpenCode | Replaced auto-pickup-on-walk with drag-and-drop: Player._input drag start/end, World.request_move_item RPC, ItemEntity "item_entities" group registration |
| 2026-02-19 | OpenCode | Fixed diagonal adjacency: replaced `path.resize(size-1)` with `_trim_path_to_adjacent()` in Player.gd — walks backwards through path to find last waypoint Chebyshev-adjacent (≤1) to the item tile |
| 2026-02-19 | OpenCode | Fixed pathfinding rerouting: MovementComponent now stores `_destination` in `move_to()`; when next step is blocked mid-path it calls `world.get_astar_path()` for a fresh route instead of immediately abandoning |
| 2026-02-19 | OpenCode | Fixed `_trim_path_to_adjacent` off-by-one: loop now starts at `path.size()-2` to skip the item tile itself (dist=0 matched trivially before) |
| 2026-02-19 | OpenCode | Full item system requirements audit; fixed FloorGrid.add_item top-item rule (was scanning whole pile, now only checks last element); fixed ItemInstance.add_to_container to store by reference instead of duplicate(); added null-slot model and recursive slot placement to ItemInstance container logic |
| 2026-02-19 | OpenCode | Added gold_coin.tres (stackable, max_stack=99, icon_path=assets/gold_coin.png); spawned 3 coins at tiles (-2,1),(-1,1),(0,1); added QtyLabel to ItemEntity.tscn; updated ItemEntity.gd to show count badge when stack>1; rewrote World.request_move_item to merge stacks, support split_count param, and create new entity on split; added Shift+drag to Player.gd to move 1 unit from a stack |
| 2026-02-19 | OpenCode | **Refactor (SOLID/MVC/performance):** Created GridService autoload (tile math, entity registry, tile occupancy); extracted ItemMoveController child node from World.gd (move/split/merge logic); MovementComponent now caches world ref and CircleShape2D in _ready() instead of per-frame/per-call allocation; ItemEntity caches texture after first disk load; FloorGrid.move_item_between no longer uses duplicate(); ItemInstance._find_placement_slot is now pure (no side-effect mutation of contents); VisualsComponent._on_damaged uses @export entity_color instead of parent group check; Player.die() uses group lookup instead of fragile get_parent().get_parent(); Player regen guard fixed (now correctly server-gated); Creature._find_nearest_player uses 1s cached player list; Spawner creature name simplified to single randi(); dead code removed (get_tile_coords broken variant, DIAGONAL_THRESHOLD_OFFSET, TILE_SIZE onready, _exit_tree stub, DEFAULT_SPAWN_POSITION) |
