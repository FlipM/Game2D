extends Node
class_name VisualsComponent

@export var sprite: Sprite2D
@export var hp_bar: ProgressBar
@export var target_highlight: Control
@export var attacker_highlight: Control
@export var damage_number_scene: PackedScene

# Directional Sprite Settings (SOLID principle: generic behavior)
@export var use_directional_sprites: bool = false
@export var base_frame: int = 0
@export var frames_per_row: int = 9 # Total columns in the sheet
@export var sprite_offset_y: float = -8.0 # Move sprite up for perspective
@export var horizontal_priority: bool = true # For diagonal movement calculation
@export var flip_h_for_left: bool = false # Some sheets only have Right and use Flip for Left

@export_group("Direction Rows")
@export var down_row: int = 0
@export var left_row: int = 1
@export var right_row: int = 2
@export var up_row: int = 3

var current_facing: Vector2 = Vector2.DOWN

func load_texture_safe(path: String):
	if not sprite: return
	
	# In some environments (headless/no editor), Godot fails to load unimported assets as resources.
	# We'll use Image load for PNGs and avoid load() entirely for them to silence the console error.
	if path.ends_with(".png"):
		if FileAccess.file_exists(path):
			var img = Image.load_from_file(ProjectSettings.globalize_path(path))
			if img:
				sprite.texture = ImageTexture.create_from_image(img)
				if use_directional_sprites:
					_apply_direction_frame()
				return
		else:
			push_error("VisualsComponent: File not found at %s" % path)
			return
	
	# Fallback to standard load for other types (non-PNG)
	var tex = load(path)
	if tex:
		sprite.texture = tex
	else:
		push_error("VisualsComponent: Failed to load resource from %s" % path)

func setup(health: Node, combat: Node):
	if sprite:
		# Perspective adjustment: move sprite up so its feet are at the origin
		# and allow it to overlap tiles above.
		sprite.offset.y = sprite_offset_y
		
	if health:
		if health.has_signal("health_changed"):
			health.health_changed.connect(_on_health_changed)
		
		var current_hp = health.get("current_health")
		var max_hp = health.get("max_health")
		if current_hp != null and max_hp != null:
			_on_health_changed(current_hp, max_hp)
	
	if combat:
		if combat.has_signal("target_changed"):
			combat.target_changed.connect(_on_target_changed)
	
	# Force initial frame calculation based on current_facing or default
	if use_directional_sprites:
		_apply_direction_frame()

func update_facing(direction: Vector2):
	if not use_directional_sprites or not sprite:
		return
		
	var facing = _get_cardinal_direction(direction)
	if facing == Vector2.ZERO:
		return
		
	current_facing = facing
	_apply_direction_frame()

func _get_cardinal_direction(dir: Vector2) -> Vector2:
	if dir == Vector2.ZERO: return Vector2.ZERO
	
	if horizontal_priority:
		if abs(dir.x) >= abs(dir.y):
			return Vector2.RIGHT if dir.x > 0 else Vector2.LEFT
		else:
			return Vector2.DOWN if dir.y > 0 else Vector2.UP
	else:
		if abs(dir.y) >= abs(dir.x):
			return Vector2.DOWN if dir.y > 0 else Vector2.UP
		else:
			return Vector2.RIGHT if dir.x > 0 else Vector2.LEFT

func _apply_direction_frame():
	if not sprite: return
	
	var row_offset = down_row
	match current_facing:
		Vector2.LEFT: row_offset = left_row
		Vector2.RIGHT: row_offset = right_row
		Vector2.UP: row_offset = up_row
		
	# Handle flip_h for left if configured
	if flip_h_for_left and current_facing == Vector2.LEFT:
		sprite.flip_h = true
		row_offset = right_row # Use right-facing row
	elif flip_h_for_left and current_facing == Vector2.RIGHT:
		sprite.flip_h = false
			
	sprite.frame = base_frame + (row_offset * frames_per_row)

var is_targeted: bool = false:
	set(value):
		is_targeted = value
		if target_highlight:
			target_highlight.visible = is_targeted

func _on_health_changed(current, maximum):
	if hp_bar:
		if hp_bar.has_method("update_hp"):
			hp_bar.update_hp(current, maximum)
		else:
			hp_bar.max_value = maximum
			hp_bar.value = current

@export var entity_color: Color = GameConstants.ENEMY_COLOR

func _on_damaged(amount):
	if amount > 0:
		spawn_damage_number(amount, entity_color)

func _on_target_changed(new_target):
	if target_highlight:
		target_highlight.visible = (new_target != null)

func update_attacker_status(is_being_attacked: bool):
	if attacker_highlight:
		attacker_highlight.visible = is_being_attacked

func spawn_damage_number(amount: int, color: Color):
	if not damage_number_scene: return
	var dn = damage_number_scene.instantiate()
	# Add to root to ensure it stays even if parent dies
	get_tree().root.add_child(dn)
	dn.set_values(amount, color)
	
	# Center it: Start at parent global pos, move up, and center horizontally
	dn.global_position = get_parent().global_position + GameConstants.DAMAGE_NUMBER_CENTER_OFFSET
	dn.size = GameConstants.DAMAGE_NUMBER_SIZE
	
	if dn.has_method("start_animation"):
		dn.start_animation()
