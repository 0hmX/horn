extends Control

@export var target: Node
@export var player: PackedScene

var net := ENetMultiplayerPeer.new()
var port := 25565

func  _ready() -> void:
	multiplayer.peer_connected.connect(func(pid):
		print("peer connected "+ str(pid) + " "+ str(multiplayer.is_server()))
		if multiplayer.is_server():
			add_player(pid)
	)

func add_player(name):
	var player_inst := player.instantiate()
	player_inst.name = str(name)
	player_inst.position = Vector3(0, 10, 0)
	target.call_deferred("add_child",player_inst, true)
	print_debug({
		"name": str(name),
		"position": player_inst.position,
	})

func _on_join_pressed() -> void:
	net.create_client("localhost",port)
	multiplayer.multiplayer_peer = net
	visible = false

func _on_create_pressed() -> void:
	net.create_server(port)
	multiplayer.multiplayer_peer = net
	add_player(multiplayer.get_unique_id())
	visible = false
