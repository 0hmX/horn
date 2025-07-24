extends Terrain3D

func _ready() -> void:
	SuperState.terrain_ref = self
	Bus.publish("terrain_ready")
