extends CharacterBody2D
class_name Creature


@onready var health = $HealthComponent
@onready var movement = $MovementComponent
@onready var combat = $CombatComponent
@onready var visuals = $VisualsComponent

@export var unit_name: String = "Creature"
@export var max_hp: int = 10
@export var attack: int = 1
@export var defense: int = 0
@export var speed: float = 100.0
@export var attack_interval: float = 1.5
@export_enum("Neutral", "Aggressive", "Passive") var aggression_type: String = "Neutral"
@export var is_attacking_player: bool = false

var move_timer = 0.0
var move_interval = 1.0

func _ready():
	_apply_stats()
	visuals.setup(health, combat)
	health.died.connect(die)

func _apply_stats():
	health.max_health = max_hp
	health.current_health = max_hp
	movement.speed = speed
	combat.attack_power = attack
	combat.defense_power = defense
	combat.attack_interval = attack_interval

func _physics_process(delta):
	if multiplayer.is_server():
		_handle_ai(delta)
		_handle_combat_logic()
	
	visuals.update_attacker_status(is_attacking_player)

func _handle_ai(delta):
	move_timer += delta
	if move_timer >= move_interval and not movement.is_moving:
		_decide_movement()
		move_timer = 0.0

func _decide_movement():
	match aggression_type:
		"Aggressive":
			_move_towards_player()
		"Passive":
			_move_away_from_player()
		_:
			_move_randomly()

func _move_randomly():
	var direction = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT].pick_random()
	movement.try_move(direction)

func _move_towards_player():
	var player = _find_nearest_player()
	if player:
		var diff = player.global_position - global_position
		var direction = Vector2.ZERO
		if abs(diff.x) > abs(diff.y):
			direction = Vector2.RIGHT if diff.x > 0 else Vector2.LEFT
		else:
			direction = Vector2.DOWN if diff.y > 0 else Vector2.UP
		movement.try_move(direction)
	else:
		_move_randomly()

func _move_away_from_player():
	var player = _find_nearest_player()
	if player:
		var diff = global_position - player.global_position
		var direction = Vector2.ZERO
		if abs(diff.x) > abs(diff.y):
			direction = Vector2.RIGHT if diff.x > 0 else Vector2.LEFT
		else:
			direction = Vector2.DOWN if diff.y > 0 else Vector2.UP
		movement.try_move(direction)
	else:
		_move_randomly()

func _handle_combat_logic():
	var player = _find_nearest_player()
	if player and aggression_type == "Aggressive":
		combat.handle_combat(self, player)
		# Update visual status for attacker highlighting
		if combat.is_in_range(self, player):
			is_attacking_player = true
			player.is_being_attacked = true
		else:
			is_attacking_player = false
	else:
		is_attacking_player = false

func _find_nearest_player():
	var players = get_tree().get_nodes_in_group("players")
	return players.reduce(func(min_p, p): 
		return p if not min_p or global_position.distance_to(p.global_position) < global_position.distance_to(min_p.global_position) else min_p
	, null)

func take_damage(amount: int):
	health.take_damage(amount)

@rpc("any_peer", "call_local")
func spawn_damage_number(amount: int, color: Color):
	visuals.spawn_damage_number(amount, color)

func die():
	queue_free()
