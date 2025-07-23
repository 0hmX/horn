# global_bus.gd (Final, Robust Version)
# Uses the engine's built-in signal system for maximum reliability.
# Set up as an AutoLoad (Singleton) named "EventBus".

extends Node

var enable_logging: bool = true

# Emits an event with an optional data payload (a Dictionary).
func emit_event(signal_name: String, data: Dictionary = {}):
	if enable_logging:
		var timestamp = Time.get_datetime_string_from_system(true)
		print("[%s] [EventBus] Emitting Event: '%s' with data: %s" % [timestamp, signal_name, str(data)])

	# --- THIS IS THE FIX ---
	# If a signal is emitted before anything has connected to it,
	# it won't exist yet. We create it here on-the-fly to prevent a crash.
	if not has_signal(signal_name):
		add_user_signal(signal_name)
		if enable_logging:
			var timestamp = Time.get_datetime_string_from_system(true)
			print("[%s] [EventBus] Created new signal on-the-fly during emit: '%s'" % [timestamp, signal_name])
	
	# Now that we know the signal exists, we can safely emit it.
	emit_signal(signal_name, data)


# Connects a callable to a specific signal on the event bus.
func connect_event(signal_name: String, callable: Callable):
	# If the signal doesn't exist on this node yet, create it dynamically.
	if not has_signal(signal_name):
		add_user_signal(signal_name)
		if enable_logging:
			var timestamp = Time.get_datetime_string_from_system(true)
			print("[%s] [EventBus] Created new signal: '%s'" % [timestamp, signal_name])
	
	# Use the engine's built-in connect method.
	if not is_connected(signal_name, callable):
		connect(signal_name, callable)
		if enable_logging:
			var timestamp = Time.get_datetime_string_from_system(true)
			var target_script = callable.get_object().get_script().resource_path if callable.get_object().get_script() else "Built-in Node"
			var target_method = callable.get_method()
			print("[%s] [EventBus] Connected listener: '%s' -> '%s' to event '%s'" % [timestamp, target_script, target_method, signal_name])


# Disconnects a callable from a specific signal on the event bus.
func disconnect_event(signal_name: String, callable: Callable):
	if is_connected(signal_name, callable):
		disconnect(signal_name, callable)
		if enable_logging:
			var timestamp = Time.get_datetime_string_from_system(true)
			var target_script = callable.get_object().get_script().resource_path if callable.get_object().get_script() else "Built-in Node"
			var target_method = callable.get_method()
			print("[%s] [EventBus] Disconnected listener: '%s' -> '%s' from event '%s'" % [timestamp, target_script, target_method, signal_name])
