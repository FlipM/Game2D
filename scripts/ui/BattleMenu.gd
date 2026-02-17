extends Panel

var dragging = false
var drag_offset = Vector2.ZERO

@onready var creature_list = $MarginContainer/VBoxContainer/ScrollContainer/CreatureList
@onready var title_bar = $TitleBar

func _ready():
	title_bar.gui_input.connect(_on_title_bar_input)
	# Update creature list periodically
	var timer = Timer.new()
	timer.wait_time = 0.5
	timer.timeout.connect(_update_creature_list)
	add_child(timer)
	timer.start()

func _on_title_bar_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				drag_offset = get_global_mouse_position() - global_position
			else:
				dragging = false
	
	if event is InputEventMouseMotion and dragging:
		var new_pos = get_global_mouse_position() - drag_offset
		# Clamp to screen bounds
		var screen_size = get_viewport_rect().size
		new_pos.x = clamp(new_pos.x, 0, screen_size.x - size.x)
		new_pos.y = clamp(new_pos.y, 0, screen_size.y - size.y)
		global_position = new_pos

func _update_creature_list():
	# Clear existing buttons
	for child in creature_list.get_children():
		child.queue_free()
	
	# Get local player
	var player = null
	var players = get_tree().get_nodes_in_group("players")
	for p in players:
		if p.is_multiplayer_authority():
			player = p
			break
	
	var creatures = get_tree().get_nodes_in_group("creatures")
	for creature in creatures:
		if not is_instance_valid(creature):
			continue
			
		var stats_ref = creature.get("stats")
		var health_ref = creature.get("health")
		var visuals_ref = creature.get("visuals")
		
		var c_name = stats_ref.unit_name if stats_ref else "Creature"
		var c_hp = health_ref.current_health if health_ref else 0
		var c_max = health_ref.max_health if health_ref else 1
		
		var button = Button.new()
		button.text = "%s (HP: %d/%d)" % [c_name, c_hp, c_max]
		
		# Highlight if targeted
		var player_target_path = player.get("target_enemy_path") if player else null
		if (player and player_target_path is NodePath and not player_target_path.is_empty() 
			and player.get_node_or_null(player_target_path) == creature):
			button.modulate = Color.RED
			if visuals_ref: visuals_ref.set("is_targeted", true)
		else:
			if visuals_ref: visuals_ref.set("is_targeted", false)
			
		button.pressed.connect(_on_creature_selected.bind(creature, button))
		creature_list.add_child(button)

func _on_creature_selected(creature, button):
	var player = null
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_multiplayer_authority():
			player = p
			break
			
	if player and player.has_method("set_target"):
		var player_target_path = player.get("target_enemy_path")
		var current_target = null
		if player_target_path is NodePath and not player_target_path.is_empty():
			current_target = player.get_node_or_null(player_target_path)
			
		if current_target == creature:
			# Stop attacking
			player.set_target(null)
			button.modulate = Color.WHITE
		else:
			# Start attacking
			player.set_target(creature)
			# Reset all button colors
			for btn in creature_list.get_children():
				btn.modulate = Color.WHITE
			button.modulate = Color.RED
