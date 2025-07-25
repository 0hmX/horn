@tool
extends Node3D

@export var use_image_heightmap: bool = false
@export var image_heightmap_path: Texture2D
@export_tool_button("Generate") var terrain = generate

# --- NEW: Water Properties ---
@export_group("Water")
@export var add_water: bool = true
@export var water_level: float = 25.0
# --- END NEW ---

func generate() -> void:
	var old_terrain = find_child("Terrain3D")
	if old_terrain:
		old_terrain.queue_free()

	# --- NEW: Remove old water plane on regeneration ---
	var old_water = find_child("WaterPlane")
	if old_water:
		old_water.queue_free()
	# --- END NEW ---

	var terrain : Terrain3D = await create_terrain()

	# --- NEW: Create the water plane after the terrain is made ---
	if add_water:
		create_water()
	# --- END NEW ---

func create_terrain() -> Terrain3D:
	var green_gr := Gradient.new()
	green_gr.set_color(0, Color.from_hsv(100./360., .35, .3))
	green_gr.set_color(1, Color.from_hsv(120./360., .4, .37))
	var green_ta: Terrain3DTextureAsset = await create_texture_asset("Grass", green_gr, 1024)
	green_ta.uv_scale = 0.1
	green_ta.detiling_rotation = 0.1

	var brown_gr := Gradient.new()
	brown_gr.set_color(0, Color.from_hsv(30./360., .4, .3))
	brown_gr.set_color(1, Color.from_hsv(30./360., .4, .4))
	var brown_ta: Terrain3DTextureAsset = await create_texture_asset("Dirt", brown_gr, 1024)
	brown_ta.uv_scale = 0.03
	green_ta.detiling_rotation = 0.1

	var grass_ma: Terrain3DMeshAsset = create_mesh_asset("Grass", Color.from_hsv(120./360., .4, .37))

	var terrain := Terrain3D.new()
	terrain.name = "Terrain3D"
	add_child(terrain, true)
	terrain.owner = get_tree().edited_scene_root

	terrain.material.world_background = Terrain3DMaterial.NONE
	terrain.material.auto_shader = true
	terrain.material.set_shader_param("auto_slope", 10)
	terrain.material.set_shader_param("blend_sharpness", .975)
	terrain.assets = Terrain3DAssets.new()
	terrain.assets.set_texture(0, green_ta)
	terrain.assets.set_texture(1, brown_ta)
	terrain.assets.set_mesh_asset(0, grass_ma)

	var img: Image
	if use_image_heightmap:
		var tex := image_heightmap_path
		var src_img := tex.get_image()
		var width := src_img.get_width()
		var height := src_img.get_height()

		var min_val := 1.0
		var max_val := 0.0

		for x in width:
			for y in height:
				var val = src_img.get_pixel(x, y).r
				if val < min_val:
					min_val = val
				if val > max_val:
					max_val = val

		var range := max_val - min_val
		if range == 0.0:
			range = 1.0

		#img = Image.create_empty(width, height, false, Image.FORMAT_RF)
		#for x in width:
			#for y in height:
				#var val = src_img.get_pixel(x, y).r
				#var normalized = (val - min_val) / range
				#img.set_pixel(x, y, Color(normalized, 0, 0, 1.0))
		#print("save")
		#img.save_png("res://ankan.png")
		terrain.region_size = 64
		terrain.data.import_images([src_img, null, null], Vector3(-1024, 0, -1024), 0.0, 150.0)

	var xforms: Array[Transform3D]
	var width: int = 100
	var step: int = 2
	for x in range(0, width, step):
		for z in range(0, width, step):
			var pos := Vector3(x, 0, z) - Vector3(width, 0, width) * .5
			pos.y = terrain.data.get_height(pos)
			xforms.push_back(Transform3D(Basis(), pos))
	terrain.instancer.add_transforms(0, xforms)

	return terrain


# --- NEW: Function to create the water plane ---
func create_water() -> void:
	# 1. Create the Mesh node for the water
	var water_plane := MeshInstance3D.new()
	water_plane.name = "WaterPlane"

	# 2. Define its shape with a PlaneMesh
	var plane_mesh := PlaneMesh.new()
	# Make the plane large enough to cover the terrain area
	plane_mesh.size = Vector2(4096, 4096)
	water_plane.mesh = plane_mesh

	# 3. Create a water material
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(0.1, 0.3, 0.5, 0.75)
	water_material.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA

	# Add some metallic/roughness for specular reflections from the sky/sun
	water_material.metallic = 0.2
	water_material.roughness = 0.1

	# Use noise to create a moving ripple effect on the surface
	var fnl := FastNoiseLite.new()
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.frequency = 0.05
	var noise_tex := NoiseTexture2D.new()
	noise_tex.width = 512
	noise_tex.height = 512
	noise_tex.seamless = true
	noise_tex.as_normal_map = true # Generate a normal map from the noise
	noise_tex.noise = fnl

	water_material.normal_enabled = true
	water_material.normal_texture = noise_tex
	water_material.normal_scale = 0.1 # Adjust strength of ripples

	water_plane.material_override = water_material

	# 4. Position the water at the specified height
	water_plane.position = Vector3(0, water_level, 0)

	# 5. Add to the scene and set owner to save it
	add_child(water_plane, true)
	water_plane.owner = get_tree().edited_scene_root
# --- END NEW ---


func create_texture_asset(asset_name: String, gradient: Gradient, texture_size: int = 512) -> Terrain3DTextureAsset:
	var fnl := FastNoiseLite.new()
	fnl.frequency = 0.004

	var alb_noise_tex := NoiseTexture2D.new()
	alb_noise_tex.width = texture_size
	alb_noise_tex.height = texture_size
	alb_noise_tex.seamless = true
	alb_noise_tex.noise = fnl
	alb_noise_tex.color_ramp = gradient
	await alb_noise_tex.changed
	var alb_noise_img: Image = alb_noise_tex.get_image()

	for x in alb_noise_img.get_width():
		for y in alb_noise_img.get_height():
			var clr: Color = alb_noise_img.get_pixel(x, y)
			clr.a = clr.v
			alb_noise_img.set_pixel(x, y, clr)
	alb_noise_img.generate_mipmaps()
	var albedo := ImageTexture.create_from_image(alb_noise_img)

	var nrm_noise_tex := NoiseTexture2D.new()
	nrm_noise_tex.width = texture_size
	nrm_noise_tex.height = texture_size
	nrm_noise_tex.as_normal_map = true
	nrm_noise_tex.seamless = true
	nrm_noise_tex.noise = fnl
	await nrm_noise_tex.changed
	var nrm_noise_img = nrm_noise_tex.get_image()
	for x in nrm_noise_img.get_width():
		for y in nrm_noise_img.get_height():
			var normal_rgh: Color = nrm_noise_img.get_pixel(x, y)
			normal_rgh.a = 0.8
			nrm_noise_img.set_pixel(x, y, normal_rgh)
	nrm_noise_img.generate_mipmaps()
	var normal := ImageTexture.create_from_image(nrm_noise_img)

	var ta := Terrain3DTextureAsset.new()
	ta.name = asset_name
	ta.albedo_texture = albedo
	ta.normal_texture = normal
	return ta

func create_mesh_asset(asset_name: String, color: Color) -> Terrain3DMeshAsset:
	var ma := Terrain3DMeshAsset.new()
	ma.name = asset_name
	ma.generated_type = Terrain3DMeshAsset.TYPE_TEXTURE_CARD
	ma.material_override.albedo_color = color
	return ma
