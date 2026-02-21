extends CanvasLayer

@onready var hp_bar = $Control/HPBar
@onready var hp_label = $Control/HPLabel
@onready var log_label = $Control/LogLabel

# Cached reference to the local player — resolved once and reused every tick.
var _local_player = null

func _ready():
	add_to_group("hud")
	var timer = Timer.new()
	timer.wait_time = 0.1
	timer.timeout.connect(_update_hp)
	add_child(timer)
	timer.start()

func add_log(text: String):
	log_label.text += text + "\n"
	# Keep only last 10 lines
	var lines = log_label.text.split("\n")
	if lines.size() > 10:
		log_label.text = "\n".join(lines.slice(lines.size() - 11))

func _update_hp():
	if not is_instance_valid(_local_player):
		_local_player = null
		for player in get_tree().get_nodes_in_group("players"):
			if player.is_multiplayer_authority():
				_local_player = player
				break

	if not _local_player:
		return

	var health_comp = _local_player.get("health")
	if health_comp:
		var hp = health_comp.current_health
		var max_hp = health_comp.max_health
		hp_bar.max_value = max_hp
		hp_bar.value = hp
		hp_label.text = "HP: %d / %d" % [hp, max_hp]
