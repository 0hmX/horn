@tool
extends Node3D

@export_group("Streaming Behavior")
## The player or runtime node to track.
@export var target_to_track: Node3D
## If true, loads a 3x3 grid of chunks. If false, loads only the current chunk.
@export var load_surrounding_chunks := true

@export_group("Editor")
## ACTIVATE this to stream chunks in the editor, following the editor camera.
@export var preview_in_editor := false

# --- Private variables ---
var _manifest: Dictionary
var _chunk_world_size := Vector2.ZERO
var _loaded_chunks: Dictionary = {} # Key: Vector2i(coord), Value: Node(chunk)
var _current_target_chunk := Vector2i(INF, INF) # Initialize to an impossible coord
var _update_cooldown := 0.0

func _ready() -> void:
	var manifest_file = FileAccess.open("res://terrain_data/manifest.json", FileAccess.READ)
	if not manifest_file:
		return
	_manifest = JSON.parse_string(manifest_file.get_as_text())
	
	var terrain_w = float(_manifest.get("terrain_size")[0])
	var terrain_d = float(_manifest.get("terrain_size")[1])
	var num_chunks_x = float(_manifest.get("num_chunks")[0])
	var num_chunks_y = float(_manifest.get("num_chunks")[1])
	
	if num_chunks_x > 0 and num_chunks_y > 0:
		_chunk_world_size.x = terrain_w / num_chunks_x
		_chunk_world_size.y = terrain_d / num_chunks_y

func _process(delta: float) -> void:
	if not _manifest or _chunk_world_size == Vector2.ZERO:
		return
	
	_update_cooldown -= delta
	if _update_cooldown <= 0.0:
		_update_cooldown = 0.25 # Update 4 times per second
		
		if (Engine.is_editor_hint() and preview_in_editor) or (not Engine.is_editor_hint()):
			_update_chunks()

func _update_chunks() -> void:
	var target_pos: Vector3
	
	if Engine.is_editor_hint() and preview_in_editor:
		var camera = get_viewport().get_camera_3d()
		if not camera: return
		target_pos = camera.global_position
	elif not Engine.is_editor_hint() and is_instance_valid(target_to_track):
		target_pos = target_to_track.global_position
	else:
		if not _loaded_chunks.is_empty(): _clear_all_chunks()
		return

	var terrain_half_size = Vector2(_manifest.get("terrain_size")[0], _manifest.get("terrain_size")[1]) / 2.0
	var new_target_chunk = Vector2i(
		floor((target_pos.x + terrain_half_size.x) / _chunk_world_size.x),
		floor((target_pos.z + terrain_half_size.y) / _chunk_world_size.y)
	)

	if new_target_chunk == _current_target_chunk:
		return
	
	# Player has moved to a new chunk, update the state
	_current_target_chunk = new_target_chunk

	# --- NEW LOGIC WITH FEATURE FLAG ---
	if load_surrounding_chunks:
		# --- 3x3 Grid Loading Logic ---
		var streaming_radius = 1 # A radius of 1 creates a 3x3 grid

		# 1. Unload chunks that are now too far away
		var chunks_to_unload = []
		for chunk_coord in _loaded_chunks.keys():
			var dist = chunk_coord - _current_target_chunk
			if max(abs(dist.x), abs(dist.y)) > streaming_radius:
				chunks_to_unload.append(chunk_coord)
		
		for coord in chunks_to_unload:
			_unload_chunk(coord)

		# 2. Load all chunks within the 3x3 grid
		for x in range(-streaming_radius, streaming_radius + 1):
			for y in range(-streaming_radius, streaming_radius + 1):
				var target_coord = _current_target_chunk + Vector2i(x, y)
				if _is_valid_chunk(target_coord) and not _loaded_chunks.has(target_coord):
					_load_chunk(target_coord)
	else:
		# --- Original Single Chunk Logic ---
		# 1. Despawn all previously loaded chunks.
		_clear_all_chunks()
		
		# 2. If the new location is on the map, spawn the single chunk for it.
		if _is_valid_chunk(_current_target_chunk):
			_load_chunk(_current_target_chunk)


func _load_chunk(coord: Vector2i) -> void:
	var chunk_name = "TerrainBody_%d_%d" % [coord.x, coord.y]
	var mesh_path = "res://terrain_data/%s.mesh" % chunk_name
	var shape_path = "res://terrain_data/%s.shape" % chunk_name
	var material_path = "res://terrain_data/%s.material" % chunk_name

	var mesh = load(mesh_path) as Mesh
	if not mesh: return
	
	var shape_resource: Shape3D
	if ResourceLoader.exists(shape_path):
		shape_resource = load(shape_path) as Shape3D

	var material: Material
	if _manifest.get("has_material", false) and ResourceLoader.exists(material_path):
		material = load(material_path) as Material
	
	var static_body := StaticBody3D.new()
	static_body.name = chunk_name
	
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	if material:
		mesh_instance.material_override = material
	static_body.add_child(mesh_instance)
	
	if shape_resource:
		var collision_shape := CollisionShape3D.new()
		collision_shape.shape = shape_resource
		static_body.add_child(collision_shape)
	
	var terrain_half_size_x = _manifest.get("terrain_size")[0] / 2.0
	var terrain_half_size_z = _manifest.get("terrain_size")[1] / 2.0
	static_body.position.x = coord.x * _chunk_world_size.x - terrain_half_size_x + _chunk_world_size.x / 2.0
	static_body.position.z = coord.y * _chunk_world_size.y - terrain_half_size_z + _chunk_world_size.y / 2.0
	
	add_child(static_body)
	_loaded_chunks[coord] = static_body

func _unload_chunk(coord: Vector2i) -> void:
	if _loaded_chunks.has(coord) and is_instance_valid(_loaded_chunks[coord]):
		_loaded_chunks[coord].queue_free()
	_loaded_chunks.erase(coord)

func _clear_all_chunks() -> void:
	for coord in _loaded_chunks.keys():
		_unload_chunk(coord)

func _is_valid_chunk(coord: Vector2i) -> bool:
	return (coord.x >= 0 and coord.x < _manifest.get("num_chunks")[0] and
			coord.y >= 0 and coord.y < _manifest.get("num_chunks")[1])
