extends Node
class_name CombatComponent

signal target_changed(new_target: Node)
signal attacked(target: Node, damage: int)
signal hit_received(amount: int)

@export var attack_power: int = 1
@export var defense_power: int = 0
@export var attack_interval: float = 1.5
@export var melee_range_multiplier: float = 1.6

var attack_timer: float = 0.0
var current_target: Node = null:
	set(value):
		if current_target != value:
			current_target = value
			target_changed.emit(current_target)

func _physics_process(delta):
	if multiplayer.is_server():
		attack_timer += delta

func handle_combat(attacker: Node, target: Node):
	if not multiplayer.is_server(): return
	if attack_timer < attack_interval: return
	
	if target and is_instance_valid(target) and is_in_range(attacker, target):
		perform_attack(target)
		attack_timer = 0.0

func perform_attack(target: Node):
	if target.has_method("take_damage"):
		var target_defense = 0
		var target_combat = target.get("combat")
		if target_combat and "defense_power" in target_combat:
			target_defense = target_combat.defense_power
			
		var damage = max(0, randi_range(0, attack_power) - target_defense)
		target.take_damage(damage)
		attacked.emit(target, damage)

func is_in_range(attacker: Node, target: Node) -> bool:
	var dist = attacker.global_position.distance_to(target.global_position)
	return dist <= 32 * melee_range_multiplier
