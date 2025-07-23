# SteamNetworkController.gd (Updated to correctly use MultiplayerSpawner)
# This script uses the MultiplayerSpawner's spawn_function for robust, authority-aware spawning.
extends Control

@export var player_scene: PackedScene
@export var multiplayer_spawner: MultiplayerSpawner

# This script requires a LineEdit node at the specified path.
@onready var lobby_id_input: LineEdit = $VBoxContainer/LineEdit

# Flag to prevent running the setup logic more than once.
var _session_started := false

func _ready() -> void:
	# Assign our custom spawning function to the spawner. This function will
	# be called on all peers whenever the server requests a spawn.
	multiplayer_spawner.spawn_function = _spawn_player_from_data

	# When a new player connects, the server will request a spawn for them.
	multiplayer.peer_connected.connect(func(pid):
		if multiplayer.is_server():
			_request_player_spawn(pid)
	)
	
	# Connect to SteamManager to handle lobby creation and joining.
	SteamManager.lobby_created.connect(_on_lobby_created_success)
	SteamManager.lobby_joined.connect(_on_lobby_joined_success)

# This function is called by the server to initiate a spawn request.
func _request_player_spawn(peer_id: int):
	# Calling .spawn() on the spawner will trigger the assigned spawn_function
	# on all connected peers, passing the peer_id as data.
	multiplayer_spawner.spawn(peer_id)

# This is the assigned spawn_function. It runs on all peers and returns the node
# that the MultiplayerSpawner should add to the scene tree.
func _spawn_player_from_data(peer_id: int) -> Node:
	var player_inst = player_scene.instantiate()
	player_inst.name = str(peer_id)
	player_inst.position = Vector3(0, 10, 0)
	# This is the most crucial step: setting the authority on the new instance
	# before it's added to the scene.
	player_inst.set_multiplayer_authority(peer_id)
	return player_inst

func _on_create_pressed() -> void:
	SteamManager.create_steam_lobby()

func _on_join_pressed() -> void:
	var lobby_id = int(lobby_id_input.text)
	SteamManager.join_steam_lobby(lobby_id)

func _on_lobby_created_success(_success: bool, lobby_id: int):
	# Check if the session has already been started to prevent double-execution.
	if _session_started:
		return

	# When the lobby is created, we become the host.
	Steam.setLobbyData(lobby_id, "host", str(Steam.getSteamID()))
	var peer = SteamMultiplayerPeer.new()
	peer.create_host(1)
	multiplayer.multiplayer_peer = peer
	
	# Request a spawn for the host's own player character.
	_request_player_spawn(multiplayer.get_unique_id())
	visible = false
	_session_started = true

func _on_lobby_joined_success(_success: bool, lobby_id: int):
	# Check if the session has already been started to prevent double-execution.
	if _session_started:
		return
		
	# When we join a lobby, we become a client.
	var host_id = int(Steam.getLobbyData(lobby_id, "host"))
	var peer = SteamMultiplayerPeer.new()
	peer.create_client(host_id, 1)
	multiplayer.multiplayer_peer = peer
	visible = false
	_session_started = true
