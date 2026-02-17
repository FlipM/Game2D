extends ProgressBar

func _ready():
	show_percentage = false
	# Set size
	custom_minimum_size = Vector2(32, 6)
	
	# Black background with white border
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color.BLACK
	bg.set_border_width_all(1)
	bg.border_color = Color.WHITE
	add_theme_stylebox_override("background", bg)
	
func update_hp(current: int, maximum: int):
	max_value = maximum
	value = current
	show()
	
	# Color gradient from green to red
	var hp_percent = float(current) / float(maximum)
	var bar_color: Color
	
	if hp_percent > 0.5:
		# Green to yellow
		bar_color = Color.GREEN.lerp(Color.YELLOW, (1.0 - hp_percent) * 2.0)
	else:
		# Yellow to red
		bar_color = Color.YELLOW.lerp(Color.RED, 1.0 - (hp_percent * 2.0))
	
	# Update the fill color
	add_theme_stylebox_override("fill", _create_stylebox(bar_color))

func _create_stylebox(color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	return style
