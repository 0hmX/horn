@tool
extends Node

var _listeners: Dictionary = {}

func subscribe(event_name: String, callable: Callable) -> void:
	if not callable.is_valid():
		push_warning("BusEvent: Attempted to subscribe with an invalid Callable.")
		return

	if not _listeners.has(event_name):
		_listeners[event_name] = []

	if not _listeners[event_name].has(callable):
		_listeners[event_name].append(callable)

func unsubscribe(event_name: String, callable: Callable) -> void:
	if _listeners.has(event_name):
		_listeners[event_name].erase(callable)

func publish(event_name: String, payload: Dictionary = {}) -> void:
	if not _listeners.has(event_name):
		return

	var listeners_for_event: Array = _listeners[event_name]
	
	for i in range(listeners_for_event.size() - 1, -1, -1):
		var callable: Callable = listeners_for_event[i]
		
		if callable.is_valid():
			callable.call(payload)
		else:
			listeners_for_event.remove_at(i)
