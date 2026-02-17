extends Label

func _ready():
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func start_animation():
	# Animation logic
	var tween = create_tween()
	tween.set_parallel(true)
	# Rise up by 60 pixels for better visibility
	tween.tween_property(self, "position:y", position.y - 60, 1.5)
	# Fade out
	tween.tween_property(self, "modulate:a", 0.0, 1.5)
	# Delete when finished
	tween.set_parallel(false)
	tween.tween_callback(queue_free)

func set_values(amount: int, color: Color = Color.WHITE):
	text = str(amount)
	modulate = color
