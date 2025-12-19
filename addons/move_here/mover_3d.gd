@tool
extends EditorPlugin

const SETTING_PATH = "addons/move_here/modifier_key"
const DEFAULT_MODIFIER = 1 # 0: Alt, 1: Ctrl, 2: Shift, 3: Space

# Updated Enum to include Space
enum Modifier { ALT = 0, CTRL = 1, SHIFT = 2, SPACE = 3 }

func _enter_tree():
	var settings = get_editor_interface().get_editor_settings()
	if not settings.has_setting(SETTING_PATH):
		settings.set_setting(SETTING_PATH, DEFAULT_MODIFIER)
	
	var property_info = {
		"name": SETTING_PATH,
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		# Added Space to the dropdown list
		"hint_string": "Alt,Ctrl,Shift,Space"
	}
	settings.add_property_info(property_info)
	settings.set_initial_value(SETTING_PATH, DEFAULT_MODIFIER, true)

func _exit_tree():
	pass

func _handles(object):
	return object is Node3D

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not event is InputEventMouseButton:
		return AFTER_GUI_INPUT_PASS
	
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return AFTER_GUI_INPUT_PASS
		
	var settings = get_editor_interface().get_editor_settings()
	var modifier_setting = settings.get_setting(SETTING_PATH)
	
	var is_match = false
	
	# Check based on setting
	match modifier_setting:
		Modifier.ALT: is_match = event.alt_pressed
		Modifier.CTRL: is_match = event.ctrl_pressed
		Modifier.SHIFT: is_match = event.shift_pressed
		Modifier.SPACE: is_match = Input.is_key_pressed(KEY_SPACE)
		_: is_match = event.ctrl_pressed

	# Strict check to prevent conflicts
	if is_match:
		var alt = event.alt_pressed
		var ctrl = event.ctrl_pressed
		var shift = event.shift_pressed
		var space = Input.is_key_pressed(KEY_SPACE)
		
		match modifier_setting:
			Modifier.CTRL: if alt or shift or space: is_match = false
			Modifier.ALT:  if ctrl or shift or space: is_match = false
			Modifier.SHIFT: if ctrl or alt or space: is_match = false
			Modifier.SPACE: if ctrl or alt or shift: is_match = false

	if not is_match:
		return AFTER_GUI_INPUT_PASS

	if _move_selected_nodes_3d(camera, event):
		return AFTER_GUI_INPUT_STOP
	
	return AFTER_GUI_INPUT_PASS

func _move_selected_nodes_3d(camera: Camera3D, event: InputEventMouseButton) -> bool:
	var selection = get_editor_interface().get_selection().get_selected_nodes()
	if selection.is_empty():
		return false
		
	var target_position = Vector3.ZERO
	var hit_found = false
	
	var from = camera.project_ray_origin(event.position)
	var dir = camera.project_ray_normal(event.position)
	var to = from + dir * 10000.0
	
	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	
	var rid_excludes = []
	for node in selection:
		if node is CollisionObject3D:
			rid_excludes.append(node.get_rid())
	query.exclude = rid_excludes
	
	var result = space_state.intersect_ray(query)
	
	if not result.is_empty():
		target_position = result.position
		hit_found = true
	else:
		var plane = Plane(Vector3.UP, 0)
		var intersection = plane.intersects_ray(from, dir)
		if intersection:
			target_position = intersection
			hit_found = true
		else:
			target_position = from + dir * 10.0
			hit_found = true

	if not hit_found:
		return false

	var undo_redo = get_undo_redo()
	undo_redo.create_action("Move 3D Node to Click")
	
	for node in selection:
		if node is Node3D:
			var final_pos = target_position
			var parent = node.get_parent()
			if parent and parent is Node3D:
				final_pos = parent.global_transform.inverse() * target_position
			
			undo_redo.add_do_property(node, "position", final_pos)
			undo_redo.add_undo_property(node, "position", node.position)
			
	undo_redo.commit_action()
	return true
