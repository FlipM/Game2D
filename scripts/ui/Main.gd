extends Node

const PORT = 7000
const DEFAULT_SERVER_IP = "127.0.0.1"

@onready var main_menu = $CanvasLayer/MainMenu
@onready var address_entry = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/AddressEntry

func _ready():
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_host_pressed():
	main_menu.hide()
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, 32)
	if error != OK:
		print("Cannot host: ", error)
		main_menu.show()
		return
	multiplayer.multiplayer_peer = peer
	print("Hosting on port ", PORT)
	_start_game()

func _on_join_pressed():
	main_menu.hide()
	var address = address_entry.text
	if address == "":
		address = DEFAULT_SERVER_IP
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, PORT)
	if error != OK:
		print("Cannot connect: ", error)
		main_menu.show()
		return
	multiplayer.multiplayer_peer = peer
	print("Connecting to ", address)

func _start_game():
	var world = load("res://scenes/entities/World.tscn").instantiate()
	get_tree().root.add_child(world)
	# Main node is just a logic node, UI is handled separately.

func _on_player_connected(id):
	print("Player connected: ", id)

func _on_player_disconnected(id):
	print("Player disconnected: ", id)

func _on_connected_ok():
	print("Connected to server!")
	_start_game()

func _on_connected_fail():
	print("Connection failed!")
	main_menu.show()

func _on_server_disconnected():
	print("Server disconnected!")
	# Back to menu
	get_tree().reload_current_scene()
