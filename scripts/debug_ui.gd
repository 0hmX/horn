# DebugUI.gd (Final EventBus Version)
# A standalone, extensible UI for displaying real-time debug information.
# Listens for the "register_debug_item" event and expects a Dictionary payload.
@tool
extends VBoxContainer

## How often the UI text updates, in seconds.
@export var update_interval: float = 0.25

# A dictionary to hold the UI labels and their data sources.
var _debug_items: Dictionary = {}

func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = update_interval
	timer.timeout.connect(_update_all_items)
	add_child(timer)
	timer.start()

	# This call is correct and will work with the new EventBus
	EventBus.connect_event("register_debug_item", Callable(self, "add_debug_item"))
	
	var fps_data := { "label": "FPS", "provider": Callable(self, "_get_fps") }
	EventBus.emit_event("register_debug_item", fps_data)

func _exit_tree() -> void:
	EventBus.disconnect_event("register_debug_item", Callable(self, "add_debug_item"))


## Public method to add a new tracked value to the UI.
## This function now receives a single Dictionary as its payload from the EventBus.
func add_debug_item(item_data: Dictionary) -> void:
	# Extract the data from the dictionary payload.
	var label_text: String = item_data.get("label", "NO_LABEL")
	var data_provider: Callable = item_data.get("provider", Callable())

	if not data_provider.is_valid():
		printerr("DebugUI Error: The provided callable for '%s' is not valid." % label_text)
		return

	if _debug_items.has(label_text):
		printerr("DebugUI Error: Item '%s' already exists." % label_text)
		return

	var label_node := Label.new()
	label_node.text = label_text + ": ..." # Initial text
	add_child(label_node)

	_debug_items[label_text] = {
		"node": label_node,
		"provider": data_provider
	}


# This function is called by the Timer to refresh all displayed values.
func _update_all_items() -> void:
	for key in _debug_items.keys():
		var item = _debug_items[key]
		var label_node: Label = item["node"]
		var data_provider: Callable = item["provider"]

		if not is_instance_valid(data_provider.get_object()):
			_debug_items.erase(key)
			label_node.queue_free()
			continue

		var new_value = data_provider.call()

		var value_string: String
		if new_value is Vector3:
			value_string = "(%.1f, %.1f, %.1f)" % [new_value.x, new_value.y, new_value.z]
		elif new_value is Vector2i:
			value_string = "(%d, %d)" % [new_value.x, new_value.y]
		elif new_value is float:
			value_string = "%.2f" % new_value
		else:
			value_string = str(new_value)

		label_node.text = "%s: %s" % [key, value_string]


# The data provider for the FPS counter.
func _get_fps() -> int:
	return Performance.get_monitor(Performance.TIME_FPS)
