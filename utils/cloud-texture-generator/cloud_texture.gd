extends Node3D

@export var texture_size: int = 256
@export var save_path: String = "user://cloud_texture.png"

#@export_tool var generate_and_save: bool = false setget _on_generate_and_save

var cloud_texture: ImageTexture
var noise := FastNoiseLite.new()

func _ready():
	# Configure FastNoiseLite for nice smooth clouds
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.05        # Controls cloud size (lower = bigger)
	#noise.octaves = 4             # Number of noise layers for detail
	#noise.lacunarity = 2.0        # Frequency multiplier between octaves
	#noise.persistence = 0.5       # Amplitude decrease between octaves

	if cloud_texture == null:
		cloud_texture = ImageTexture.new()
		_generate_and_save_texture()

func _on_generate_and_save(value):
	if value:
		_generate_and_save_texture()
		#generate_and_save = false  # Reset button state

func _generate_and_save_texture():
	var img = Image.create(texture_size, texture_size, false, Image.FORMAT_R8)
	for y in texture_size:
		for x in texture_size:
			var nx = float(x) / texture_size
			var ny = float(y) / texture_size

			# Sample noise, returns -1..1
			var n = noise.get_noise_2d(nx, ny)

			# Normalize from [-1..1] to [0..1]
			n = (n + 1.0) * 0.5

			# Threshold noise to simulate cloud shapes
			var cloud_alpha = smoothstep(0.4, 0.7, n)

			img.set_pixel(x, y, Color(cloud_alpha, cloud_alpha, cloud_alpha, 1.0))
	var err = img.save_png(save_path)
	if err != OK:
		print("Failed to save cloud texture to ", save_path)

	cloud_texture.create_from_image(img)
	# Use `cloud_texture` in materials or sprites as needed
	# Example: $Sprite3D.texture = cloud_texture

func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
