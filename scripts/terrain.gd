# AsyncTerrainGenerator.gd
# Generates chunked terrain with collision, subdivision, vertex colors, and detail layers.
@tool
extends Node3D

# --- User Configuration ---
@export_group("Source Data")
@export var heightmap: Texture2D
@export var terrain_size := Vector2(100, 100)
@export var terrain_height := 15.0

@export_group("Appearance")
@export var color_gradient: GradientTexture1D

@export_group("Geometry Quality")
@export_range(1, 8, 1) var subdivision_level: int = 1

@export_group("Detail Objects")
## An array of DetailLayer resources that define what to place on the terrain.
@export var detail_layers: Array[DetailLayer]

@export_group("Physics")
@export var collision_type: CollisionType = CollisionType.TRIMESH

@export_group("Chunking")
@export var enable_chunking := true
## How many chunks to divide the terrain into (e.g., (4, 4) for a 4x4 grid).
@export var chunk_division := Vector2i(4, 4)

@export_group("Preview Settings")
@export var preview_size := Vector2(100, 100)
@export var preview_height := 15.0

@export_group("Performance & Safety")
@export_range(100, 50000, 100) var operations_per_frame := 5000
@export var enable_kill_switch := true
@export var max_operations_limit := 16_000_000

@export_group("Actions")
@export var generate_chunked_terrain: bool = false:
	set(value):
		if value:
			if _generation_state == GenState.IDLE:
				_start_generation(false)
			else:
				printerr("Generation is already in progress.")
		property_list_changed.emit()

@export var generate_full_map_preview: bool = false:
	set(value):
		if value:
			if _generation_state == GenState.IDLE:
				_start_generation(true)
			else:
				printerr("Cannot generate preview while another operation is in progress.")
		property_list_changed.emit()

@export var bake_chunks_to_disk: bool = false:
	set(value):
		if value:
			_bake_chunks()
		property_list_changed.emit()

# --- Enums ---
enum CollisionType { NONE, TRIMESH, HEIGHTMAP }
enum GenState {
	IDLE,
	PREPARING,
	GENERATING_VERTICES,
	GENERATING_INDICES,
	GENERATING_DETAILS,
	FINALIZING
}

# --- Internal State ---
var _generation_state: GenState = GenState.IDLE
var _is_preview_mode := false
var _surface_tool: SurfaceTool
var _image: Image
var _gradient_image: Image
var _height_data: PackedFloat32Array
var _chunk_pixel_offset := Vector2i.ZERO
var _current_chunk_dims := Vector2i.ZERO
var _preview_dims := Vector2i.ZERO
var _num_chunks := Vector2i.ZERO
var _current_chunk := Vector2i.ZERO
var _progress_x := 0
var _progress_z := 0
var _total_operations := 0
var _detail_instance_transforms: Dictionary[Vector2i, Dictionary] = {}


# --- Core Logic ---
func _process(_delta: float) -> void:
	if not Engine.is_editor_hint() or _generation_state == GenState.IDLE:
		return

	match _generation_state:
		GenState.PREPARING: _prepare_generation_step()
		GenState.GENERATING_VERTICES: _process_geometry_vertices()
		GenState.GENERATING_INDICES: _process_geometry_indices()
		GenState.GENERATING_DETAILS: _process_geometry_details()
		GenState.FINALIZING: _finalize_generation_step()

func _start_generation(is_preview: bool) -> void:
	var mode_string = "preview" if is_preview else "chunked terrain"
	print("Starting %s generation..." % mode_string)

	if not _prepare_common_data(not is_preview):
		_cancel_generation("Failed during data preparation.")
		return
	
	_is_preview_mode = is_preview
	_current_chunk = Vector2i.ZERO

	if not _is_preview_mode:
		_num_chunks = chunk_division if enable_chunking else Vector2i.ONE
	
	_generation_state = GenState.PREPARING

func _prepare_common_data(apply_subdivision: bool) -> bool:
	if not heightmap:
		printerr("Cannot generate terrain: Heightmap texture is not set.")
		return false

	_clear_existing_terrain()

	_image = heightmap.get_image()
	if _image.is_empty():
		printerr("Generation failed: The provided texture has no image data.")
		return false

	if apply_subdivision and subdivision_level > 1:
		var old_dims = _image.get_size()
		var new_dims = (old_dims - Vector2i.ONE) * subdivision_level + Vector2i.ONE
		print("Subdividing heightmap from %dx%d to %dx%d..." % [old_dims.x, old_dims.y, new_dims.x, new_dims.y])
		_image.resize(new_dims.x, new_dims.y, Image.INTERPOLATE_BILINEAR)

	_gradient_image = null
	if color_gradient:
		var grad_img = color_gradient.get_image()
		if grad_img and grad_img.is_compressed(): grad_img.decompress()
		_gradient_image = grad_img
	
	_total_operations = 0
	_detail_instance_transforms.clear()
	return true

# --- Unified Generation Steps ---

func _prepare_generation_step() -> void:
	if _is_preview_mode:
		print("Preparing preview...")
		_preview_dims = _image.get_size()
	else:
		var img_w = _image.get_width()
		var img_h = _image.get_height()
		var base_chunk_size = (Vector2(img_w, img_h) - Vector2.ONE) / Vector2(_num_chunks)
		
		_chunk_pixel_offset.x = floori(_current_chunk.x * base_chunk_size.x)
		_chunk_pixel_offset.y = floori(_current_chunk.y * base_chunk_size.y)
		
		var end_pixel_x = floori((_current_chunk.x + 1) * base_chunk_size.x)
		var end_pixel_y = floori((_current_chunk.y + 1) * base_chunk_size.y)
		
		if _current_chunk.x == _num_chunks.x - 1: end_pixel_x = img_w - 1
		if _current_chunk.y == _num_chunks.y - 1: end_pixel_y = img_h - 1
			
		_current_chunk_dims.x = (end_pixel_x - _chunk_pixel_offset.x) + 1
		_current_chunk_dims.y = (end_pixel_y - _chunk_pixel_offset.y) + 1
		
		if _current_chunk_dims.x <= 1 or _current_chunk_dims.y <= 1:
			_finish_all_generations()
			return
		
		print("Generating chunk (%d, %d) with dimensions %s" % [_current_chunk.x, _current_chunk.y, _current_chunk_dims])
		
		if collision_type == CollisionType.HEIGHTMAP:
			_height_data = PackedFloat32Array()
			_height_data.resize(_current_chunk_dims.x * _current_chunk_dims.y)
			
	_progress_x = 0
	_progress_z = 0
	_surface_tool = SurfaceTool.new()
	_surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_generation_state = GenState.GENERATING_VERTICES

func _process_geometry_vertices() -> void:
	# Determine context based on generation mode
	var dims = _preview_dims if _is_preview_mode else _current_chunk_dims
	var world_size = preview_size if _is_preview_mode else terrain_size / Vector2(_num_chunks)
	var height_mult = preview_height if _is_preview_mode else terrain_height
	var pixel_offset = Vector2i.ZERO if _is_preview_mode else _chunk_pixel_offset

	for _i in range(operations_per_frame):
		if _progress_z >= dims.y:
			_progress_x = 0; _progress_z = 0
			_generation_state = GenState.GENERATING_INDICES; return
			
		var img_x = pixel_offset.x + _progress_x
		var img_z = pixel_offset.y + _progress_z
		
		var vx: float = remap(_progress_x, 0, dims.x - 1, -world_size.x / 2.0, world_size.x / 2.0)
		var vz: float = remap(_progress_z, 0, dims.y - 1, -world_size.y / 2.0, world_size.y / 2.0)
		var vy: float = _get_height_from_image(img_x, img_z, height_mult)
		
		if not _is_preview_mode and collision_type == CollisionType.HEIGHTMAP:
			_height_data[_progress_z * dims.x + _progress_x] = vy
		
		if _gradient_image:
			var normalized_height = clampf(vy / height_mult, 0.0, 1.0) if height_mult > 0.001 else 0.0
			var sample_x = int(normalized_height * (_gradient_image.get_width() - 1))
			_surface_tool.set_color(_gradient_image.get_pixel(sample_x, 0))
		
		_surface_tool.set_uv(Vector2(float(img_x) / (_image.get_width() - 1), float(img_z) / (_image.get_height() - 1)))
		_surface_tool.add_vertex(Vector3(vx, vy, vz))
		
		_total_operations += 1
		if enable_kill_switch and _total_operations > max_operations_limit:
			_cancel_generation("Exceeded maximum operations limit."); return
		
		_progress_x += 1
		if _progress_x >= dims.x: _progress_x = 0; _progress_z += 1

func _process_geometry_indices() -> void:
	var dims = _preview_dims if _is_preview_mode else _current_chunk_dims
	
	for _i in range(operations_per_frame / 6):
		if _progress_z >= dims.y - 1:
			_progress_x = 0; _progress_z = 0
			_generation_state = GenState.GENERATING_DETAILS; return

		var top_left: int = _progress_z * dims.x + _progress_x
		var top_right: int = top_left + 1
		var bottom_left: int = (_progress_z + 1) * dims.x + _progress_x
		var bottom_right: int = bottom_left + 1
		
		_surface_tool.add_index(top_left); _surface_tool.add_index(top_right); _surface_tool.add_index(bottom_left)
		_surface_tool.add_index(top_right); _surface_tool.add_index(bottom_right); _surface_tool.add_index(bottom_left)

		_progress_x += 1
		if _progress_x >= dims.x - 1: _progress_x = 0; _progress_z += 1

func _process_geometry_details() -> void:
	# Immediately exit if there's nothing to do.
	if detail_layers.is_empty():
		_generation_state = GenState.FINALIZING
		return

	# Determine the key for this chunk/preview to use in logs.
	var data_key = Vector2i(-1, -1) if _is_preview_mode else _current_chunk
	
	# === INITIAL STATE INFO ===
	# Announce the start only once per chunk, when progress is at the beginning.
	if _progress_x == 0 and _progress_z == 0:
		print("--- Starting detail placement for key: %s ---" % [data_key])

	# This will count points generated ONLY in this frame's execution.
	var points_generated_this_frame := 0
	
	# Determine context based on generation mode
	var dims = _preview_dims if _is_preview_mode else _current_chunk_dims
	var world_size = preview_size if _is_preview_mode else terrain_size / Vector2(_num_chunks)
	var height_mult = preview_height if _is_preview_mode else terrain_height
	var pixel_offset = Vector2i.ZERO if _is_preview_mode else _chunk_pixel_offset
	var detail_world_size = preview_size if _is_preview_mode else world_size

	# Initialize the dictionary for transforms if it's the first time for this chunk.
	if not _detail_instance_transforms.has(data_key):
		_detail_instance_transforms[data_key] = {}
		for i in range(detail_layers.size()):
			_detail_instance_transforms[data_key][i] = []

	# Main loop to process a batch of points.
	for _i in range(operations_per_frame):
		# Check if we've finished all the rows for this chunk.
		if _progress_z >= dims.y:
			_generation_state = GenState.FINALIZING
			
			# === END STATE INFO (Reason: All rows processed) ===
			print("--- Finished detail placement for key: %s. Generated a total of %d points this frame. ---" % [data_key, points_generated_this_frame])
			return
			
		var img_x = pixel_offset.x + _progress_x
		var img_z = pixel_offset.y + _progress_z
		var height = _get_height_from_image(img_x, img_z, height_mult)
		var normal = _get_normal_from_image(img_x, img_z, world_size, height_mult)
		var slope = rad_to_deg(normal.angle_to(Vector3.UP))
		
		# Iterate through each possible detail layer.
		for layer_idx in range(detail_layers.size()):
			var layer: DetailLayer = detail_layers[layer_idx]
			if not is_instance_valid(layer) or layer.meshes.is_empty():
				continue
				
			var can_place = height >= layer.min_height and height <= layer.max_height and \
							slope >= layer.min_slope_angle and slope <= layer.max_slope_angle
							
			# If rules and density check pass, create and store the point.
			if can_place and randf() < layer.density:
				var world_x: float = remap(_progress_x, 0, dims.x - 1, -detail_world_size.x / 2.0, detail_world_size.x / 2.0)
				var world_z: float = remap(_progress_z, 0, dims.y - 1, -detail_world_size.y / 2.0, detail_world_size.y / 2.0)
				var origin = Vector3(world_x, height, world_z)
				var basis: Basis
				
				if layer.align_with_normal:
					basis = Basis.looking_at(normal, Vector3.UP).inverse() if abs(normal.dot(Vector3.UP)) < 0.999 else Basis.IDENTITY
				else:
					basis = Basis.IDENTITY

				if layer.random_y_rotation: basis = basis.rotated(Vector3.UP, randf() * TAU)
				
				var scale_val = randf_range(layer.scale_range.x, layer.scale_range.y)
				var scale = Vector3.ONE * scale_val
				origin += normal * layer.vertical_offset
				
				var transform = Transform3D(basis.scaled(scale), origin)
				_detail_instance_transforms[data_key][layer_idx].append(transform)
				
				# === POINT GENERATED ===
				points_generated_this_frame += 1

		# Move to the next point in the grid.
		_progress_x += 1
		if _progress_x >= dims.x: 
			_progress_x = 0
			_progress_z += 1
	
	# === END STATE INFO (Reason: Operations limit reached for this frame) ===
	print("--- Pausing detail placement for key: %s. Generated %d points this frame. ---" % [data_key, points_generated_this_frame])

func _finalize_generation_step() -> void:
	print("Finalizing step...")
	_surface_tool.generate_normals()
	var mesh: ArrayMesh = _surface_tool.commit()
	var root_node: Node3D
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	
	if _gradient_image:
		var material = StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		mesh_instance.material_override = material

	if _is_preview_mode:
		mesh_instance.name = "FullTerrainPreview"
		root_node = mesh_instance
		add_child(root_node)
		_create_multimesh_instances(root_node, Vector2i(-1, -1))
		_finish_all_generations()
	else:
		var static_body := StaticBody3D.new()
		static_body.name = "TerrainBody_%d_%d" % [_current_chunk.x, _current_chunk.y]
		mesh_instance.name = "TerrainMeshInstance"
		static_body.add_child(mesh_instance)
		root_node = static_body
		add_child(root_node)
		
		_create_multimesh_instances(root_node, _current_chunk)
		
		if collision_type != CollisionType.NONE:
			var shape_3d: Shape3D
			if collision_type == CollisionType.TRIMESH:
				shape_3d = mesh.create_trimesh_shape()
			elif collision_type == CollisionType.HEIGHTMAP:
				var heightmap_shape := HeightMapShape3D.new()
				heightmap_shape.map_width = _current_chunk_dims.x
				heightmap_shape.map_depth = _current_chunk_dims.y
				heightmap_shape.map_data = _height_data
				shape_3d = heightmap_shape
			
			var collision_shape := CollisionShape3D.new()
			collision_shape.shape = shape_3d
			collision_shape.name = "TerrainCollisionShape"
			static_body.add_child(collision_shape)
		
		# Move to next chunk
		_current_chunk.x += 1
		if _current_chunk.x >= _num_chunks.x:
			_current_chunk.x = 0
			_current_chunk.y += 1
		
		if _current_chunk.y >= _num_chunks.y:
			_finish_all_generations()
		else:
			_generation_state = GenState.PREPARING

	if is_instance_valid(root_node):
		root_node.owner = get_tree().edited_scene_root

# --- Shared Logic & Cleanup ---

func _finish_all_generations():
	print("Generation complete.")
	_generation_state = GenState.IDLE
	_surface_tool = null; _image = null; _gradient_image = null

func _cancel_generation(reason: String) -> void:
	printerr("Generation cancelled: ", reason)
	_generation_state = GenState.IDLE
	_surface_tool = null; _image = null; _gradient_image = null

func _clear_existing_terrain() -> void:
	for child in get_children():
		if child.name.begins_with("TerrainBody_") or child.name == "FullTerrainPreview":
			child.queue_free()

func _bake_chunks() -> void:
	print("Baking terrain chunks to disk...")
	var data_dir = "res://terrain_data"
	
	if not DirAccess.dir_exists_absolute(data_dir):
		var err = DirAccess.make_dir_absolute(data_dir)
		if err == OK:
			print("Created directory: %s" % data_dir)
		else:
			printerr("Failed to create directory: %s. Error code: %s" % [data_dir, err])
			return

	var chunk_nodes = get_children().filter(func(c): return c.name.begins_with("TerrainBody_"))

	if chunk_nodes.is_empty():
		printerr("Bake failed: No generated terrain chunks found to bake.")
		return
		
	var manifest := {
		"terrain_size": [terrain_size.x, terrain_size.y],
		"terrain_height": terrain_height,
		"num_chunks": [_num_chunks.x, _num_chunks.y],
		"subdivision": subdivision_level,
		"has_material": color_gradient != null,
		"detail_layers_count": detail_layers.size()
	}
	var manifest_file = FileAccess.open(data_dir + "/manifest.json", FileAccess.WRITE)
	manifest_file.store_string(JSON.stringify(manifest, "\t"))
	manifest_file.close()
	print("Saved manifest.json")

	for chunk_node in chunk_nodes:
		var mesh_instance := chunk_node.get_node_or_null("TerrainMeshInstance") as MeshInstance3D
		var collision_shape := chunk_node.get_node_or_null("TerrainCollisionShape") as CollisionShape3D
		
		if not mesh_instance:
			printerr("Skipping %s: No MeshInstance3D found." % chunk_node.name)
			continue
			
		ResourceSaver.save(mesh_instance.mesh, "%s/%s.mesh" % [data_dir, chunk_node.name])
		
		if collision_shape:
			ResourceSaver.save(collision_shape.shape, "%s/%s.shape" % [data_dir, chunk_node.name])
		
		if mesh_instance.material_override:
			ResourceSaver.save(mesh_instance.material_override, "%s/%s.material" % [data_dir, chunk_node.name])
			
		for child in chunk_node.get_children():
			if child is MultiMeshInstance3D:
				var mmi = child as MultiMeshInstance3D
				ResourceSaver.save(mmi.multimesh, "%s/%s_%s.multimesh" % [data_dir, chunk_node.name, mmi.name])

	print("Bake complete! Chunks and details saved to %s" % data_dir)
	_clear_existing_terrain()

func _create_multimesh_instances(parent_node: Node, data_key: Vector2i) -> void:
	for layer_idx in _detail_instance_transforms[data_key]:
		print(len(_detail_instance_transforms[data_key][layer_idx]))
		return
		var layer: DetailLayer = _detail_instance_transforms[data_key][layer_idx]
		if not is_instance_valid(layer) or layer.meshes.is_empty():
			continue
		
		var mmi = MultiMeshInstance3D.new()
		mmi.name = "DetailLayer_%d" % layer_idx
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = layer.meshes.pick_random()
		mm.buffer = _pack_transforms_to_buffer(_detail_instance_transforms[data_key][layer_idx])
		
		mmi.multimesh = mm
		parent_node.add_child(mmi)

func _get_height_from_image(px: int, py: int, height_multiplier: float) -> float:
	if not _image: return 0.0
	return _image.get_pixel(clamp(px, 0, _image.get_width() - 1), clamp(py, 0, _image.get_height() - 1)).r * height_multiplier

func _get_normal_from_image(px: int, py: int, terrain_dims: Vector2, height_mult: float) -> Vector3:
	# Get height of neighboring pixels
	var h_l = _get_height_from_image(px - 1, py, height_mult)
	var h_r = _get_height_from_image(px + 1, py, height_mult)
	var h_d = _get_height_from_image(px, py - 1, height_mult)
	var h_u = _get_height_from_image(px, py + 1, height_mult)
	
	var world_pixel_width = terrain_dims.x / (_image.get_width() - 1) if _image.get_width() > 1 else 1.0
	
	# Compute normal using central differences
	var normal = Vector3()
	normal.x = h_l - h_r
	normal.y = 2.0 * world_pixel_width
	normal.z = h_d - h_u
	
	return normal.normalized()

func _pack_transforms_to_buffer(transforms: Array[Transform3D]) -> PackedFloat32Array:
	var buffer = PackedFloat32Array()
	buffer.resize(transforms.size() * 12)
	var i = 0
	for t in transforms:
		# This packs the transform basis in a transposed manner.
		# Preserved from original script to avoid logic changes.
		buffer[i+0] = t.basis.x.x; buffer[i+1] = t.basis.y.x; buffer[i+2] = t.basis.z.x; buffer[i+3] = t.origin.x
		buffer[i+4] = t.basis.x.y; buffer[i+5] = t.basis.y.y; buffer[i+6] = t.basis.z.y; buffer[i+7] = t.origin.y
		buffer[i+8] = t.basis.x.z; buffer[i+9] = t.basis.y.z; buffer[i+10] = t.basis.z.z; buffer[i+11] = t.origin.z
		i += 12
	return buffer
