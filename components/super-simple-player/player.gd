extends CharacterBody3D

## The character's current physical state.
enum State { GROUND, AIR, LEDGE_GRAB }
var current_state = State.GROUND:
	set(new_state):
		if current_state != new_state:
			print("STATE CHANGE: %s -> %s" % [State.keys()[current_state], State.keys()[new_state]])
			current_state = new_state

# --- Exportable Properties ---
@export_group("Animations")
@export var animation_map: Dictionary = {
	"idle": &"Idle",
	"run": &"Running",
	"jump": &"Jump",
	"fall": &"Fall",
	"ledge_hang": &"LedgeHang",
	"climb_up": &"ClimbUp",
	"turn_right": &"RightTurn",
	"turn_left": &"LeftTurn",
}
@export var animation_blend_time: float = 0.2 # <--- ADD THIS LINE

@export_group("Movement")
@export var speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var rotation_speed: float = 3.5
@export var wait_period: float = 3.0

@export_group("Camera Settings")
@export var mouse_sensitivity: float = 0.002
@export var min_pitch_angle: float = -60.0
@export var max_pitch_angle: float = 30.0
@export var yaw_pivot: Node3D
@export var pitch_pivot: Node3D
@export var camera: Camera3D

@export_group("Ledge Grab")
@export var ledge_climb_offset := Vector3(0, 1.2, -1.0)

@export_group("Node References")
@export var animation_player: AnimationPlayer

# --- Private Variables ---
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var synced_animation: StringName
var is_climbing := false

# --- OnReady Node References ---
@onready var wall_ray := $LedgeDetector/WallRay
@onready var ledge_ray := $LedgeDetector/LedgeRay
@onready var collision_shape := $Bone

var _can_process_input := false
var _is_waiting_for_start := false
var _wait_timer := 0.0

# --- Godot Functions ---
func _ready() -> void:
	print("LOG: Player._ready() called. Name: %s, Authority: %s" % [name, get_multiplayer_authority()])
	camera.current = is_multiplayer_authority()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Bus subscription and initial state change would go here if needed
	# Example: Bus.subscribe("game_state_changed", Callable(self, "_on_game_state_changed"))

# Add this entire function to your script
func _unhandled_input(event: InputEvent) -> void:
	# First, check if the "quit" action was just pressed
	if event.is_action_pressed("quit"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			print("LOG: Mouse cursor released.")
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			print("LOG: Mouse cursor captured.")

	# The rest of your mouse motion logic follows
	if not _can_process_input or not is_multiplayer_authority():
		return

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event is InputEventMouseMotion:
		yaw_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		pitch_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		pitch_pivot.rotation.x = clamp(pitch_pivot.rotation.x, deg_to_rad(min_pitch_angle), deg_to_rad(max_pitch_angle))

func _physics_process(delta: float) -> void:
	# This section can be used for game state management (e.g., waiting for game start)
	# For simplicity, we'll assume input is always enabled.
	_can_process_input = true 

	if not _can_process_input:
		return
	
	if is_multiplayer_authority():
		match current_state:
			State.GROUND:
				ground_state(delta)
			State.AIR:
				air_state(delta)
			State.LEDGE_GRAB:
				ledge_grab_state(delta)
	
	move_and_slide()

func ground_state(delta: float) -> void:
	# Handle Jump
	if Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
		self.current_state = State.AIR # Use self to trigger the setter
		set_animation(&"jump")
		print("LOG: Jump action pressed. Velocity.y set to %f" % velocity.y)
		return

	# Get input for movement
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

	# --- REFINED LOGIC ---
	
	# 1. Apply rotation first, if there is any horizontal input.
	if input_dir.x != 0:
		rotate_y(-input_dir.x * rotation_speed * delta)
	
	# 2. Decide animation and velocity based on forward/backward input priority.
	if input_dir.y != 0:
		# Player is actively moving forward or backward.
		set_animation(&"run")
		
		var direction = transform.basis * Vector3(0, 0, input_dir.y)
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		# Player is NOT moving forward or backward. They are either turning in place or idle.
		if input_dir.x != 0:
			# Turning in place.
			set_animation(&"turn_right" if input_dir.x > 0 else &"turn_left")
		else:
			# Completely idle.
			set_animation(&"idle")
		
		# Decelerate any remaining horizontal velocity.
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
	
	# --- End of Refined Logic ---
	
	# Check if we walked off an edge
	if not is_on_floor():
		print("LOG: Left ground without jumping (walked off edge).")
		self.current_state = State.AIR

func air_state(delta: float) -> void:
	# Apply gravity
	velocity.y -= gravity * delta

	# Check for landing
	if is_on_floor():
		print("LOG: Landed on floor.")
		self.current_state = State.GROUND
		return

	# Check for ledges only when falling
	if velocity.y < 0:
		set_animation(&"fall")
		check_for_ledge()

func ledge_grab_state(delta: float) -> void:
	# If a climb is already happening, do nothing to prevent input spam
	if is_climbing:
		return

	velocity = Vector3.ZERO
	set_animation(&"ledge_hang")

	if Input.is_action_just_pressed("jump"):
		print("LOG: 'jump' pressed in LEDGE_GRAB state. Attempting to climb.")
		is_climbing = true # Prevent further climb actions
		climb_up()
	elif Input.is_action_just_pressed("crouch"):
		print("LOG: 'crouch' pressed in LEDGE_GRAB state. Letting go.")
		let_go()

# Replace your existing set_animation function with this one
func set_animation(key: StringName) -> void:
	if not animation_map.has(key):
		print("ERROR: Animation key not found in map: ", key)
		return

	var new_anim = animation_map[key]
	if synced_animation != new_anim:
		print("LOG: Animation changed to '%s' (Key: '%s')" % [new_anim, key])
		synced_animation = new_anim
		# The only change is adding the blend time as the second argument
		animation_player.play(synced_animation, animation_blend_time)

func check_for_ledge() -> void:
	if wall_ray.is_colliding() and not ledge_ray.is_colliding():
		print("LOG: Valid ledge detected!")
		grab_ledge()

func grab_ledge() -> void:
	self.current_state = State.LEDGE_GRAB
	
	var collision_point = wall_ray.get_collision_point()
	var wall_normal = wall_ray.get_collision_normal()
	print("LOG: Grabbing ledge at point: %s with normal: %s" % [collision_point, wall_normal])
	
	var hang_position = collision_point + wall_normal * 0.4
	
	global_position.x = hang_position.x
	global_position.z = hang_position.z
	global_position.y = collision_point.y - ($LedgeDetector.position.y + wall_ray.position.y)
	print("LOG: Snapped player position to %s" % global_position)

func climb_up() -> void:
	print("LOG: climb_up() started.")
	set_animation(&"climb_up")

	if collision_shape:
		print("LOG: Disabling collision shape for climb.")
		collision_shape.disabled = true

	# Wait for animation to finish (ensure it's not looping)
	await animation_player.animation_finished
	print("LOG: 'ClimbUp' animation finished.")

	global_position += ledge_climb_offset
	print("LOG: Moved player by offset. New position: %s" % global_position)
	self.current_state = State.GROUND

	if collision_shape:
		print("LOG: Re-enabling collision shape.")
		collision_shape.disabled = false
	
	# Reset the flag only after everything is finished.
	is_climbing = false
	print("LOG: Climb complete. is_climbing reset to false.")

func let_go() -> void:
	print("LOG: let_go() called.")
	self.current_state = State.AIR
