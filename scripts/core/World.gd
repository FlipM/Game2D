extends Node2D

const PLAYER_SCENE = preload("res://scenes/entities/Player.tscn")
const WALL_SCENE = preload("res://scenes/entities/Wall.tscn")
const FLOOR_SCENE = preload("res://scenes/entities/Floor.tscn")
const SPAWNER_SCENE = preload("res://scenes/entities/Spawner.tscn")
const RAT_SCENE = preload("res://scenes/entities/Rat.tscn")

@onready var TILE_SIZE = GameConstants.TILE_SIZE
var ARENA_RADIUS = 5
var BOUNDARY_RADIUS = 6
const DIAGONAL_THRESHOLD_OFFSET = 1.0

@onready var center_pos = GameConstants.WORLD_CENTER

class GridAStar extends AStar2D:
	func _compute_cost(from_id, to_id):
		var from_pos = get_point_position(from_id)
		var to_pos = get_point_position(to_id)
		var dist = from_pos.distance_to(to_pos)
		if dist > GameConstants.TILE_SIZE + 1.0: # Diagonal (approx 45.25)
			return 2.1 # Higher than 2.0 to prioritize straight lines
		return 1.0

	func _estimate_cost(from_id, to_id):
		var from_pos = get_point_position(from_id)
		var to_pos = get_point_position(to_id)
		return from_pos.distance_to(to_pos) / float(GameConstants.TILE_SIZE)

var astar = GridAStar.new()
var world_to_id = {}

# Robust Mapping: Using round() ensures we get the nearest tile even with floating point drifts
func get_tile_coords(pos: Vector2) -> Vector2i:
	return Vector2i((pos - center_pos) / TILE_SIZE).snapped(Vector2i.ONE)
	# Note: .snapped on Vector2i is not available in all versions, 
	# let's use a more manual robust approach:
	# var offset = pos - center_pos
	# return Vector2i(round(offset.x / TILE_SIZE), round(offset.y / TILE_SIZE))

func get_tile_coords_robust(pos: Vector2) -> Vector2i:
	var offset = pos - center_pos
	return Vector2i(round(offset.x / TILE_SIZE), round(offset.y / TILE_SIZE))

func _ready():
	add_to_group("world")
	_generate_arena()
	_setup_spawners()
	_setup_astar()
	
	# Setup custom spawn function
	$MultiplayerSpawner.spawn_function = _spawn_player
	
	# Only the server should spawn players
	if not multiplayer.is_server():
		return
	
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)
	
	# Add existing players
	if multiplayer.is_server():
		for id in multiplayer.get_peers():
			add_player(id)
		add_player(1)

func _setup_astar():
	astar.clear()
	world_to_id.clear()
	
	# Iterate boundary nodes
	for x in range(-BOUNDARY_RADIUS, BOUNDARY_RADIUS + 1):
		for y in range(-BOUNDARY_RADIUS, BOUNDARY_RADIUS + 1):
			var pos = center_pos + Vector2(x * TILE_SIZE, y * TILE_SIZE)
			var id = astar.get_available_point_id()
			
			# Check if there's a wall here
			var is_wall = false
			if abs(x) > ARENA_RADIUS or abs(y) > ARENA_RADIUS:
				is_wall = true
			
			if not is_wall:
				astar.add_point(id, pos)
				world_to_id[Vector2i(x, y)] = id
	
	# Connect points within inner arena
	for x in range(-ARENA_RADIUS, ARENA_RADIUS + 1):
		for y in range(-ARENA_RADIUS, ARENA_RADIUS + 1):
			var current_id = world_to_id.get(Vector2i(x, y), -1)
			if current_id == -1: continue
			
			# Neighbors (including diagonals)
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx == 0 and dy == 0: continue
					
					var neighbor_pos = Vector2i(x + dx, y + dy)
					var neighbor_id = world_to_id.get(neighbor_pos, -1)
					
					if neighbor_id != -1:
						astar.connect_points(current_id, neighbor_id, true)

func get_astar_path(from_pos: Vector2, to_pos: Vector2, exclude_entity: Node = null) -> PackedVector2Array:
	var start_id = astar.get_closest_point(from_pos)
	var end_id = astar.get_closest_point(to_pos)
	
	if start_id == -1 or end_id == -1:
		return PackedVector2Array()
	
	# Temporarily disable points occupied/reserved by others
	var disabled_points = []
	var entities = get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("creatures")
	var target_coords = get_tile_coords_robust(to_pos)
	
	for entity in entities:
		if not is_instance_valid(entity) or entity == exclude_entity:
			continue
		
		# Check both current position and intended target (reservation)
		var movement = entity.get_node_or_null("MovementComponent")
		if not movement: continue
		
		var current_coords = get_tile_coords_robust(entity.global_position)
		var reserved_coords = get_tile_coords_robust(movement.target_position)
		
		for coords in [current_coords, reserved_coords]:
			if coords != target_coords:
				var id = world_to_id.get(coords, -1)
				if id != -1 and id != end_id and not astar.is_point_disabled(id):
					astar.set_point_disabled(id, true)
					disabled_points.append(id)
	
	var path = astar.get_point_path(start_id, end_id)
	
	# Re-enable points
	for id in disabled_points:
		astar.set_point_disabled(id, false)
		
	return path

func is_tile_occupied(pos: Vector2, exclude_entity: Node = null) -> bool:
	var check_coords = get_tile_coords_robust(pos)
	var entities = get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("creatures")
	
	for entity in entities:
		if not is_instance_valid(entity) or entity == exclude_entity:
			continue
		
		var movement = entity.get_node_or_null("MovementComponent")
		if not movement: continue
		
		# A tile is occupied if an entity is physically there OR has reserved it (target_position)
		var entity_coords = get_tile_coords_robust(entity.global_position)
		var reserved_coords = get_tile_coords_robust(movement.target_position)
		
		if entity_coords == check_coords or reserved_coords == check_coords:
			return true
	return false

func _spawn_player(data):
	var id = data[0]
	var pos = data[1]
	print("Spawn function called for: ", id, " at ", pos)
	
	var player = PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.set_multiplayer_authority(id)
	player.position = pos
	return player

func _generate_arena():
	# Create a container for environment if not exists
	var env_node = Node2D.new()
	env_node.name = "Environment"
	add_child(env_node)
	
	# 10x10 Floor: x=[-5, 5], y=[-5, 5]
	# Walls surround it: x=[-6, 6], y=[-6, 6] logic
	
	for x in range(-6, 7):
		for y in range(-6, 7):
			var pos = center_pos + Vector2(x * TILE_SIZE, y * TILE_SIZE)
			
			if abs(x) <= 5 and abs(y) <= 5:
				# Floor
				var floor_tile = FLOOR_SCENE.instantiate()
				floor_tile.position = pos
				env_node.add_child(floor_tile)
			else:
				# Wall
				var wall = WALL_SCENE.instantiate()
				wall.position = pos
				env_node.add_child(wall)

func _setup_spawners():
	# Only server creates spawners
	if not multiplayer.is_server():
		return
	
	# Create a spawner in the top-left area of the arena
	var spawner = SPAWNER_SCENE.instantiate()
	spawner.creature_scene = RAT_SCENE
	spawner.spawn_interval = 10.0
	spawner.max_creatures = 5
	spawner.position = center_pos + Vector2(-3 * TILE_SIZE, -3 * TILE_SIZE)
	add_child(spawner)

func add_player(id):
	print("Adding player: ", id)
	# Trigger spawn via MultiplayerSpawner
	$MultiplayerSpawner.spawn([id, center_pos])

func remove_player(id):
	print("Removing player: ", id)
	var player = $Players.get_node_or_null(str(id))
	if player:
		player.queue_free()
