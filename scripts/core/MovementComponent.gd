@tool
extends Node
class_name MovementComponent

signal movement_started
signal movement_finished
signal direction_changed(direction: Vector2)

@export var speed: float = 100.0
@export var tile_size: int = 32

var target_position: Vector2 = Vector2.ZERO
var is_moving: bool = false
var parent_body: CharacterBody2D
var stuck_timer: float = 0.0

var current_path: PackedVector2Array = []

func _exit_tree():
	pass # Occupation is now group-based and synchronized

func _ready():
	parent_body = get_parent() as CharacterBody2D
	if not parent_body:
		push_error("MovementComponent must be a child of a CharacterBody2D")
	target_position = parent_body.global_position
	
	# Programmatically change and shrink collision shape to allow squeezing
	var collision = parent_body.get_node_or_null("CollisionShape2D")
	if collision:
		var circle = CircleShape2D.new()
		circle.radius = 10.0
		collision.shape = circle

func _physics_process(_delta):
	if Engine.is_editor_hint(): return
	if not parent_body: return
	
	if parent_body.global_position.distance_to(target_position) > 2:
		var prev_pos = parent_body.global_position
		var diff = target_position - parent_body.global_position
		var dir = diff.normalized()
		
		var effective_speed = speed
		if abs(dir.x) > 0.1 and abs(dir.y) > 0.1:
			effective_speed = speed * 0.7
		
		parent_body.velocity = dir * effective_speed
		parent_body.move_and_slide()
		
		if not is_moving:
			is_moving = true
			movement_started.emit()
			stuck_timer = 0.0
		
		# Stuck detection
		if parent_body.global_position.distance_to(prev_pos) < 0.1:
			stuck_timer += _delta
			if stuck_timer > 0.8: # Balanced patience
				if current_path.size() > 0:
					current_path = []
				# Re-snap to nearest grid point robustly
				var world = get_tree().get_first_node_in_group("world")
				if world:
					var coords = world.get_tile_coords_robust(parent_body.global_position)
					target_position = world.center_pos + Vector2(coords) * world.TILE_SIZE
				_finish_movement()
		else:
			stuck_timer = 0.0
	else:
		parent_body.velocity = Vector2.ZERO
		parent_body.global_position = target_position
		
		if current_path.size() > 0:
			var next_pos = current_path[0]
			var world = get_tree().get_first_node_in_group("world")
			if world and world.is_tile_occupied(next_pos, parent_body):
				current_path = []
				_finish_movement()
			else:
				target_position = next_pos
				direction_changed.emit((target_position - parent_body.global_position).normalized())
				current_path.remove_at(0)
		elif is_moving:
			_finish_movement()

func _finish_movement():
	is_moving = false
	movement_finished.emit()
	stuck_timer = 0.0

func try_move(direction: Vector2) -> bool:
	if is_moving: return false
	
	var world = get_tree().get_first_node_in_group("world")
	if not world: return false
	
	# Robust target calculation
	var current_coords = world.get_tile_coords_robust(parent_body.global_position)
	var target_coords = current_coords + Vector2i(round(direction.x), round(direction.y))
	var new_target = world.center_pos + Vector2(target_coords) * world.TILE_SIZE
	
	# Check if target tile is occupied by other entities (now includes their target_position reservations)
	if world.is_tile_occupied(new_target, parent_body):
		return false
	
	# Static collision check (walls)
	var space_state = parent_body.get_world_2d().direct_space_state
	var shape = CircleShape2D.new()
	shape.radius = 10.0
	
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0, new_target)
	query.collision_mask = parent_body.collision_mask
	query.exclude = [parent_body.get_rid()]
	
	var results = space_state.intersect_shape(query)
	for res in results:
		if res.collider is StaticBody2D:
			return false
	
	# Reserve the target immediately
	target_position = new_target
	direction_changed.emit(direction)
	is_moving = true 
	movement_started.emit()
	stuck_timer = 0.0
	return true

func move_to(path: PackedVector2Array):
	if path.size() == 0: return
	
	current_path = path
	if current_path.size() > 0 and parent_body.global_position.distance_to(current_path[0]) < 2:
		current_path.remove_at(0)
	
	if current_path.size() > 0:
		var next_pos = current_path[0]
		var world = get_tree().get_first_node_in_group("world")
		if world and not world.is_tile_occupied(next_pos, parent_body):
			target_position = next_pos
			direction_changed.emit((target_position - parent_body.global_position).normalized())
			current_path.remove_at(0)
			is_moving = true
			movement_started.emit()
			stuck_timer = 0.0
		else:
			current_path = []

func teleport(new_pos: Vector2):
	target_position = new_pos
	parent_body.global_position = new_pos
	is_moving = false
	stuck_timer = 0.0
	current_path = []

func _force_snap_to_grid():
	var world = get_tree().get_first_node_in_group("world")
	if world:
		var coords = world.get_tile_coords_robust(parent_body.global_position)
		teleport(world.center_pos + Vector2(coords) * world.TILE_SIZE)
