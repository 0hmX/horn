@tool
extends Node3D

enum GenerationType { RECURSIVE, SPACE_COLONIZATION }

@export_group("Generator Settings")
@export var generation_type : GenerationType = GenerationType.SPACE_COLONIZATION
@export var random_seed : int = 0:
	set(value):
		random_seed = value
		generate_tree()
@export var generate_on_ready : bool = true
@export_tool_button("Generate")
var _t = generate_tree
@export var is_generating : bool = false:
	set(value):
		if value:
			generate_tree()

@export_group("Tree Shape")
@export var trunk_height : float = 1.0
@export var initial_branch_length : float = 2.0
@export var trunk_radius : float = 0.2
@export var radius_falloff : float = 0.8
@export var branch_segments : int = 8

@export_group("Recursive Algorithm")
@export_range(0, 90) var main_branch_angle : float = 30.0
@export_range(0, 90) var branch_angle_variance : float = 15.0
@export_range(0.5, 0.95) var branch_length_falloff : float = 0.8
@export_range(1, 5) var max_recursion_depth : int = 4

@export_group("Space Colonization Algorithm")
@export_range(100, 2000) var attraction_points_count : int = 500
@export_range(1.0, 10.0) var attraction_volume_size : float = 5.0
@export_range(0.5, 5.0) var attraction_range : float = 2.0
@export_range(0.2, 2.0) var kill_range : float = 1.0
@export_range(5, 50) var max_growth_iterations : int = 25

var rng = RandomNumberGenerator.new()
var mesh_instance : MeshInstance3D

class Branch:
	var parent : Branch
	var position : Vector3
	var direction : Vector3
	var original_direction : Vector3
	var growth_count : int = 0
	var children : Array[Branch] = []

	func _init(p_parent, p_pos, p_dir):
		self.parent = p_parent
		self.position = p_pos
		self.direction = p_dir
		self.original_direction = p_dir

func _ready():
	if Engine.is_editor_hint():
		return
	if generate_on_ready:
		generate_tree()

func generate_tree():
	rng.seed = random_seed
	
	if is_instance_valid(mesh_instance):
		mesh_instance.queue_free()

	var branches : Array[Branch]
	if generation_type == GenerationType.RECURSIVE:
		branches = _generate_recursive_skeleton()
	else:
		branches = _generate_colonization_skeleton()

	if branches.is_empty():
		return

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var radius_map = {}
	for branch in branches:
		var current = branch
		var radius = trunk_radius
		while current.parent:
			radius *= radius_falloff
			current = current.parent
		radius_map[branch] = radius

	for branch in branches:
		if branch.parent:
			var start_pos = branch.parent.position
			var end_pos = branch.position
			var start_radius = radius_map[branch.parent] if branch.parent in radius_map else trunk_radius
			var end_radius = radius_map[branch]
			_create_cylinder(st, start_pos, end_pos, start_radius, end_radius)

	if st.get_vertex_count() == 0:
		return

	st.generate_normals()
	var mesh = st.commit()

	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	add_child(mesh_instance)

func _generate_recursive_skeleton() -> Array[Branch]:
	var branches : Array[Branch] = []
	var root_branch = Branch.new(null, Vector3.ZERO, Vector3.UP)
	branches.append(root_branch)

	var first_branch_pos = Vector3.UP * trunk_height
	var trunk_child = Branch.new(root_branch, first_branch_pos, Vector3.UP)
	root_branch.children.append(trunk_child)
	branches.append(trunk_child)

	_recursive_branch(trunk_child, max_recursion_depth, branches)
	return branches

func _recursive_branch(parent_branch: Branch, depth: int, branches: Array[Branch]):
	if depth <= 0:
		return

	var base_dir = parent_branch.direction
	var branch_length = initial_branch_length * pow(branch_length_falloff, max_recursion_depth - depth)

	var a_dir = base_dir.rotated(Vector3.FORWARD, deg_to_rad(main_branch_angle + rng.randf_range(-branch_angle_variance, branch_angle_variance)))
	a_dir = a_dir.rotated(Vector3.UP, rng.randf_range(0, TAU))
	var branch_a = Branch.new(parent_branch, parent_branch.position + a_dir * branch_length, a_dir)
	parent_branch.children.append(branch_a)
	branches.append(branch_a)
	_recursive_branch(branch_a, depth - 1, branches)

	var b_dir = base_dir.rotated(Vector3.FORWARD, deg_to_rad(-main_branch_angle + rng.randf_range(-branch_angle_variance, branch_angle_variance)))
	b_dir = b_dir.rotated(Vector3.UP, rng.randf_range(0, TAU))
	var branch_b = Branch.new(parent_branch, parent_branch.position + b_dir * branch_length, b_dir)
	parent_branch.children.append(branch_b)
	branches.append(branch_b)
	_recursive_branch(branch_b, depth - 1, branches)

func _generate_colonization_skeleton() -> Array[Branch]:
	var attraction_nodes : Array[Vector3] = []
	var center = Vector3(0, trunk_height + attraction_volume_size / 2.0, 0)
	for i in range(attraction_points_count):
		var point = Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		).normalized() * attraction_volume_size / 2.0
		attraction_nodes.append(center + point)
	
	var root_branch = Branch.new(null, Vector3.ZERO, Vector3.UP)
	var tree_branches : Array[Branch] = [root_branch]
	var current_branch = root_branch
	
	var is_growing = true
	var iterations = 0
	while is_growing and iterations < max_growth_iterations:
		is_growing = false
		iterations += 1
		
		var i = attraction_nodes.size() - 1
		while i >= 0:
			var attraction_node = attraction_nodes[i]
			var closest_branch : Branch = null
			var closest_dist = INF
			
			for tree_branch in tree_branches:
				var dist = tree_branch.position.distance_to(attraction_node)
				if dist < kill_range:
					attraction_nodes.remove_at(i)
					break
				if dist < attraction_range and dist < closest_dist:
					closest_dist = dist
					closest_branch = tree_branch
			
			if closest_branch != null:
				var new_dir = (attraction_node - closest_branch.position).normalized()
				closest_branch.direction = (closest_branch.direction * closest_branch.growth_count + new_dir).normalized()
				closest_branch.growth_count += 1
			i -= 1

		var new_branches : Array[Branch] = []
		for tree_branch in tree_branches:
			if tree_branch.growth_count > 0:
				var new_dir = tree_branch.direction.normalized()
				var new_pos = tree_branch.position + new_dir * initial_branch_length
				var new_branch = Branch.new(tree_branch, new_pos, new_dir)
				new_branches.append(new_branch)
				tree_branch.children.append(new_branch)
				tree_branch.direction = tree_branch.original_direction
				tree_branch.growth_count = 0
				is_growing = true
		
		tree_branches.append_array(new_branches)

	var all_branches : Array[Branch] = [root_branch]
	var queue : Array[Branch] = [root_branch]
	var head = 0
	while head < queue.size():
		var current = queue[head]
		head += 1
		for child in current.children:
			all_branches.append(child)
			queue.append(child)
			
	return all_branches

func _create_cylinder(st: SurfaceTool, start_pos: Vector3, end_pos: Vector3, start_radius: float, end_radius: float):
	var direction = (end_pos - start_pos).normalized()
	var rotation : Quaternion

	if direction.is_equal_approx(Vector3.UP):
		rotation = Quaternion()
	elif direction.is_equal_approx(Vector3.DOWN):
		rotation = Quaternion(Vector3.RIGHT, PI)
	else:
		var basis = Basis().looking_at(direction)
		rotation = basis.get_rotation_quaternion()

	var start_idx = st.get_vertex_count()
	
	for i in range(branch_segments + 1):
		var angle = float(i) / branch_segments * TAU
		var x = cos(angle)
		var z = sin(angle)
		
		var top_vertex = Vector3(x * end_radius, 0, z * end_radius)
		st.add_vertex(end_pos + rotation * top_vertex)
		
		var bottom_vertex = Vector3(x * start_radius, 0, z * start_radius)
		st.add_vertex(start_pos + rotation * bottom_vertex)

	for i in range(branch_segments):
		var current_top = start_idx + i * 2
		var current_bottom = start_idx + i * 2 + 1
		var next_top = start_idx + (i + 1) * 2
		var next_bottom = start_idx + (i + 1) * 2 + 1

		st.add_index(current_bottom)
		st.add_index(next_bottom)
		st.add_index(current_top)
		
		st.add_index(current_top)
		st.add_index(next_bottom)
		st.add_index(next_top)

	var top_center_idx = st.get_vertex_count()
	st.add_vertex(end_pos)
	for i in range(branch_segments):
		st.add_index(top_center_idx)
		st.add_index(start_idx + i * 2)
		st.add_index(start_idx + (i + 1) * 2)

	var bottom_center_idx = st.get_vertex_count()
	st.add_vertex(start_pos)
	for i in range(branch_segments):
		st.add_index(bottom_center_idx)
		st.add_index(start_idx + (i + 1) * 2 + 1)
		st.add_index(start_idx + i * 2 + 1)
