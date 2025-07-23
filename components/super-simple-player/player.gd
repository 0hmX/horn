extends CharacterBody3D

@export var speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var rotation_speed: float = 3.5

@export_group("Camera Settings")
@export var mouse_sensitivity: float = 0.002
@export var min_pitch_angle: float = -60.0
@export var max_pitch_angle: float = 30.0
@export var yaw_pivot: Node3D
@export var pitch_pivot: Node3D
@export var camera: Camera3D

@export_group("Node References")
@export var animation_player: AnimationPlayer

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var synced_animation: StringName

# This flag will control whether the player can move or look around.
var _can_process_input := false

func _ready() -> void:
	print("Player spawned. Name: ", name, ", Authority ID: ", get_multiplayer_authority(), ", My ID: ", multiplayer.get_unique_id())
	camera.current = is_multiplayer_authority()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Subscribe to future game state change events.
	Bus.subscribe("game_state_changed", Callable(self, "_on_game_state_changed"))

	# Immediately check the current state in case we missed the signals.
	# This ensures the player is initialized correctly if it spawns into an
	# already active game.
	var initial_payload = {
		"from": SuperState.State.IN_LOBBY,
		"to": SuperState.current_state
	}
	_on_game_state_changed(initial_payload)

# This function is called by the Bus when the game state changes.
func _on_game_state_changed(payload: Dictionary):
	# Only enable controls if the new state is GAME_ACTIVE.
	print(payload)
	if payload.has("to") and payload["to"] == SuperState.State.GAME_ACTIVE:
		_can_process_input = true
	else:
		_can_process_input = false

func _unhandled_input(event: InputEvent) -> void:
	# Always allow the player to toggle the mouse cursor.
	if event.is_action_pressed("quit"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Block camera movement unless the game is active.
	if not _can_process_input:
		return

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event is InputEventMouseMotion:
		if is_multiplayer_authority():
			yaw_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
			pitch_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
			pitch_pivot.rotation.x = clamp(pitch_pivot.rotation.x, deg_to_rad(min_pitch_angle), deg_to_rad(max_pitch_angle))

func _physics_process(delta: float) -> void:
	# Block all movement and physics unless the game is active.
	if not _can_process_input:
		# Ensure the character stops moving if the game state changes mid-action.
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return

	if is_multiplayer_authority():
		if not is_on_floor():
			velocity.y -= gravity * delta

		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = jump_velocity

		var input_dir := Input.get_vector("move_left", "move_right","move_backward", "move_forward")
		
		rotate_y(-input_dir.x * rotation_speed * delta)

		var direction = transform.basis * Vector3(0, 0, input_dir.y)

		if direction != Vector3.ZERO:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = move_toward(velocity.x, 0, speed)
			velocity.z = move_toward(velocity.z, 0, speed)
		
		var is_moving = Vector2(velocity.x, velocity.z).length_squared() > 0.1
		synced_animation = &"Running" if is_moving else &"LookingDown"
		
		move_and_slide()

	if animation_player.current_animation != synced_animation:
		animation_player.play(synced_animation)
