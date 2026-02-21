extends Node2D

const PLAYER_SCENE     = preload("res://scenes/entities/Player.tscn")
const WALL_SCENE       = preload("res://scenes/entities/Wall.tscn")
const FLOOR_SCENE      = preload("res://scenes/entities/Floor.tscn")
const SPAWNER_SCENE    = preload("res://scenes/entities/Spawner.tscn")
const RAT_SCENE        = preload("res://scenes/entities/Rat.tscn")
const ITEM_ENTITY_SCENE = preload("res://scenes/entities/ItemEntity.tscn")

const ItemMoveController_Script = preload("res://scripts/core/ItemMoveController.gd")
const FloorGrid_Script          = preload("res://scripts/core/FloorGrid.gd")
const ItemInstance_Script       = preload("res://scripts/resources/ItemInstance.gd")

var floor_grid: Node           = null
var _item_move_controller: Node = null

# ---------------------------------------------------------------------------
# Pathfinding
# ---------------------------------------------------------------------------
# AStarGrid2D subclass with diagonal cost slightly above 2.
# Two orthogonal steps (cost 2.0) always beat one diagonal on an open path, so
# diagonals are only chosen when they avoid a detour that would cost more than 2.
class DiagonalCostGrid extends AStarGrid2D:
	func _compute_cost(from_id: Vector2i, to_id: Vector2i) -> float:
		var d = (to_id - from_id).abs()
		return GameConstants.ASTAR_DIAGONAL_COST if d.x == 1 and d.y == 1 \
		                                         else GameConstants.ASTAR_ORTHOGONAL_COST

var astar := DiagonalCostGrid.new()

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready():
	add_to_group("world")
	_generate_arena()

	floor_grid = FloorGrid_Script.new()
	add_child(floor_grid)

	_item_move_controller = ItemMoveController_Script.new()
	_item_move_controller.floor_grid = floor_grid
	add_child(_item_move_controller)

	_setup_spawners()
	_setup_astar()

	$MultiplayerSpawner.spawn_function = _spawn_player
	$ItemSpawner.spawn_function        = _spawn_item_entity
	_item_move_controller.item_spawner = $ItemSpawner

	if not multiplayer.is_server():
		return

	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)

	for id in multiplayer.get_peers():
		add_player(id)
	add_player(GameConstants.PEER_ID_SERVER)

	_spawn_item_at_tile("res://scripts/resources/sword.tres",     Vector2i(1,  0))
	_spawn_item_at_tile("res://scripts/resources/gold_coin.tres", Vector2i(-2, 1))
	_spawn_item_at_tile("res://scripts/resources/gold_coin.tres", Vector2i(-1, 1))
	_spawn_item_at_tile("res://scripts/resources/gold_coin.tres", Vector2i(0,  1))

# ---------------------------------------------------------------------------
# Arena generation
# ---------------------------------------------------------------------------
func _generate_arena():
	var env_node    = Node2D.new()
	env_node.name   = "Environment"
	add_child(env_node)

	var ts     = GameConstants.TILE_SIZE
	var center = GameConstants.WORLD_CENTER
	var arena  = GameConstants.ARENA_RADIUS
	var bound  = GameConstants.BOUNDARY_RADIUS

	for x in range(-bound, bound + 1):
		for y in range(-bound, bound + 1):
			var pos  = center + Vector2(x * ts, y * ts)
			var tile = FLOOR_SCENE if (abs(x) <= arena and abs(y) <= arena) else WALL_SCENE
			var node = tile.instantiate()
			node.position = pos
			env_node.add_child(node)

# ---------------------------------------------------------------------------
# Spawners
# ---------------------------------------------------------------------------
func _setup_spawners():
	if not multiplayer.is_server():
		return
	var spawner             = SPAWNER_SCENE.instantiate()
	spawner.creature_scene  = RAT_SCENE
	spawner.spawn_interval  = 10.0
	spawner.max_creatures   = 5
	spawner.position = GameConstants.WORLD_CENTER \
	                 + Vector2(-3 * GameConstants.TILE_SIZE, -3 * GameConstants.TILE_SIZE)
	add_child(spawner)

func add_player(id: int):
	print("Adding player: ", id)
	$MultiplayerSpawner.spawn([id, GameConstants.WORLD_CENTER])

func remove_player(id: int):
	print("Removing player: ", id)
	var player = $Players.get_node_or_null(str(id))
	if player:
		player.queue_free()

func _spawn_player(data: Array) -> Node:
	var id  = data[0]
	var pos = data[1]
	var player = PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.set_multiplayer_authority(id)
	player.position = pos
	return player

# ---------------------------------------------------------------------------
# Item spawning
# ---------------------------------------------------------------------------
func _spawn_item_entity(data: Array) -> Node:
	# Only set position here — item data is pushed separately via sync_to_clients
	# RPC to avoid the Resource arriving as EncodedObjectAsID on clients.
	var entity    = ITEM_ENTITY_SCENE.instantiate()
	entity.position = data[1]
	return entity

func _spawn_item_at_tile(item_data_path: String, tile_coords: Vector2i):
	var item_data = load(item_data_path)
	if not item_data:
		push_error("World: Failed to load item data: " + item_data_path)
		return
	var inst  = ItemInstance_Script.new()
	inst.data  = item_data
	inst.count = 1
	floor_grid.add_item(tile_coords, inst)

	var pos    = GridService.tile_to_world(tile_coords)
	var entity = $ItemSpawner.spawn([inst, pos])
	# Set item AFTER spawn() returns — setting it inside spawn_function would
	# include it in the spawn snapshot and cause EncodedObjectAsID on clients.
	entity.set_item(inst)
	entity.sync_to_clients.rpc(pos, item_data_path, inst.count)
	print("Spawned item '%s' at tile %s" % [item_data.name, tile_coords])

# ---------------------------------------------------------------------------
# Item interaction RPC (server-authoritative)
# ---------------------------------------------------------------------------
@rpc("any_peer", "call_local")
func request_move_item(entity_path: NodePath, drop_tile: Vector2i,
                       requester_id: int, split_count: int = 0):
	if not multiplayer.is_server():
		return

	var entity = get_node_or_null(entity_path)
	if not entity or not entity.has_method("set_item"):
		push_warning("World.request_move_item: invalid entity path %s" % entity_path)
		return
	if entity.item == null:
		return

	# Proximity check — requester must be adjacent to the item.
	var player_node = _find_player_by_id(requester_id)
	if player_node == null:
		return
	var item_tile   = GridService.world_to_tile(entity.global_position)
	var player_tile = GridService.world_to_tile(player_node.global_position)
	var dist = (item_tile - player_tile).abs()
	if dist.x > 1 or dist.y > 1:
		push_warning("World.request_move_item: player too far from item")
		return

	if not astar.is_in_boundsv(drop_tile):
		push_warning("World.request_move_item: drop tile %s is outside arena" % drop_tile)
		return
	if drop_tile == item_tile:
		return

	var moving = entity.item.count if split_count <= 0 \
	                               else mini(split_count, entity.item.count)
	_item_move_controller.execute(entity, item_tile, drop_tile, moving)

func _find_player_by_id(peer_id: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and p.get_multiplayer_authority() == peer_id:
			return p
	return null

# ---------------------------------------------------------------------------
# Pathfinding
# ---------------------------------------------------------------------------
func _setup_astar():
	var size = GameConstants.ARENA_RADIUS * 2 + 1
	astar.region    = Rect2i(-GameConstants.ARENA_RADIUS, -GameConstants.ARENA_RADIUS, size, size)
	astar.cell_size = Vector2(GameConstants.TILE_SIZE, GameConstants.TILE_SIZE)
	astar.offset    = GameConstants.WORLD_CENTER
	# DIAGONAL_MODE_ALWAYS: the cost model decides when diagonals are worthwhile.
	astar.diagonal_mode            = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	# Manhattan heuristic is admissible when diagonal cost > 2.
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()

func get_astar_path(from_pos: Vector2, to_pos: Vector2,
                    exclude_entity: Node = null) -> PackedVector2Array:
	var from_cell = GridService.world_to_tile(from_pos)
	var to_cell   = GridService.world_to_tile(to_pos)

	# Temporarily mark occupied tiles solid so the path avoids them.
	# Use a Dictionary as a set to avoid marking the same cell twice.
	var blocked: Dictionary = {}
	for group in ["players", "creatures"]:
		for entity in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(entity) or entity == exclude_entity:
				continue
			var movement = entity.get_node_or_null("MovementComponent")
			if not movement:
				continue
			for cell in [GridService.world_to_tile(entity.global_position),
			             GridService.world_to_tile(movement.target_position)]:
				if cell != to_cell and astar.is_in_boundsv(cell) and not blocked.has(cell):
					astar.set_point_solid(cell, true)
					blocked[cell] = true

	var path = astar.get_point_path(from_cell, to_cell)

	for cell in blocked:
		astar.set_point_solid(cell, false)

	return path

# Mark a tile permanently solid or walkable (doors, placed objects, etc.).
func set_tile_solid(tile: Vector2i, solid: bool) -> void:
	if astar.is_in_boundsv(tile):
		astar.set_point_solid(tile, solid)
