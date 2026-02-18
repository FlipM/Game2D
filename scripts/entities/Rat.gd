extends "res://scripts/entities/Creature.gd"

func _ready():
	aggression_type = "Aggressive"
	move_interval = 0.8
	super._ready()
	
	if visuals:
		visuals.load_texture_safe("res://assets/dog_cat_rat.png")
