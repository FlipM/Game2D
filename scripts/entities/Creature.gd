extends CharacterBody2D
class_name Creature

@onready var health  = $HealthComponent
@onready var movement = $MovementComponent
@onready var combat  = $CombatComponent
@onready var visuals = $VisualsComponent

@export var unit_name: String = "Creature"
@export var max_hp: int       = 10
@export var attack: int       = 1
@export var defense: int      = 0
@export var speed: float      = 100.0
@export var attack_interval: float = 1.5
@export_enum("Neutral", "Aggressive", "Passive") var aggression_type: String = "Neutral"
# Peer ID of the player being targeted (0 = no target). Replicated so every
# client can check whether the creature is targeting *them* specifically.
@export var target_peer_id: int = 0

var move_timer: float    = 0.0
var move_interval: float = 0.5

# Cache the player list and the world node; refresh players at most once per second.
const PLAYER_CACHE_INTERVAL: float = 1.0
var _cached_players: Array         = []
var _player_cache_timer: float     = 0.0
var _world: Node                   = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready():
	_world = get_tree().get_first_node_in_group("world")
	_apply_stats()
	visuals.setup(health, combat)
	health.died.connect(die)
	if movement:
		movement.direction_changed.connect(visuals.update_facing)

func _apply_stats():
	health.max_health      = max_hp
	health.current_health  = max_hp
	movement.speed         = speed
	combat.attack_power    = attack
	combat.defense_power   = defense
	combat.attack_interval = attack_interval

# ---------------------------------------------------------------------------
# Per-frame update (server only for AI/combat; all peers for visuals)
# ---------------------------------------------------------------------------
func _physics_process(delta):
	if multiplayer.is_server():
		_player_cache_timer += delta
		if _player_cache_timer >= PLAYER_CACHE_INTERVAL:
			_player_cache_timer = 0.0
			_cached_players     = get_tree().get_nodes_in_group("players")
		_handle_ai(delta)
		_handle_combat_logic()

	# Only the targeted player sees the attacker highlight on this creature.
	var i_am_targeted = target_peer_id != 0 and target_peer_id == multiplayer.get_unique_id()
	visuals.update_attacker_status(i_am_targeted)

# ---------------------------------------------------------------------------
# AI
# ---------------------------------------------------------------------------
func _handle_ai(delta: float):
	move_timer += delta
	if move_timer >= move_interval and not movement.is_moving:
		_decide_movement()
		move_timer = 0.0

func _decide_movement():
	var player = _find_nearest_player()
	if player and combat.is_in_range(self, player):
		return  # Already in melee range — stay put and let combat handle it.

	match aggression_type:
		"Aggressive": _move_towards_player()
		"Passive":    _move_away_from_player()
		_:            _move_randomly()

func _move_randomly():
	var direction = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT].pick_random()
	movement.try_move(direction)

func _move_towards_player():
	var player = _find_nearest_player()
	if player == null:
		_move_randomly()
		return
	if _world == null:
		return
	var path = _world.get_astar_path(global_position, player.global_position, self)
	if path.size() > 1:
		movement.try_move((path[1] - global_position).normalized())

func _move_away_from_player():
	var player = _find_nearest_player()
	if player == null:
		_move_randomly()
		return
	var diff      = global_position - player.global_position
	var direction = Vector2.RIGHT if diff.x > 0 else Vector2.LEFT
	if abs(diff.y) > abs(diff.x):
		direction = Vector2.DOWN if diff.y > 0 else Vector2.UP
	movement.try_move(direction)

# ---------------------------------------------------------------------------
# Combat
# ---------------------------------------------------------------------------
func _handle_combat_logic():
	var player = _find_nearest_player()
	if player and aggression_type == "Aggressive":
		combat.handle_combat(self, player)
		# Set target_peer_id as soon as we have a target — regardless of melee range.
		# Clients use this to show the attacker highlight only to the targeted player.
		target_peer_id = player.get_multiplayer_authority()
	else:
		target_peer_id = 0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _find_nearest_player() -> Node:
	if _cached_players.is_empty():
		_cached_players = get_tree().get_nodes_in_group("players")

	var nearest: Node  = null
	var best_dist: float = INF
	for p in _cached_players:
		if not is_instance_valid(p):
			continue
		var d = global_position.distance_to(p.global_position)
		if d < best_dist:
			best_dist = d
			nearest   = p
	return nearest

func take_damage(amount: int):
	health.take_damage(amount)
	if multiplayer.is_server() and amount > 0:
		spawn_damage_number.rpc(amount, Color.WHITE)

@rpc("any_peer", "call_local")
func spawn_damage_number(amount: int, color: Color):
	visuals.spawn_damage_number(amount, color)

func die():
	queue_free()
