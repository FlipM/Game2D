extends CharacterBody2D

@onready var health = $HealthComponent
@onready var movement = $MovementComponent
@onready var combat = $CombatComponent
@onready var visuals = $VisualsComponent

@export var stats: Resource

# Combat state
@export var target_enemy_path: NodePath = ""
@export var is_being_attacked: bool = false # Highlight if a monster is attacking

func _ready():
	if stats:
		_apply_stats()
	visuals.setup(health, combat)
	health.died.connect(die)
	
	if is_multiplayer_authority():
		combat.attacked.connect(_on_attacked)
		health.damaged.connect(_on_damaged)

func _apply_stats():
	health.max_health = stats.max_hp
	health.current_health = stats.max_hp
	movement.speed = stats.speed
	combat.attack_power = stats.attack
	combat.defense_power = stats.defense
	combat.attack_interval = stats.attack_interval

func _physics_process(delta):
	if is_multiplayer_authority():
		_handle_input()
		_handle_regen(delta)
	
	if multiplayer.is_server():
		_handle_combat_logic()
	
	visuals.update_attacker_status(is_being_attacked)

func _handle_input():
	if movement.is_moving:
		return
		
	var direction = Vector2.ZERO
	if Input.is_action_pressed("ui_up"):
		direction = Vector2.UP
	elif Input.is_action_pressed("ui_down"):
		direction = Vector2.DOWN
	elif Input.is_action_pressed("ui_left"):
		direction = Vector2.LEFT
	elif Input.is_action_pressed("ui_right"):
		direction = Vector2.RIGHT
		
	if direction != Vector2.ZERO:
		movement.try_move(direction)

func _handle_combat_logic():
	# Resolve target
	var target = get_node_or_null(target_enemy_path)
	if target and is_instance_valid(target):
		combat.handle_combat(self, target)
	else:
		target_enemy_path = ""

func _handle_regen(delta):
	if not multiplayer.is_server() or stats.regen_hp <= 0:
		return
	
	# Simple regen logic (could be moved to a RegenComponent)
	# For now keeping it simple
	health.heal(int(stats.regen_hp * delta))

func set_target(enemy):
	if enemy:
		target_enemy_path = get_path_to(enemy)
	else:
		target_enemy_path = ""

func take_damage(amount: int):
	health.take_damage(amount)

@rpc("any_peer", "call_local")
func spawn_damage_number(amount: int, color: Color):
	visuals.spawn_damage_number(amount, color)

func die():
	print("Player died!")
	# Respawn logic
	var world = get_parent().get_parent()
	var spawn_pos = world.center_pos if "center_pos" in world else Vector2(576, 324)
	movement.teleport(spawn_pos)
	health.heal(health.max_health)

@rpc("any_peer", "call_local")
func add_to_log(text: String):
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("add_log"):
		hud.add_log(text)

func _on_attacked(target, damage):
	var target_name = "Creature"
	var target_stats = target.get("stats")
	if target_stats and "unit_name" in target_stats:
		target_name = target_stats.unit_name
	add_to_log.rpc("You hit %s for %d damage" % [target_name, damage])

func _on_damaged(amount):
	if amount > 0:
		add_to_log.rpc("You took %d damage!" % amount)
