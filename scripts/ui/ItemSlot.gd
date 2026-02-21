extends Control

# The ItemInstance currently occupying this slot (null = empty).
@export var item = null

@onready var icon: TextureRect = $Icon if has_node("Icon") else null
@onready var qty_label: Label = $QtyLabel if has_node("QtyLabel") else null

# Assign an ItemInstance (or null to clear) and refresh visuals.
func set_item(new_item):
    item = new_item
    _update_visual()

# Clear this slot.
func clear_item():
    item = null
    _update_visual()

func _update_visual():
    if icon:
        icon.texture = item.data.icon if item and item.data and item.data.icon else null
    if qty_label:
        qty_label.text = str(item.count) if item and item.data and item.data.is_stackable and item.count > 1 else ""

func _gui_input(event):
    # Placeholder: implement drag-and-drop here.
    # On left-click press: start drag with item data.
    # On left-click release over another slot: call target_slot.set_item(item) and clear self.
    pass
