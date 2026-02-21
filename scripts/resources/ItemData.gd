extends Resource

# Unique identifier for this item type
@export var id: String = ""
# Display name
@export var name: String = ""
# Weight in arbitrary units
@export var weight: float = 1.0
# Optional icon texture (assign after editor import; null is safe for headless)
@export var icon = null
# Headless-safe icon path: load via Image API instead of Godot importer.
# Set this to a res:// PNG path; it takes precedence over `icon` at runtime.
@export var icon_path: String = ""
# Item behaviour flags
@export var is_collectable: bool = false
@export var is_stackable: bool = false
@export var max_stack: int = 1
@export var is_consumable: bool = false
@export var is_usable: bool = false
@export var is_container: bool = false
# How many item slots this container offers (0 = unlimited)
@export var container_slots: int = 0

# Extendable: add more flags/fields here without touching downstream code.
