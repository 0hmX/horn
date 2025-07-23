extends Control

@export var player_scene: PackedScene
@export var multiplayer_spawner: MultiplayerSpawner
@export var terrain3d: Terrain3D

@onready var lobby_id_input: LineEdit = $VBoxContainer/LineEdit

var _session_started := false

func _ready() -> void:
	Terrain.terrain3d = terrain3d
	multiplayer_spawner.spawn_function = _spawn_player_from_data
	multiplayer.peer_connected.connect(func(pid):
		Bus.publish("peer_joined_session", {"peer_id": pid})
		if multiplayer.is_server():
			_request_player_spawn(pid)
	)
	
	SteamManager.lobby_created.connect(_on_lobby_created_success)
	SteamManager.lobby_joined.connect(_on_lobby_joined_success)

func _request_player_spawn(peer_id: int):
	multiplayer_spawner.spawn(peer_id)

func _spawn_player_from_data(peer_id: int) -> Node:
	var player_inst = player_scene.instantiate()
	player_inst.name = str(peer_id)
	player_inst.set_multiplayer_authority(peer_id)
	Bus.publish("player_spawned", {"peer_id": peer_id, "player_node": player_inst})
	return player_inst

func _on_create_pressed() -> void:
	SteamManager.create_steam_lobby()

func _on_join_pressed() -> void:
	var lobby_id = int(lobby_id_input.text)
	SteamManager.join_steam_lobby(lobby_id)

func _on_lobby_created_success(_success: bool, lobby_id: int):
	if _session_started:
		return
	Bus.publish("session_started", {"is_host": true, "peer_id": multiplayer.get_unique_id()})
	Bus.publish("lobby_ui_hidden")

	DisplayServer.clipboard_set(str(lobby_id))

	Steam.setLobbyData(lobby_id, "host", str(Steam.getSteamID()))
	var peer = SteamMultiplayerPeer.new()
	peer.create_host(1)
	multiplayer.multiplayer_peer = peer
	
	_request_player_spawn(multiplayer.get_unique_id())
	visible = false
	_session_started = true


func _on_lobby_joined_success(_success: bool, lobby_id: int):
	if _session_started:
		return
		
	var host_id = int(Steam.getLobbyData(lobby_id, "host"))
	var peer = SteamMultiplayerPeer.new()
	peer.create_client(host_id, 1)
	multiplayer.multiplayer_peer = peer
	visible = false
	_session_started = true

	Bus.publish("session_started", {"is_host": false, "peer_id": multiplayer.get_unique_id()})
	Bus.publish("lobby_ui_hidden")
