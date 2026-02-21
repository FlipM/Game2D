extends Control

const _ItemSlot = preload("res://scripts/ui/ItemSlot.gd")

# The ItemInstance this UI is currently displaying (must have data.is_container == true).
@export var item_container = null
@export var slot_count: int = 5

func _ready():
    _refresh_slots()

# Assign a container ItemInstance to this UI and rebuild slot display.
func set_container(container):
    item_container = container
    slot_count = container.data.container_slots if container and container.data and container.data.container_slots > 0 else 5
    _refresh_slots()

# Rebuild child ItemSlot nodes to match the container contents.
func _refresh_slots():
    # Add missing slots
    for i in range(slot_count):
        var slot
        if i >= get_child_count():
            slot = _ItemSlot.new()
            add_child(slot)
        else:
            slot = get_child(i)
        var slot_item = item_container.contents[i] if item_container and i < item_container.contents.size() else null
        slot.set_item(slot_item)
    # Remove excess slots
    while get_child_count() > slot_count:
        get_child(get_child_count() - 1).queue_free()
