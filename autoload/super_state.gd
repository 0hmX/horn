class_name GameState
extends Node

enum State {
	IN_LOBBY,
	SESSION_LOADING,
	GAME_ACTIVE,
	GAME_PAUSED
}

var current_state: GameState.State = GameState.State.IN_LOBBY
var terrain_ref: Terrain3D = null
var local_player_ref : Node3D = null
var _is_local_player_spawned := false

func _ready() -> void:
	Bus.subscribe("session_started", Callable(self, "_on_session_started"))
	Bus.subscribe("player_spawned", Callable(self, "_on_player_spawned"))

func set_state(new_state: GameState.State) -> void:
	if current_state == new_state:
		return

	var previous_state = current_state
	current_state = new_state
	
	var payload = {"from": previous_state, "to": new_state}
	Bus.publish("game_state_changed", payload)
	print("Game State changed from %s to %s" % [State.keys()[previous_state], State.keys()[new_state]])

func _on_session_started(_payload: Dictionary):
	set_state(GameState.State.SESSION_LOADING)

func _on_player_spawned(payload: Dictionary):
	if payload.has("peer_id") and payload.has("player_node") and payload["peer_id"] == multiplayer.get_unique_id():
		_is_local_player_spawned = true
		local_player_ref = payload["player_node"]
		_check_if_loading_is_complete()

func _check_if_loading_is_complete() -> void:
	if current_state != GameState.State.SESSION_LOADING:
		return
	if _is_local_player_spawned:
		set_state(GameState.State.GAME_ACTIVE)
