@tool
extends CharacterBody3D

@export_group("Movement")
@export var speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var rotation_speed: float = 3.5
@export var spawn_wait_time: float = 3.0
@export var spawn_position_offset: float = 0.5

@export_group("Camera Settings")
@export var mouse_sensitivity: float = 0.002
@export var min_pitch_angle: float = -60.0
@export var max_pitch_angle: float = 30.0
@export var yaw_pivot: Node3D
@export var pitch_pivot: Node3D
@export var camera: Camera3D

@export_group("Node References")
@export var animation_tree: AnimationTree
@export var animation_player: AnimationPlayer

@export_group("Tools")
@export var save_tree_to_file: bool = false:
	set(value):
		if value:
			_generate_and_save_tree()
			save_tree_to_file = false

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var state_machine
var current_state_name: StringName = "Ground"
var _previous_input_dir := Vector2.ZERO
var _can_process_input := false
var _is_waiting_for_start := false
var _wait_timer := 0.0

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	camera.current = is_multiplayer_authority()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	Bus.subscribe("game_state_changed", Callable(self, "_on_game_state_changed"))
	var initial_payload = {"to": SuperState.current_state}
	_on_game_state_changed(initial_payload)
	
	setup_animation_tree()

func _on_game_state_changed(payload: Dictionary) -> void:
	if payload.has("to") and payload["to"] == SuperState.State.GAME_ACTIVE:
		_is_waiting_for_start = true
		_wait_timer = 0.0
	else:
		_can_process_input = false
		_is_waiting_for_start = false

func setup_animation_tree() -> void:
	var tree_root = load("res://player_state_machine.tres")
	if not tree_root:
		printerr("Failed to load 'res://player_state_machine.tres'. Did you save it from the Inspector?")
		return
	
	animation_tree.tree_root = tree_root
	state_machine = animation_tree.get("parameters/playback")
	state_machine.start("Ground")
	animation_tree.active = true

func _generate_and_save_tree() -> void:
	if not animation_player:
		print("ERROR: AnimationPlayer is not assigned.")
		return

	var state_machine_root = AnimationNodeStateMachine.new()
	
	var ground_blend_space = AnimationNodeBlendSpace2D.new()
	ground_blend_space.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_DISCRETE
	add_animation_to_blend_space(ground_blend_space, "Idle", Vector2(0, 0))
	add_animation_to_blend_space(ground_blend_space, "Running", Vector2(0, -1))
	add_animation_to_blend_space(ground_blend_space, "LeftTurn", Vector2(-1, 0))
	add_animation_to_blend_space(ground_blend_space, "RightTurn", Vector2(1, 0))
	state_machine_root.add_node("Ground", ground_blend_space)

	var air_blend_space = AnimationNodeBlendSpace1D.new()
	air_blend_space.min_space = -jump_velocity
	air_blend_space.max_space = jump_velocity
	add_animation_to_blend_space(air_blend_space, "Jump", jump_velocity)
	add_animation_to_blend_space(air_blend_space, "Fall", -jump_velocity)
	state_machine_root.add_node("Air", air_blend_space)

	state_machine_root.add_transition("Ground", "Air", AnimationNodeStateMachineTransition.new())
	state_machine_root.add_transition("Air", "Ground", AnimationNodeStateMachineTransition.new())
	
	var save_path = "res://player_state_machine.tres"
	var result = ResourceSaver.save(state_machine_root, save_path)
	if result == OK:
		print("Successfully saved AnimationTree resource to: ", save_path)
	else:
		print("ERROR: Failed to save AnimationTree resource.")

func add_animation_to_blend_space(blend_space, anim_name: String, pos: Variant):
	var anim_resource: Animation = animation_player.get_animation(anim_name)
	
	if not anim_resource:
		printerr("Animation not found: '", anim_name, "'. Please check spelling and case.")
		return

	var anim_node = AnimationNodeAnimation.new()
	anim_node.animation = anim_name
	
	if blend_space is AnimationNodeBlendSpace2D:
		blend_space.add_blend_point(anim_node, pos)
	elif blend_space is AnimationNodeBlendSpace1D:
		blend_space.add_blend_point(anim_node, pos)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

	if Engine.is_editor_hint() or not is_multiplayer_authority() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseMotion:
		yaw_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		pitch_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		pitch_pivot.rotation.x = clamp(pitch_pivot.rotation.x, deg_to_rad(min_pitch_angle), deg_to_rad(max_pitch_angle))

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	if _is_waiting_for_start:
		_wait_timer += delta
		if _wait_timer >= spawn_wait_time:
			_is_waiting_for_start = false
			_can_process_input = true
			var offset = Vector3(randf_range(-spawn_position_offset, spawn_position_offset), 0, randf_range(-spawn_position_offset, spawn_position_offset))
			global_position += offset

	if not _can_process_input:
		velocity = Vector3.ZERO
		move_and_slide()
		return
		
	if not is_on_floor():
		velocity.y -= gravity * delta

	if is_multiplayer_authority():
		handle_movement_and_animation(delta)
	
	move_and_slide()

func handle_movement_and_animation(delta: float) -> void:
	if is_on_floor():
		if current_state_name != "Ground":
			current_state_name = "Ground"
			state_machine.travel("Ground")

		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
			current_state_name = "Air"
			state_machine.travel("Air")
			return

		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		
		var was_turning_in_place = _previous_input_dir.y == 0 and _previous_input_dir.x != 0
		var is_running_now = input_dir.y != 0
		if was_turning_in_place and is_running_now:
			state_machine.travel("Ground")
		
		animation_tree.set("parameters/Ground/blend_position", input_dir)
		
		if input_dir.x != 0:
			rotate_y(-input_dir.x * rotation_speed * delta)
		if input_dir.y != 0:
			var direction = transform.basis * Vector3(0, 0, input_dir.y)
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = move_toward(velocity.x, 0, speed)
			velocity.z = move_toward(velocity.z, 0, speed)
			
		_previous_input_dir = input_dir
	else:
		if current_state_name != "Air":
			current_state_name = "Air"
			state_machine.travel("Air")
		
		animation_tree.set("parameters/Air/blend_position", velocity.y)
		_previous_input_dir = Vector2.ZERO
