extends MultiplayerSpawner

@export var player:  PackedScene

func _ready() -> void:
	multiplayer.peer_connected.connect(add_player)

func add_player(name):
	if !multiplayer.is_server(): return
	var player_inst := player.instantiate()
	player_inst.name = str(name)
	player_inst.position = Vector3(0,200,0)
	get_node(spawn_path).call_deferred("add_child", player_inst)
