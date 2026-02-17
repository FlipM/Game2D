@tool
extends Node
class_name MovementComponent

signal movement_started
signal movement_finished

@export var speed: float = 100.0
@export var tile_size: int = 32

var target_position: Vector2 = Vector2.ZERO
var is_moving: bool = false
var parent_body: CharacterBody2D
var stuck_timer: float = 0.0

func _ready():
	parent_body = get_parent() as CharacterBody2D
	if not parent_body:
		push_error("MovementComponent must be a child of a CharacterBody2D")
	target_position = parent_body.global_position

func _physics_process(_delta):
	if Engine.is_editor_hint(): return
	if not parent_body: return
	
	if parent_body.global_position.distance_to(target_position) > 2:
		var prev_pos = parent_body.global_position
		parent_body.velocity = (target_position - parent_body.global_position).normalized() * speed
		parent_body.move_and_slide()
		
		if not is_moving:
			is_moving = true
			movement_started.emit()
			stuck_timer = 0.0
		
		# Stuck detection
		if parent_body.global_position.distance_to(prev_pos) < 0.1:
			stuck_timer += _delta
			if stuck_timer > 0.5:
				print("Movement stuck, resetting.")
				_force_snap_to_grid()
		else:
			stuck_timer = 0.0
	else:
		parent_body.velocity = Vector2.ZERO
		parent_body.global_position = target_position
		if is_moving:
			is_moving = false
			movement_finished.emit()
			stuck_timer = 0.0

func try_move(direction: Vector2) -> bool:
	if is_moving: return false
	
	var new_target = parent_body.global_position + direction * tile_size
	
	# Check if target tile is occupied using a small rectangle shape
	var space_state = parent_body.get_world_2d().direct_space_state
	var shape = RectangleShape2D.new()
	shape.size = Vector2(tile_size - 4, tile_size - 4) # Small margin to avoid border hits
	
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0, new_target)
	query.collision_mask = parent_body.collision_mask
	query.exclude = [parent_body.get_rid()]
	
	var results = space_state.intersect_shape(query)
	if results.size() > 0:
		return false
		
	target_position = new_target
	return true

func teleport(new_pos: Vector2):
	target_position = new_pos
	parent_body.global_position = new_pos
	is_moving = false
	stuck_timer = 0.0

func _force_snap_to_grid():
	var world = get_tree().get_first_node_in_group("world")
	var center = world.center_pos if world and "center_pos" in world else Vector2(576, 324)
	var offset = parent_body.global_position - center
	var snapped_offset = offset.snapped(Vector2(tile_size, tile_size))
	teleport(center + snapped_offset)
