extends CharacterBody3D

@export var speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var rotation_speed: float = 10.0

@export_group("Camera Settings")
@export var mouse_sensitivity: float = 0.002
@export var min_pitch_angle: float = -60.0
@export var max_pitch_angle: float = 30.0
@export var yaw_pivot: Node3D   # Assign your 'cam' node here
@export var pitch_pivot: Node3D # Assign your 'cam-2' node here

@export_group("Node References")
@export var animation_player: AnimationPlayer

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var synced_animation: StringName

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event is InputEventMouseMotion:
		if is_multiplayer_authority():
			# CHANGED: Rotate the player body directly for instant horizontal look.
			self.rotate_y(-event.relative.x * mouse_sensitivity)

			# Vertical rotation on the pivot remains the same.
			pitch_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
			pitch_pivot.rotation.x = clamp(pitch_pivot.rotation.x, deg_to_rad(min_pitch_angle), deg_to_rad(max_pitch_angle))

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		if not is_on_floor():
			velocity.y -= gravity * delta

		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = jump_velocity

		# REMOVED: The slerp is no longer needed as the mouse rotates the player directly.
		# transform.basis = transform.basis.slerp(yaw_pivot.basis, rotation_speed * delta)

		var input_dir := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
		var direction := (transform.basis * Vector3(-input_dir.x, 0, input_dir.y)).normalized()

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
