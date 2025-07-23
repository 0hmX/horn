# DetailLayer.gd
# A resource that defines a layer of detail objects (e.g., trees, rocks, grass)
# to be placed on the terrain by the generator.
@tool
extends Resource
class_name DetailLayer


@export_group("Source Models")
## The 3D models to be randomly selected for this layer.
@export var meshes: Array[Mesh]

@export_group("Placement Rules")
## The chance for an object to spawn at any valid location.
## A value of 0.01 means a 1% chance per vertex.
@export_range(0.0, 1.0) var density: float = 0.01
## The minimum world height at which these objects can appear.
@export var min_height: float = -1000.0
## The maximum world height at which these objects can appear.
@export var max_height: float = 1000.0
## The minimum surface slope angle (in degrees) for placement.
## 0 is perfectly flat.
@export_range(0.0, 90.0) var min_slope_angle: float = 0.0
## The maximum surface slope angle (in degrees) for placement.
## 90 is a sheer cliff.
@export_range(0.0, 90.0) var max_slope_angle: float = 30.0


@export_group("Object Transform")
## The minimum and maximum random scale to apply to each instance.
@export var scale_range := Vector2(0.8, 1.2)
## A vertical offset to apply after placing the object on the surface.
## Use a small negative value to sink objects slightly into the ground.
@export var vertical_offset: float = 0.0
## If true, each instance will have a random rotation around its vertical axis.
@export var align_with_normal := true
## If true, each instance will have a random rotation around its vertical axis.
@export var random_y_rotation := true
