extends "res://scripts/entities/Creature.gd"

const DEFAULT_AGGRESSION = "Aggressive"
const DEFAULT_MOVE_INTERVAL = 0.8

func _ready():
	aggression_type = DEFAULT_AGGRESSION
	move_interval = DEFAULT_MOVE_INTERVAL
	super._ready()
	
	if visuals:
		visuals.load_texture_safe("res://assets/dog_cat_rat.png")
