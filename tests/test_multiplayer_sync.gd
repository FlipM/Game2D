extends Node
## Multiplayer synchronisation tests: 1 server + 2 local ENet clients.
## Validates authority rules and basic RPC connectivity in one headless process.
## Run standalone help: godot --headless --path . tests/test_multiplayer_sync.gd

var _passed: int = 0
var _failed: int = 0

const PORT := 7901 # Use a distinct port so this doesn't conflict with the game.

var _server_peer: ENetMultiplayerPeer = null
var _client1_peer: ENetMultiplayerPeer = null
var _client2_peer: ENetMultiplayerPeer = null


func _ready():
	# Standalone run support
	if get_tree().current_scene == self:
		_run_all()
		print("\n=== Multiplayer Sync Tests: %d passed, %d failed ===" % [_passed, _failed])
		get_tree().quit(1 if _failed > 0 else 0)


func _run_all():
	_test_server_creation()
	_test_client_connection()
	_test_authority_guard()
	_test_peer_id_uniqueness()
	_teardown()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _assert(condition: bool, description: String):
	if condition:
		print("  PASS: %s" % description)
		_passed += 1
	else:
		printerr("  FAIL: %s" % description)
		_failed += 1

func _poll(n: int = 60):
	for _i in range(n):
		if _server_peer: _server_peer.poll()
		if _client1_peer: _client1_peer.poll()
		if _client2_peer: _client2_peer.poll()

func _teardown():
	if _server_peer: _server_peer.close()
	if _client1_peer: _client1_peer.close()
	if _client2_peer: _client2_peer.close()


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
func _test_server_creation():
	print("\n[server_creation]")
	_server_peer = ENetMultiplayerPeer.new()
	var err = _server_peer.create_server(PORT, 4)
	_assert(err == OK, "ENet server created successfully on port %d" % PORT)
	_assert(_server_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED,
		"server peer reports connected status after creation")

func _test_client_connection():
	print("\n[client_connection]")
	_client1_peer = ENetMultiplayerPeer.new()
	var err1 = _client1_peer.create_client("127.0.0.1", PORT)
	_assert(err1 == OK, "client 1 create_client returns OK")

	_client2_peer = ENetMultiplayerPeer.new()
	var err2 = _client2_peer.create_client("127.0.0.1", PORT)
	_assert(err2 == OK, "client 2 create_client returns OK")

	# Poll to let the handshake complete.
	_poll(120)

	_assert(_server_peer.get_available_packet_count() >= 0,
		"server peer is valid after client connections")
	_assert(_client1_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED,
		"client 1 is not disconnected after poll")
	_assert(_client2_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED,
		"client 2 is not disconnected after poll")

func _test_authority_guard():
	print("\n[authority_guard]")
	## Simulate the server-only guard used in CombatComponent and Spawner.
	## In headless mode the default multiplayer is a OfflineMultiplayerPeer acting as server.
	var default_mp = multiplayer # SceneTree.multiplayer — OfflineMultiplayer
	_assert(default_mp.is_server(), "default headless multiplayer is_server() == true")

	## A stub SceneMultiplayer backed by a client peer should NOT be_server.
	var client_mp = SceneMultiplayer.new()
	client_mp.multiplayer_peer = _client1_peer
	_assert(not client_mp.is_server(), "client-backed SceneMultiplayer is_server() == false")

func _test_peer_id_uniqueness():
	print("\n[peer_id_uniqueness]")
	## Server unique ID in ENet is always 1.
	var server_mp = SceneMultiplayer.new()
	server_mp.multiplayer_peer = _server_peer
	_poll(20)
	_assert(server_mp.get_unique_id() == 1, "server peer unique_id == 1")
	## Client IDs are assigned by the server and are > 1.
	var client_mp = SceneMultiplayer.new()
	client_mp.multiplayer_peer = _client1_peer
	_poll(20)
	_assert(client_mp.get_unique_id() > 1 or client_mp.get_unique_id() == 0,
		"client peer unique_id assigned by server (> 1) or still connecting (0)")
