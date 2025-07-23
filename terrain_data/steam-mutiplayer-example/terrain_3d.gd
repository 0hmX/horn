extends Terrain3D


func _ready() -> void:
	Bus.publish("terrain_ready")
