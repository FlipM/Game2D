extends CharacterBody2D

const DEFAULT_SPAWN_POSITION = Vector2(576, 324)

@onready var health = $HealthComponent
@onready var movement = $MovementComponent
@onready var combat = $CombatComponent
@onready var visuals = $VisualsComponent

@export var unit_name: String = "Player"
@export var max_hp: int = 100
@export var attack: int = 10
@export var defense: int = 10
@export var speed: float = 200.0
@export var attack_interval: float = 1.5
@export var regen_hp: float = 1.0
@export var regen_interval: float = 2.0

var regen_timer: float = 0.0

# Combat state
@export var target_enemy_path: NodePath = ""
@export var is_being_attacked: bool = false # Highlight if a monster is attacking

func _ready():
	_apply_stats()
	visuals.setup(health, combat)
	health.died.connect(die)
	
	if movement:
		movement.direction_changed.connect(visuals.update_facing)
	
	if multiplayer.is_server():
		combat.attacked.connect(_on_attacked)
		health.damaged.connect(_on_damaged)
	
	if is_multiplayer_authority():
		$Camera2D.enabled = true

func _apply_stats():
	health.max_health = max_hp
	health.current_health = max_hp
	movement.speed = speed
	combat.attack_power = attack
	combat.defense_power = defense
	combat.attack_interval = attack_interval

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
		direction += Vector2.UP
	if Input.is_action_pressed("ui_down"):
		direction += Vector2.DOWN
	if Input.is_action_pressed("ui_left"):
		direction += Vector2.LEFT
	if Input.is_action_pressed("ui_right"):
		direction += Vector2.RIGHT
		
	if direction != Vector2.ZERO:
		movement.try_move(direction.normalized())

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var world = get_tree().get_first_node_in_group("world")
			if world:
				var target_pos = get_global_mouse_position()
				var snapped_pos = (target_pos - world.center_pos).snapped(Vector2(world.TILE_SIZE, world.TILE_SIZE)) + world.center_pos
				# Pass self to exclude_entity
				var path = world.get_astar_path(global_position, snapped_pos, self)
				movement.move_to(path)

func _handle_combat_logic():
	# Resolve target
	var target = get_node_or_null(target_enemy_path)
	if target and is_instance_valid(target):
		combat.handle_combat(self, target)
	else:
		target_enemy_path = ""

func _handle_regen(delta):
	if not multiplayer.is_server() or regen_hp <= 0:
		return
	
	regen_timer += delta
	if regen_timer >= regen_interval:
		regen_timer = 0.0
		health.heal(int(regen_hp))

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
	var spawn_pos = world.center_pos if "center_pos" in world else DEFAULT_SPAWN_POSITION
	movement.teleport(spawn_pos)
	health.heal(health.max_health)

@rpc("any_peer", "call_local")
func add_to_log(text: String):
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("add_log"):
		hud.add_log(text)

func _on_attacked(target, damage):
	if not multiplayer.is_server(): return
	
	var target_name = "Creature"
	if "unit_name" in target:
		target_name = target.unit_name
	
	var peer_id = get_multiplayer_authority()
	add_to_log.rpc_id(peer_id, "You hit %s for %d damage" % [target_name, damage])

func _on_damaged(amount):
	if not multiplayer.is_server(): return
	
	if amount > 0:
		var peer_id = get_multiplayer_authority()
		add_to_log.rpc_id(peer_id, "You took %d damage!" % amount)
		spawn_damage_number.rpc(amount, Color.RED)
