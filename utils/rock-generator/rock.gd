@tool
extends MeshInstance3D

@export_range(0.1, 10.0, 0.1) var radius: float = 1.0
@export_range(4, 128, 1) var subdivisions: int = 32
@export_range(0.0, 0.5, 0.01) var roughness: float = 0.15
@export_range(0.0, 1.0, 0.01) var detail_scale: float = 0.05

@export var noise: FastNoiseLite

func _ready() -> void:
	if noise == null:
		return
	generate_rock_mesh()

func generate_rock_mesh() -> void:
	var st = SurfaceTool.new()

	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var base_sphere = SphereMesh.new()
	base_sphere.radius = radius
	base_sphere.height = radius * 2.0
	base_sphere.radial_segments = subdivisions
	base_sphere.rings = subdivisions

	var arrays = base_sphere.get_mesh_arrays()
	var vertices = arrays[ArrayMesh.ARRAY_VERTEX]
	var normals = arrays[ArrayMesh.ARRAY_NORMAL]
	var uvs = arrays[ArrayMesh.ARRAY_TEX_UV]
	var indices = arrays[ArrayMesh.ARRAY_INDEX]

	for i in range(vertices.size()):
		var original_vertex = vertices[i]
		var original_normal = normals[i]
		var uv = uvs[i]

		# Use the exported noise object instead of creating a new one
		# The noise properties will now be set in the editor on the exported FastNoiseLite resource
		var noise_value = noise.get_noise_3d(original_vertex.x * detail_scale,
											 original_vertex.y * detail_scale,
											 original_vertex.z * detail_scale)
		var displacement_amount = (noise_value + 1.0) * 0.5 * roughness * radius

		var displaced_vertex = original_vertex + original_normal * displacement_amount

		st.set_uv(uv)
		st.set_normal(original_normal)
		st.add_vertex(displaced_vertex)

	for i in range(indices.size()):
		st.add_index(indices[i])

	var array_mesh = st.commit()

	self.mesh = array_mesh

	print("Generated rock mesh with radius: %s, subdivisions: %s, roughness: %s" % [radius, subdivisions, roughness])

func _set(property: StringName, value: Variant) -> bool:
	if property == "radius" or property == "subdivisions" or property == "roughness" or property == "detail_scale":
		if get(property) != value:
			set(property, value)
			if is_inside_tree():
				generate_rock_mesh()
			return true
	return false

@export_tool_button("Gen")
var _t = _ready
