extends CharacterBody2D

@onready var health = $HealthComponent
@onready var movement = $MovementComponent
@onready var combat = $CombatComponent
@onready var visuals = $VisualsComponent

@export var unit_name: String = "Player"
@export var max_hp: int = 100
@export var attack: int = 10
@export var defense: int = 10
@export var speed: float = 200.0
@export var attack_interval: float = 1.5
@export var regen_hp: float = 1.0
@export var regen_interval: float = 2.0

var regen_timer: float = 0.0

# Combat state
@export var target_enemy_path: NodePath = ""

# Item drag state (local authority only)
# Set on mouse-press; evaluated on mouse-release.
var _press_tile: Vector2i = Vector2i.ZERO # tile where mouse was pressed
var _press_world: Vector2 = Vector2.ZERO # world-snapped pos of press
var _pending_item_entity = null # ItemEntity to move once adjacent
var _pending_drop_tile: Vector2i = Vector2i.ZERO # where to drop it
var _pending_split: bool = false # true when Shift was held on press (move 1 only)

# Cached scene-tree references — set in _ready, valid for the node's lifetime.
var _world = null

func _ready():
	_world = get_tree().get_first_node_in_group("world")
	_apply_stats()
	visuals.entity_color = GameConstants.PLAYER_COLOR
	visuals.setup(health, combat)
	health.died.connect(die)
	
	if movement:
		movement.direction_changed.connect(visuals.update_facing)
	
	if multiplayer.is_server():
		combat.attacked.connect(_on_attacked)
		health.damaged.connect(_on_damaged)
	
	if is_multiplayer_authority():
		$Camera2D.enabled = true
		movement.movement_finished.connect(_on_movement_finished)

func _apply_stats():
	health.max_health = max_hp
	health.current_health = max_hp
	movement.speed = speed
	combat.attack_power = attack
	combat.defense_power = defense
	combat.attack_interval = attack_interval

func _physics_process(delta):
	if is_multiplayer_authority():
		_handle_input()
		_handle_regen(delta)
	
	if multiplayer.is_server():
		_handle_combat_logic()


func _handle_input():
	if movement.is_moving:
		return
		
	var direction = Vector2.ZERO
	if Input.is_action_pressed("ui_up"):
		direction += Vector2.UP
	if Input.is_action_pressed("ui_down"):
		direction += Vector2.DOWN
	if Input.is_action_pressed("ui_left"):
		direction += Vector2.LEFT
	if Input.is_action_pressed("ui_right"):
		direction += Vector2.RIGHT
		
	if direction != Vector2.ZERO:
		movement.try_move(direction.normalized())

func _input(event):
	if not is_multiplayer_authority():
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return

	if not _world:
		return

	var snapped = _snapped_tile_world(get_global_mouse_position())

	if event.pressed:
		# Record press tile and whether Shift is held; wait for release to decide action.
		_cancel_pending_item()
		_press_tile = GridService.world_to_tile(snapped)
		_press_world = snapped
		_pending_split = Input.is_key_pressed(KEY_SHIFT)
	else:
		# --- Mouse released ---
		var release_tile = GridService.world_to_tile(snapped)

		if release_tile == _press_tile:
			# Same tile press+release: walk there regardless of whether there's an item.
			var path = _world.get_astar_path(global_position, _press_world, self)
			movement.move_to(path)
		else:
			# Different tile: only act if there is an item at the press tile.
			var entity = _find_item_entity_at(_press_world)
			if entity == null:
				return # No item — ignore the drag entirely.

			var player_tile = GridService.world_to_tile(global_position)
			var dist = (_press_tile - player_tile).abs()
			if dist.x <= 1 and dist.y <= 1:
				# Already adjacent — move the item immediately.
				_send_move_item(_world, entity, release_tile, _pending_split)
			else:
				# Too far — walk adjacent to the item, then move it on arrival.
				_pending_item_entity = entity
				_pending_drop_tile = release_tile
				# _pending_split already set on press; preserved for deferred move

				# If already moving, don't interrupt — _on_movement_finished will
				# reroute to the new target once the current step completes.
				if movement.is_moving:
					return

				var path = _world.get_astar_path(global_position, _press_world, self)
				path = _trim_path_to_adjacent(_press_tile, path)
				if path.size() > 0:
					movement.move_to(path)
				else:
					# Already adjacent after trim (edge case) — move immediately.
					_send_move_item(_world, entity, release_tile, _pending_split)
					_cancel_pending_item()

# Called each time this player finishes a movement step.
func _on_movement_finished():
	if _pending_item_entity == null or not is_instance_valid(_pending_item_entity):
		_cancel_pending_item()
		return

	if not _world:
		_cancel_pending_item()
		return

	var item_tile = GridService.world_to_tile(_pending_item_entity.global_position)
	var player_tile = GridService.world_to_tile(global_position)
	var dist = (item_tile - player_tile).abs()
	if dist.x <= 1 and dist.y <= 1:
		# Now adjacent — execute the deferred item move.
		_send_move_item(_world, _pending_item_entity, _pending_drop_tile, _pending_split)
		_cancel_pending_item()
	else:
		# Path exhausted but not yet adjacent (e.g. trim landed short, or obstacle).
		# Reroute: walk as close as possible to the item and retry on next arrival.
		var item_world = _pending_item_entity.global_position
		var path = _world.get_astar_path(global_position, item_world, self)
		path = _trim_path_to_adjacent(item_tile, path)
		if path.size() > 0:
			movement.move_to(path)
		else:
			# Truly unreachable — give up.
			_cancel_pending_item()

func _send_move_item(world, entity, drop_tile: Vector2i, split: bool = false):
	# split_count: 1 when Shift is held and item is stackable (split off one unit), 0 = move all.
	var split_count = 0
	if split and entity.item != null and entity.item.data != null and entity.item.data.is_stackable:
		split_count = 1
	world.request_move_item.rpc_id(1,
		entity.get_path(),
		drop_tile,
		get_multiplayer_authority(),
		split_count)

func _cancel_pending_item():
	_pending_item_entity = null
	_pending_drop_tile = Vector2i.ZERO
	_pending_split = false

# Trim `path` so the player stops at the last waypoint that is Chebyshev-adjacent
# (dist ≤ 1 in both axes) to `item_tile`.  Falls back to removing the last step if
# no adjacent waypoint is found (same safety net as before).
func _trim_path_to_adjacent(item_tile: Vector2i, path: PackedVector2Array) -> PackedVector2Array:
	if path.size() <= 1:
		return path
	# Walk backwards starting from the second-to-last waypoint.
	# The last waypoint IS the item tile (distance 0), so we skip it and look
	# for the furthest-along waypoint that is still Chebyshev-adjacent (≤ 1).
	for i in range(path.size() - 2, -1, -1):
		var waypoint_tile = GridService.world_to_tile(path[i])
		var d = (item_tile - waypoint_tile).abs()
		if d.x <= 1 and d.y <= 1:
			# Keep path up to and including this waypoint.
			path.resize(i + 1)
			return path
	# Fallback: just drop the last step.
	path.resize(path.size() - 1)
	return path

# Return snapped world position aligned to the tile grid.
func _snapped_tile_world(mouse_pos: Vector2) -> Vector2:
	var ts = GameConstants.TILE_SIZE
	return (mouse_pos - GameConstants.WORLD_CENTER).snapped(Vector2(ts, ts)) + GameConstants.WORLD_CENTER

# Return the ItemEntity whose centre is within half a tile of `world_pos`, or null.
# Uses the GridService entity registry (O(1)) instead of a full group scan.
func _find_item_entity_at(world_pos: Vector2):
	var tile = GridService.world_to_tile(world_pos)
	return GridService.get_item_entity_at(tile)

func _handle_combat_logic():
	# Resolve target
	var target = get_node_or_null(target_enemy_path)
	if target and is_instance_valid(target):
		combat.handle_combat(self, target)
	else:
		target_enemy_path = ""

func _handle_regen(delta):
	# Regen runs on the server (authoritative) for the local authority process call.
	# _physics_process already gates this call behind is_multiplayer_authority(),
	# and on the server the host player IS its own authority, so this guard is correct.
	if not multiplayer.is_server():
		return
	if regen_hp <= 0:
		return
	regen_timer += delta
	if regen_timer >= regen_interval:
		regen_timer = 0.0
		health.heal(int(regen_hp))

func set_target(enemy):
	if enemy:
		target_enemy_path = get_path_to(enemy)
	else:
		target_enemy_path = ""

func take_damage(amount: int):
	health.take_damage(amount)

@rpc("any_peer", "call_local")
func spawn_damage_number(amount: int, color: Color):
	visuals.spawn_damage_number(amount, color)

func die():
	print("Player died!")
	movement.teleport(GameConstants.WORLD_CENTER)
	health.heal(health.max_health)

@rpc("any_peer", "call_local")
func add_to_log(text: String):
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("add_log"):
		hud.add_log(text)

func _on_attacked(target, damage):
	if not multiplayer.is_server(): return
	
	var target_name = "Creature"
	if "unit_name" in target:
		target_name = target.unit_name
	
	var peer_id = get_multiplayer_authority()
	add_to_log.rpc_id(peer_id, "You hit %s for %d damage" % [target_name, damage])

func _on_damaged(amount):
	if not multiplayer.is_server(): return
	
	if amount > 0:
		var peer_id = get_multiplayer_authority()
		add_to_log.rpc_id(peer_id, "You took %d damage!" % amount)
		spawn_damage_number.rpc(amount, Color.RED)
