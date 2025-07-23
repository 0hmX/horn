extends Node2D

@onready var player_spawner = $Player/MultiplayerSpawner

func _ready() -> void:
	# Connect UI buttons to the SteamManager functions
	$UI/CreateLobbyButton.pressed.connect(SteamManager.create_lobby)
	$UI/JoinLobbyButton.pressed.connect(SteamManager.find_and_join_lobby)

	# Connect to the manager's signal to know when we can spawn
	SteamManager.network_ready.connect(_on_network_ready)
	
	# Connect to Godot's signals for when players join/leave
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_network_ready() -> void:
	print("Network is ready. Spawning local player.")
	# The server spawns for everyone, clients just spawn for themselves locally
	_spawn_player(multiplayer.get_unique_id())

func _on_peer_connected(id: int) -> void:
	print("Player connected: %s" % id)
	# The server is responsible for spawning players for new clients
	if multiplayer.is_server():
		_spawn_player(id)

func _on_peer_disconnected(id: int) -> void:
	print("Player disconnected: %s" % id)
	# Find and remove the player node associated with the disconnected peer
	var player_node = get_node_or_null(str(id))
	if player_node:
		player_node.queue_free()

@rpc("any_peer", "call_local")
func _spawn_player(id: int) -> void:
	var player_instance = player_spawner.spawn(id)
	print("Spawned player for peer: %s" % id)
