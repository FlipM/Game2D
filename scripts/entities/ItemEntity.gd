extends Area2D
class_name ItemEntity

const ItemInstance = preload("res://scripts/resources/ItemInstance.gd")

# Holds the live ItemInstance this entity represents on the floor.
# Not @export — must not be replicated by MultiplayerSynchronizer (Resource
# objects would arrive as EncodedObjectAsID). State is pushed via sync_to_clients RPC.
var item = null

@onready var sprite: Sprite2D = $Sprite2D if has_node("Sprite2D") else null
@onready var qty_label: Label = $QtyLabel if has_node("QtyLabel") else null

# Cached texture — loaded once from disk, reused on subsequent update_visual() calls.
var _cached_texture: ImageTexture = null
var _cached_icon_path: String = ""

func _ready():
	add_to_group("item_entities")
	# On the server the position is already correct at _ready time (set by
	# _spawn_item_entity before add_child returns), so register immediately.
	# On clients the position is still Vector2.ZERO until sync_to_clients fires,
	# so defer registration to sync_to_clients to avoid mapping every item to
	# tile (0,0) and corrupting the GridService registry.
	if multiplayer.is_server():
		GridService.register_item_entity(self)
	update_visual()
	# On clients, item is null until the server sends sync_to_clients. For nodes
	# spawned before this peer connected (late-join), the initial RPC was already
	# sent and missed. Request a fresh sync from the server.
	if not multiplayer.is_server():
		request_sync.rpc_id(1)

func _exit_tree():
	GridService.unregister_item_entity(self)

# Update sprite and quantity label.
# Priority: item.data.icon_path (loaded via Image API) > item.data.icon (editor-imported Texture2D).
# Call this any time the item's count or data changes.
func update_visual():
	_update_sprite()
	_update_qty_label()

func _update_sprite():
	if sprite == null:
		return
	if item == null or item.data == null:
		sprite.texture = null
		return

	# Prefer icon_path: works headless without .ctex
	var path = item.data.get("icon_path") if item.data.get("icon_path") != null else ""
	if path != "":
		# Only reload from disk if the path changed.
		if path != _cached_icon_path or _cached_texture == null:
			var global_path = ProjectSettings.globalize_path(path)
			if FileAccess.file_exists(global_path):
				var img = Image.load_from_file(global_path)
				if img:
					_cached_texture = ImageTexture.create_from_image(img)
					_cached_icon_path = path
				else:
					_cached_texture = null
					_cached_icon_path = ""
			else:
				push_warning("ItemEntity: icon_path '%s' not found, falling back." % path)
				_cached_texture = null
				_cached_icon_path = ""
		if _cached_texture != null:
			sprite.texture = _cached_texture
			return

	# Fallback: editor-imported Texture2D (requires .ctex)
	if item.data.icon:
		sprite.texture = item.data.icon
	else:
		sprite.texture = null

func _update_qty_label():
	if qty_label == null:
		return
	if item == null or item.data == null or not item.data.is_stackable or item.count <= 1:
		qty_label.visible = false
		qty_label.text = ""
		return
	qty_label.text = str(item.count)
	qty_label.visible = true

# Assign an ItemInstance to this entity and refresh its visual.
func set_item(new_item):
	item = new_item
	# Invalidate cache when item data changes.
	_cached_texture = null
	_cached_icon_path = ""
	update_visual()

# Called by the server on all peers after any item mutation (merge, move, split).
# Sends position, item data path, and count — the spawner replicates the bare node
# but cannot transfer the ItemInstance Resource, so all state flows through here.
@rpc("authority", "call_remote", "reliable")
func sync_to_clients(pos: Vector2, data_path: String, count: int):
	var old_tile = GridService.world_to_tile(global_position)
	var was_registered = GridService.get_item_entities_at(old_tile).has(self)
	position = pos
	var new_tile = GridService.world_to_tile(global_position)
	if was_registered:
		if old_tile != new_tile:
			GridService.move_item_entity(self, old_tile, new_tile)
			# Mirror the move_child the server does in move_whole: the moved item
			# must render above items already at the destination tile.
			var parent = get_parent()
			if parent:
				parent.move_child(self, parent.get_child_count() - 1)
	else:
		# First sync on this client — position was not yet set, register now.
		GridService.register_item_entity(self)
	var inst = ItemInstance.new()
	inst.data  = load(data_path)
	inst.count = count
	set_item(inst)

# Called by a client on the server when it needs the current state of this entity
# (e.g. late-join: the initial sync_to_clients RPC was sent before they connected).
@rpc("any_peer", "call_remote", "reliable")
func request_sync():
	if not multiplayer.is_server():
		return
	if item == null or item.data == null:
		return
	var sender = multiplayer.get_remote_sender_id()
	sync_to_clients.rpc_id(sender, global_position, item.data.resource_path, item.count)
