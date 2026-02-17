extends Node
class_name HealthComponent

signal health_changed(current: int, maximum: int)
signal damaged(amount: int)
signal healed(amount: int)
signal died

@export var max_health: int = 10:
	set(value):
		var old_max = max_health
		max_health = value
		if current_health == old_max or current_health > max_health:
			current_health = max_health
		health_changed.emit(current_health, max_health)
var current_health: int = 10:
	set(value):
		current_health = clamp(value, 0, max_health)
		health_changed.emit(current_health, max_health)
		if current_health <= 0:
			died.emit()

func _ready():
	current_health = max_health
	health_changed.emit(current_health, max_health)

func take_damage(amount: int):
	current_health -= amount
	damaged.emit(amount)

func heal(amount: int):
	current_health += amount
	healed.emit(amount)

func is_alive() -> bool:
	return current_health > 0
