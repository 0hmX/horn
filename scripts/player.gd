# Filename: player_controller.gd
# Attach this script to your CharacterBody3D node.

extends CharacterBody3D

# --- Movement Parameters ---
@export var speed = 5.0
@export var jump_velocity = 4.5

# --- Mouse & Camera Control ---
@export var mouse_sensitivity = 0.002  # Radians per pixel, a good starting value.

# Vertical look limits (in degrees). Converted to radians below.
@export var min_pitch_degrees = -89.0
@export var max_pitch_degrees = 89.0

# --- Node References ---
# This path points to the node that holds your Camera3D.
# Based on your scene tree, the Camera3D is a child of the second Node3D.
# This parent node will be used to handle the up/down (pitch) rotation.
# Adjust this path if you change your scene structure.
@onready var camera_pivot = $Node3D/Node3D

# --- Private Variables ---
var _min_pitch_rad: float
var _max_pitch_rad: float

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready():
	"""
	Called when the node enters the scene tree for the first time.
	"""
	# Lock the mouse cursor to the game window and hide it.
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Convert degree-based clamps to radians for internal calculations.
	_min_pitch_rad = deg_to_rad(min_pitch_degrees)
	_max_pitch_rad = deg_to_rad(max_pitch_degrees)
	
	# --- NEW: Register debug items with the global EventBus ---
	# Register the player's position. The callable points to the built-in function.
	EventBus.emit_event.call_deferred("register_debug_item", {
		"label": "Player Pos",
		"provider": Callable(self, "get_global_position")
	})
	
	EventBus.emit_event.call_deferred("register_debug_item", {
		"label": "Player Speed",
		"provider": Callable(self, "_get_speed")
	})


func _get_speed():
	return velocity

func _unhandled_input(event: InputEvent):
	"""
	Handles input events that were not handled by the GUI or other nodes.
	This is the best place for mouse motion logic.
	"""
	# Check if the input event is mouse movement.
	if event is InputEventMouseMotion:
		# Horizontal rotation (Yaw):
		# We rotate the entire CharacterBody3D left and right.
		# This makes the body's "forward" direction follow the mouse.
		rotate_y(-event.relative.x * mouse_sensitivity)

		# Vertical rotation (Pitch):
		# We only rotate the camera's parent pivot up and down.
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)

		# Clamp the vertical rotation to prevent the camera from flipping over.
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, _min_pitch_rad, _max_pitch_rad)

func _input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("quit"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _physics_process(delta: float):
	"""
	Called every physics frame. Used for movement and physics calculations.
	"""
	# Add gravity to the character.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle the Jump action.
	# Assumes you have an input action named "jump" (e.g., mapped to Spacebar).
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# --- Movement Logic ---
	# Get input for forward/backward movement.
	# Assumes "move_forward" is W and "move_backward" is S.
	var input_axis = Input.get_axis("move_backward", "move_forward")

	# Determine the forward direction based on the character's rotation.
	# The Z-axis of the basis is the "forward" direction.
	var direction = -transform.basis.z

	# Calculate the target velocity.
	if input_axis != 0:
		# If moving, set velocity based on direction, speed, and input.
		velocity.x = direction.x * speed * input_axis
		velocity.z = direction.z * speed * input_axis
	else:
		# If not moving, apply friction to stop the character.
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	# Apply the final calculated velocity to the character.
	# This function handles collisions and sliding along walls.
	move_and_slide()
