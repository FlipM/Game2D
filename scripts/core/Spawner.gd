extends Node2D

@export var creature_scene: PackedScene
@export var creature_id: String = "Creature"
@export var spawn_interval: float = 10.0
@export var max_creatures: int = 5

var spawn_timer: Timer
var creature_count: int = 0

func _ready():
	# Only server spawns creatures
	if not multiplayer.is_server():
		return
	
	spawn_timer = Timer.new()
	spawn_timer.wait_time = spawn_interval
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(spawn_timer)
	spawn_timer.start()
	
	# Spawn one immediately
	_spawn_creature()

func _on_spawn_timer_timeout():
	if creature_count < max_creatures:
		_spawn_creature()

func _spawn_creature():
	if not creature_scene:
		push_error("No creature scene assigned to spawner!")
		return
	
	var creature = creature_scene.instantiate()
	# Set a unique name to avoid reserved name errors in MultiplayerSpawner
	creature.name = creature_id + "_" + str(randi())
	creature.position = global_position
	creature.tree_exited.connect(_on_creature_died)
	
	# Add to world's creatures container with force_readable_name = true
	var world = get_tree().get_first_node_in_group("world")
	if world and world.has_node("Creatures"):
		world.get_node("Creatures").add_child(creature, true)
		creature_count += 1
		print("Spawned creature: ", creature.name, " at ", global_position)

func _on_creature_died():
	creature_count -= 1
