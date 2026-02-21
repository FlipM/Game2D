@tool
extends Node
class_name MovementComponent

signal movement_started
signal movement_finished
signal direction_changed(direction: Vector2)

@export var speed: float = 100.0

var target_position: Vector2 = Vector2.ZERO
var is_moving: bool          = false
var parent_body: CharacterBody2D
var stuck_timer: float       = 0.0

var current_path: PackedVector2Array = []
var _destination: Vector2            = Vector2.ZERO

var _world                        = null
var _circle_shape: CircleShape2D  = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready():
	parent_body = get_parent() as CharacterBody2D
	if not parent_body:
		push_error("MovementComponent must be a child of a CharacterBody2D")
		return

	target_position = parent_body.global_position
	_world          = get_tree().get_first_node_in_group("world")

	# Single shared shape for both the occupancy probe and the collision shape.
	_circle_shape        = CircleShape2D.new()
	_circle_shape.radius = GameConstants.TILE_SIZE / 3.2  # ≈ 10 px for a 32-px tile

	var collision = parent_body.get_node_or_null("CollisionShape2D")
	if collision:
		collision.shape = _circle_shape

# ---------------------------------------------------------------------------
# Physics update — split into two focused helpers
# ---------------------------------------------------------------------------
func _physics_process(delta):
	if Engine.is_editor_hint() or not parent_body:
		return

	if parent_body.global_position.distance_to(target_position) > GameConstants.ARRIVAL_THRESHOLD:
		_tick_movement(delta)
	else:
		_snap_and_advance_path()

func _tick_movement(delta: float):
	var prev_pos = parent_body.global_position
	var dir      = (target_position - parent_body.global_position).normalized()

	var effective_speed = speed
	if abs(dir.x) > GameConstants.DIAGONAL_AXIS_THRESHOLD \
	and abs(dir.y) > GameConstants.DIAGONAL_AXIS_THRESHOLD:
		effective_speed *= GameConstants.DIAGONAL_SPEED_FACTOR

	parent_body.velocity = dir * effective_speed
	parent_body.move_and_slide()

	if not is_moving:
		is_moving = true
		movement_started.emit()
		stuck_timer = 0.0

	if parent_body.global_position.distance_to(prev_pos) < GameConstants.STUCK_MIN_DISPLACEMENT:
		stuck_timer += delta
		if stuck_timer >= GameConstants.STUCK_TIMEOUT:
			_abort_stuck()
	else:
		stuck_timer = 0.0

func _abort_stuck():
	current_path = []
	_destination = Vector2.ZERO
	# Snap to nearest tile so subsequent moves start from a clean position.
	var coords    = GridService.world_to_tile(parent_body.global_position)
	target_position = GridService.tile_to_world(coords)
	_finish_movement()

func _snap_and_advance_path():
	parent_body.velocity        = Vector2.ZERO
	parent_body.global_position = target_position

	if current_path.size() == 0:
		if is_moving:
			_finish_movement()
		return

	var next_pos = current_path[0]
	if GridService.is_tile_occupied(next_pos, parent_body):
		_try_reroute_or_stop()
	else:
		_step_to(next_pos)

func _try_reroute_or_stop():
	if _world and _destination != Vector2.ZERO:
		var new_path = _world.get_astar_path(parent_body.global_position, _destination, parent_body)
		if new_path.size() > 0:
			# Skip first waypoint if we are already on top of it.
			if parent_body.global_position.distance_to(new_path[0]) < GameConstants.ARRIVAL_THRESHOLD:
				new_path.remove_at(0)
			current_path = new_path
			if current_path.size() > 0 \
			and not GridService.is_tile_occupied(current_path[0], parent_body):
				_step_to(current_path[0])
				return

	# Reroute failed or no destination — give up.
	current_path = []
	_destination = Vector2.ZERO
	_finish_movement()

func _step_to(pos: Vector2):
	target_position = pos
	direction_changed.emit((target_position - parent_body.global_position).normalized())
	current_path.remove_at(0)

func _finish_movement():
	is_moving   = false
	stuck_timer = 0.0
	movement_finished.emit()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func try_move(direction: Vector2) -> bool:
	if is_moving or not _world:
		return false

	var current_coords = GridService.world_to_tile(parent_body.global_position)
	var target_coords  = current_coords + Vector2i(roundi(direction.x), roundi(direction.y))
	var new_target     = GridService.tile_to_world(target_coords)

	if GridService.is_tile_occupied(new_target, parent_body):
		return false
	if _is_wall(new_target):
		return false

	target_position = new_target
	direction_changed.emit(direction)
	is_moving   = true
	stuck_timer = 0.0
	movement_started.emit()
	return true

func _is_wall(world_pos: Vector2) -> bool:
	var space_state = parent_body.get_world_2d().direct_space_state
	var query       = PhysicsShapeQueryParameters2D.new()
	query.shape          = _circle_shape
	query.transform      = Transform2D(0, world_pos)
	query.collision_mask = parent_body.collision_mask
	query.exclude        = [parent_body.get_rid()]
	for result in space_state.intersect_shape(query):
		if result.collider is StaticBody2D:
			return true
	return false

func move_to(path: PackedVector2Array):
	if path.size() == 0:
		return

	current_path = path
	_destination = current_path[current_path.size() - 1]

	# Skip the first waypoint if we are already standing on it.
	if parent_body.global_position.distance_to(current_path[0]) < GameConstants.ARRIVAL_THRESHOLD:
		current_path.remove_at(0)

	if current_path.size() == 0:
		return

	var next_pos = current_path[0]
	if GridService.is_tile_occupied(next_pos, parent_body):
		current_path = []
		_destination = Vector2.ZERO
		return

	_step_to(next_pos)
	is_moving   = true
	stuck_timer = 0.0
	movement_started.emit()

func teleport(new_pos: Vector2):
	target_position             = new_pos
	parent_body.global_position = new_pos
	is_moving                   = false
	stuck_timer                 = 0.0
	current_path                = []
	_destination                = Vector2.ZERO
