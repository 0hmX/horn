@tool
extends Node3D

@export_group("References")
@export var start_node: NodePath
@export var end_node: NodePath
@export var path_block_scene: PackedScene

@export_group("Path Shape")
@export var path_gap: float = 2.0
@export_range(1, 10, 1) var lane_count: int = 3
@export var lane_spacing: float = 2.0
@export var horizontal_deviation: float = 5.0
@export var vertical_deviation: float = 2.0
@export var max_angle_change_deg: float = 25.0
@export var start_offset := Vector3.ZERO
@export var end_offset := Vector3.ZERO

@export_group("Curve Control Points")
@export var control_points: Array[Vector3]

@export_group("Noise Settings")
@export var noise: FastNoiseLite

@export_group("Actions")
@export_tool_button("Generate Path") var generate:
	get:
		return generate_path
	set(value):
		pass

@export_tool_button("Clear Path") var clear:
	get:
		return clear_path
	set(value):
		pass

var _path_container: Node3D

func _ready() -> void:
	if not has_node("PathContainer"):
		_path_container = Node3D.new()
		_path_container.name = "PathContainer"
		add_child(_path_container)
		_path_container.owner = get_tree().edited_scene_root
	else:
		_path_container = get_node("PathContainer")

func clear_path() -> void:
	if not _path_container:
		return
	for child in _path_container.get_children():
		child.queue_free()
	print("Previous path cleared.")

func generate_path() -> void:
	if not get_node_or_null(start_node) or not get_node_or_null(end_node):
		push_error("Start Node or End Node is not set.")
		return
	if not path_block_scene:
		push_error("Path Block Scene is not set.")
		return
	if not noise:
		push_error("Noise resource is not set.")
		return
	if path_gap <= 0:
		push_error("Path Gap must be greater than zero.")
		return

	clear_path()
	print("Generating new path...")

	var start_pos: Vector3 = get_node(start_node).global_position + start_offset
	var end_pos: Vector3 = get_node(end_node).global_position + end_offset

	var curve = Curve3D.new()
	curve.add_point(start_pos)
	for point in control_points:
		curve.add_point(global_position + point)
	curve.add_point(end_pos)
	
	var total_distance: float = curve.get_baked_length()
	var total_segments: int = int(total_distance / path_gap)
	
	if total_segments <= 1:
		push_warning("Distance is too short to generate a path with the current gap.")
		return

	var previous_center_point: Vector3 = start_pos
	var previous_direction: Vector3 = curve.sample_baked(0.01, true) - start_pos
	if previous_direction == Vector3.ZERO:
		previous_direction = (end_pos - start_pos).normalized()
	
	var lane_center_offset: float = (float(lane_count - 1) / 2.0) * lane_spacing

	for i in range(total_segments + 1):
		var distance_along_curve = float(i) * path_gap
		var ideal_point: Vector3 = curve.sample_baked(distance_along_curve, true)
		
		var noise_x: float = noise.get_noise_3d(distance_along_curve, 0, 0)
		var noise_y: float = noise.get_noise_3d(0, distance_along_curve, 0)
		var noise_z: float = noise.get_noise_3d(0, 0, distance_along_curve)
		
		var target_point: Vector3 = ideal_point + Vector3(
			noise_x * horizontal_deviation,
			noise_y * vertical_deviation,
			noise_z * horizontal_deviation
		)
		
		var current_direction: Vector3 = (target_point - previous_center_point).normalized()
		var max_angle_rad: float = deg_to_rad(max_angle_change_deg)
		
		if current_direction == Vector3.ZERO:
			current_direction = previous_direction
		
		current_direction = previous_direction.slerp(current_direction, 1.0).limit_length(1.0)
		current_direction = previous_direction.slerp(current_direction, max_angle_rad)

		var current_center_point: Vector3 = previous_center_point + current_direction * path_gap
		var right_vector: Vector3 = current_direction.cross(Vector3.UP).normalized()
		
		var look_at_point = current_center_point + current_direction * path_gap

		for j in range(lane_count):
			if (i + j) % 2 == 0:
				var lane_offset: float = (float(j) * lane_spacing) - lane_center_offset
				var block_position: Vector3 = current_center_point + (right_vector * lane_offset)
				
				var block_instance = path_block_scene.instantiate()
				_path_container.add_child(block_instance)
				block_instance.owner = get_tree().edited_scene_root
				block_instance.global_position = block_position
				block_instance.look_at(look_at_point, Vector3.UP)
		
		previous_center_point = current_center_point
		previous_direction = current_direction

	print("Path generation complete.")
