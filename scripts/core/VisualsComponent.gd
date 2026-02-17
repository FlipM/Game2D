extends Node
class_name VisualsComponent

@export var sprite: Sprite2D
@export var hp_bar: ProgressBar
@export var target_highlight: Control
@export var attacker_highlight: Control
@export var damage_number_scene: PackedScene

var is_targeted: bool = false:
	set(value):
		is_targeted = value
		if target_highlight:
			target_highlight.visible = is_targeted

func setup(health: Node, combat: Node):
	if health:
		if health.has_signal("health_changed"):
			health.health_changed.connect(_on_health_changed)
		if health.has_signal("damaged"):
			health.damaged.connect(_on_damaged)
		
		var current_hp = health.get("current_health")
		var max_hp = health.get("max_health")
		if current_hp != null and max_hp != null:
			_on_health_changed(current_hp, max_hp)
	
	if combat:
		if combat.has_signal("target_changed"):
			combat.target_changed.connect(_on_target_changed)

func _on_health_changed(current, maximum):
	if hp_bar:
		if hp_bar.has_method("update_hp"):
			hp_bar.update_hp(current, maximum)
		else:
			hp_bar.max_value = maximum
			hp_bar.value = current

func _on_damaged(amount):
	if amount > 0:
		spawn_damage_number(amount, Color.RED if get_parent().is_in_group("players") else Color.WHITE)

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
	# Assuming a reasonable label width, centering on its own position is handled by alignment
	dn.global_position = get_parent().global_position + Vector2(-100, -32) # -100 to half-offset a 200px centered label
	dn.size = Vector2(200, 20)
	
	if dn.has_method("start_animation"):
		dn.start_animation()
