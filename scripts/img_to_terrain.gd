@tool
extends Node3D

# =============================================================================
#  CONFIGURATION
# =============================================================================
@export_group("Configuration", "config_")

## The image to use as a heightmap. Black is low, white is high.
@export var config_heightmap_texture: Texture2D


# =============================================================================
#  ACTIONS
# =============================================================================
@export_group("Actions")

## Click this to generate or regenerate the terrain.
@export var action_generate: bool = false:
	set(value):
		if value:
			_generate_terrain()
		action_generate = false # Reset to act like a button

## Click this to remove the generated terrain from the scene.
@export var action_clean: bool = false:
	set(value):
		if value:
			_clear_existing_terrain()
		action_clean = false # Reset to act like a button


# --- Core Functions ---

func _generate_terrain() -> void:
	if not Engine.is_editor_hint(): return
	
	if not config_heightmap_texture:
		push_warning("Cannot generate: Please assign a heightmap texture.")
		return

	print("Generating default terrain from heightmap...")

	# 1. Clear any old terrain first to prevent duplicates.
	_clear_existing_terrain()

	# 2. Create a default terrain node.
	var terrain := Terrain3D.new()
	terrain.name = "Terrain3D"
	add_child(terrain)
	terrain.owner = get_tree().edited_scene_root
	
	terrain.data_directory = "res://terrain_data"
	DirAccess.make_dir_absolute(terrain.data_directory)
	
	# 3. Import the heightmap image to define the terrain shape.
	var img: Image = config_heightmap_texture.get_image()
	var size_x = img.get_width()
	var size_z = img.get_height()
	var position = Vector3(-size_x / 2.0, 0, -size_z / 2.0)
	
	terrain.data.import_images([img, null, null], position, 0.0, 256.0)

	# 4. Enable collision.
	terrain.collision_enabled = true

	print("Terrain generation complete.")


func _clear_existing_terrain() -> void:
	if not Engine.is_editor_hint(): return
	
	var old_terrain = find_child("Terrain3D", false, false)
	if old_terrain:
		print("Removing existing terrain node.")
		old_terrain.call_deferred("queue_free")
