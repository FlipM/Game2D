extends CanvasLayer

@onready var hp_bar = $Control/HPBar
@onready var hp_label = $Control/HPLabel
@onready var log_label = $Control/LogLabel

func _ready():
	add_to_group("hud")
	# Update HP bar periodically
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
	var local_player = null
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player.is_multiplayer_authority():
			local_player = player
			break
			
	if local_player:
		var health_comp = local_player.get("health")
		if health_comp:
			var hp = health_comp.current_health
			var max_hp = health_comp.max_health
			hp_bar.max_value = max_hp
			hp_bar.value = hp
			hp_label.text = "HP: %d / %d" % [hp, max_hp]
