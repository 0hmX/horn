# Steam.gd
# A more comprehensive Steam manager autoload script.
extends Node

# Your game's App ID. Use 480 for testing (Spacewar).
# Replace with your actual App ID for release!
const STEAM_APP_ID = 480

# Signals to communicate Steam events to the rest of the game
signal steam_initialized(success, message)
signal lobby_created(success, lobby_id)
signal lobby_joined(success, lobby_id)
signal lobby_list_updated(lobbies)
signal lobby_message_received(lobby_id, user_id, message)
signal persona_state_changed(user_id, flags)

func _ready():
	# The steam_appid.txt file is required for testing outside of the Steam client.
	# It tells the Steam client which app to launch.
	var file = FileAccess.open("steam_appid.txt", FileAccess.WRITE)
	if file:
		file.store_string(str(STEAM_APP_ID))
		file.close()
	else:
		print("Error: Could not create steam_appid.txt")

	# Initialize Steamworks
	var result = Steam.steamInitEx() # Use steamInitEx for more detailed results
	if result.get('status'):
		var error_message = "Steamworks initialization failed. Reason: %s" % result['verbal']
		print(error_message)
		emit_signal("steam_initialized", false, error_message)
		get_tree().quit()
		return

	print("Steamworks initialized successfully!")
	emit_signal("steam_initialized", true, "Steamworks initialized successfully!")

	# Connect to a wide range of useful Steam signals
	_connect_signals()

func _process(_delta):
	# The Steam callbacks must be run constantly.
	Steam.run_callbacks()

func _connect_signals():
	# Connect to signals using the correct snake_case names from the documentation
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_message.connect(_on_lobby_message)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.lobby_data_update.connect(_on_lobby_data_update)
	Steam.join_game_requested.connect(_on_game_join_requested)
	Steam.persona_state_change.connect(_on_persona_state_change)
	Steam.p2p_session_request.connect(_on_p2p_session_request)
	Steam.p2p_session_connect_fail.connect(_on_p2p_session_connect_fail)

# --- Public Functions ---

func get_steam_name(steam_id: int = 0) -> String:
	"""Returns the persona name of the given user, or the current user if no ID is provided."""
	if steam_id == 0:
		return Steam.getPersonaName()
	else:
		return Steam.getFriendPersonaName(steam_id)

func create_steam_lobby(lobby_type: int = Steam.LOBBY_TYPE_PUBLIC, max_members: int = 8):
	"""Requests Steam to create a new lobby."""
	print("Creating a new Steam lobby...")
	Steam.createLobby(lobby_type, max_members)

func request_steam_lobby_list():
	"""Requests a list of available public lobbies from Steam."""
	print("Requesting lobby list...")
	# You can add filters here to narrow down the search, for example:
	# Steam.addRequestLobbyListStringFilter("game_version", "1.0", Steam.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()

func join_steam_lobby(lobby_id: int):
	"""Attempts to join a specific Steam lobby by its ID."""
	print("Attempting to join lobby: %s" % lobby_id)
	Steam.joinLobby(lobby_id)

func leave_steam_lobby(lobby_id: int):
	"""Leaves the specified lobby."""
	print("Leaving lobby: %s" % lobby_id)
	Steam.leaveLobby(lobby_id)

func send_lobby_message(lobby_id: int, message: String) -> bool:
	"""Sends a text message to the lobby chat."""
	# Note: sendLobbyChatMsg expects a PackedByteArray, not a String
	var message_bytes = message.to_utf8_buffer()
	return Steam.sendLobbyChatMsg(lobby_id, message_bytes)

# --- Signal Handlers ---

func _on_lobby_created(connect_result: int, lobby_id: int):
	if connect_result == Steam.RESULT_OK:
		print("Lobby created successfully! Lobby ID: %s" % lobby_id)
		emit_signal("lobby_created", true, lobby_id)
	else:
		print("Failed to create lobby. Result code: %s" % connect_result)
		emit_signal("lobby_created", false, 0)

func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int):
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		print("Joined lobby successfully! Lobby ID: %s" % lobby_id)
		emit_signal("lobby_joined", true, lobby_id)
	else:
		print("Failed to join lobby. Response code: %s" % response)
		emit_signal("lobby_joined", false, 0)

func _on_lobby_match_list(lobbies: Array):
	print("Found %s lobbies." % len(lobbies))
	emit_signal("lobby_list_updated", lobbies)

func _on_lobby_message(lobby_id: int, user_id: int, message: String, _chat_type: int):
	# The signal now correctly provides a String, not PackedByteArray
	print("Lobby (%s) message from %s: %s" % [lobby_id, get_steam_name(user_id), message])
	emit_signal("lobby_message_received", lobby_id, user_id, message)

func _on_lobby_chat_update(lobby_id: int, changed_user_id: int, making_change_id: int, chat_state: int):
	print("Lobby (%s) chat update: User %s state changed by %s. New state: %s" % [lobby_id, changed_user_id, making_change_id, chat_state])

func _on_lobby_data_update(success_code: int, lobby_id: int, member_id: int):
	# The 'success' parameter is an integer result code, not a boolean
	if success_code == 1: # Assuming 1 is success, adjust if docs specify otherwise
		print("Lobby (%s) data updated for member %s." % [lobby_id, member_id])

func _on_game_join_requested(user_id: int, connect_string: String):
	print("User %s wants to join. Connect string: %s" % [get_steam_name(user_id), connect_string])
	if connect_string.is_valid_int():
		join_steam_lobby(int(connect_string))

func _on_persona_state_change(user_id: int, flags: int):
	emit_signal("persona_state_changed", user_id, flags)

func _on_p2p_session_request(remote_steam_id: int):
	print("Accepting P2P session request from %s" % remote_steam_id)
	Steam.acceptP2PSessionWithUser(remote_steam_id)

func _on_p2p_session_connect_fail(remote_steam_id: int, session_error: int):
	print("P2P session connection failed with %s. Error: %s" % [remote_steam_id, session_error])
