extends Node2D

const PLAYER_SCENE = preload("res://scenes/entities/Player.tscn")
const WALL_SCENE = preload("res://scenes/entities/Wall.tscn")
const FLOOR_SCENE = preload("res://scenes/entities/Floor.tscn")
const SPAWNER_SCENE = preload("res://scenes/entities/Spawner.tscn")
const RAT_SCENE = preload("res://scenes/entities/Rat.tscn")

const TILE_SIZE = 32
# Center of 1152x648 is approx 576, 324. 
# We want 10x10 floor. 
var center_pos = Vector2(1152/2, 648/2)

func _ready():
	add_to_group("world")
	_generate_arena()
	_setup_spawners()
	
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
