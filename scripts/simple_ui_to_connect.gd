extends Control

# The scene for the player character.
@export var player_scene: PackedScene
# Reference to the MultiplayerSpawner node in your scene.
@export var multiplayer_spawner: MultiplayerSpawner

@onready var lobby_id_input: LineEdit = $"VBoxContainer/LineEdit"
@onready var lobby_id_display_label: Label = $"Label"


func _ready() -> void:
	# Assign our custom spawning function to the spawner.
	# This function will be called on all peers when the server requests a spawn.
	if multiplayer_spawner != null:
		multiplayer_spawner.spawn_function = _spawn_player_from_data
	else:
		printerr("MultiplayerSpawner node is not assigned in the Inspector. Spawning will fail.")

	SteamManager.lobby_created.connect(_on_lobby_created_success)
	SteamManager.lobby_joined.connect(_on_lobby_joined_success)


# --- UI Button Handlers ---
func _on_create():
	SteamManager.create_steam_lobby()

func _on_join():
	if lobby_id_input == null:
		printerr("Cannot join lobby: LobbyIDInput node is missing.")
		return
	var lobby_id_text = lobby_id_input.text
	if lobby_id_text.is_valid_int():
		SteamManager.join_steam_lobby(int(lobby_id_text))
	else:
		print("Invalid Lobby ID.")


# --- SteamManager Signal Callbacks ---
func _on_lobby_created_success(success: bool, lobby_id: int):
	if not success:
		print("Failed to host lobby.")
		return
		
	if SteamManager.lobby_joined.is_connected(_on_lobby_joined_success):
		SteamManager.lobby_joined.disconnect(_on_lobby_joined_success)
		
	print("Lobby hosted successfully! Your Lobby ID is: %s" % lobby_id)
	if lobby_id_display_label != null:
		lobby_id_display_label.text = "Lobby ID: %s" % lobby_id
		lobby_id_display_label.visible = true

	Steam.setLobbyData(lobby_id, "0hmx.0hmx", str(Steam.getSteamID()))
	
	var peer = SteamMultiplayerPeer.new()
	peer.create_host(1)
	multiplayer.multiplayer_peer = peer
	
	# The server requests a spawn for itself (peer_id = 1).
	_request_player_spawn(multiplayer.get_unique_id())
	
	# Connect to the peer_connected signal to spawn players for new clients.
	multiplayer.peer_connected.connect(_on_peer_connected)
	
	visible = false

func _on_lobby_joined_success(success: bool, lobby_id: int):
	if not success:
		print("Failed to join lobby.")
		return

	if SteamManager.lobby_created.is_connected(_on_lobby_created_success):
		SteamManager.lobby_created.disconnect(_on_lobby_created_success)

	print("Joined lobby successfully! ID: %s" % lobby_id)
	
	var host_id = int(Steam.getLobbyData(lobby_id, "0hmx.0hmx"))
	
	var peer = SteamMultiplayerPeer.new()
	peer.create_client(host_id, 1)
	multiplayer.multiplayer_peer = peer
	
	# The client just connects. The server and MultiplayerSpawner will handle everything else.
	visible = false

# --- Godot Multiplayer Signal Callback ---
func _on_peer_connected(id: int):
	# When a new peer connects, the server tells the spawner to create a character for them.
	# The spawner will run the spawn_function on all clients, including the new one.
	_request_player_spawn(id)

# --- Spawning Logic ---
func _request_player_spawn(peer_id: int):
	# The server requests a custom spawn, passing the peer_id of the new player as data.
	# The spawn_function will be called on all peers to perform the actual spawn.
	if multiplayer_spawner != null:
		multiplayer_spawner.spawn(peer_id)

# This function is assigned to the MultiplayerSpawner's `spawn_function` property.
# It is called on ALL peers (including the server) when the server calls `spawn()`.
func _spawn_player_from_data(peer_id: int) -> Node:
	var player_inst = player_scene.instantiate()
	player_inst.name = str(peer_id)
	
	# This is the crucial step. We set the authority on the instance before returning it.
	# The spawner will then add it to the scene tree for us.
	player_inst.set_multiplayer_authority(peer_id)
	
	print("Executing spawn function for peer: %s" % peer_id)
	return player_inst
