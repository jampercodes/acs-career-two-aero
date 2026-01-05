extends Control
class_name CarListUI

@onready var car_list: ItemList          = $RootHBox/CarListContainer/CarListScrollContainer/CarList
@onready var category_list: ItemList     = $RootHBox/DataListContainer/DataListHContainer/CategoryPanel/CategoryList
@onready var value_list: ItemList        = $RootHBox/DataListContainer/DataListHContainer/ValuePanel/ValueListScrollContainer/ValueList
@onready var car_name_label: Label       = $RootHBox/DataListContainer/DataListHContainer/ValuePanel/CarNameLabel
@onready var preview_texrect: TextureRect = $RootHBox/DetailsContainer/PreviewTexture
@onready var root_hbox: HBoxContainer    = $RootHBox
@onready var specstext: RichTextLabel    = $RootHBox/DetailsContainer/specs
@onready var tune_button: Button         = $RootHBox/DetailsContainer/ModifyButton
@onready var custom_only_checkbox: CheckBox = $RootHBox/CarListContainer/FilterBar/CustomOnlyCheckBox

var all_cars: Array[Car] = []      # full list
var visible_cars: Array[Car] = []  # after filter
var current_car: Car = null
var _categories: Array[Node] = []
var show_only_custom := false

func _get_car_display_name(car: Car) -> String:
	if car.screen_name != "":
		return car.screen_name
	return str(car.name)
	
func _sort_car_by_display_name(a: Car, b: Car) -> bool:
	var name_a := _get_car_display_name(a)
	var name_b := _get_car_display_name(b)
	return name_a.nocasecmp_to(name_b) < 0

func _ready() -> void:
	category_list.item_selected.connect(_on_category_selected)
	car_list.item_selected.connect(_on_car_selected)
	custom_only_checkbox.toggled.connect(_on_custom_only_toggled)

func set_cars(car_array: Array[Car]) -> void:
	all_cars = car_array.duplicate()

	# Sort master list alphabetically
	all_cars.sort_custom(_sort_car_by_display_name)

	_refresh_visible_cars()

	# Auto-select first visible car
	if visible_cars.size() > 0:
		car_list.select(0)
		_on_car_selected(0)


func _refresh_visible_cars() -> void:
	# Clear all UI first
	car_list.clear()
	value_list.clear()
	category_list.clear()
	_categories.clear()
	
	visible_cars.clear()

	for car in all_cars:
		if show_only_custom and not car.is_custom:
			continue
		visible_cars.append(car)

	_populate_car_list()


func _populate_car_list() -> void:
	car_list.clear()

	for car in visible_cars:
		var display_name: String = _get_car_display_name(car)
		car_list.add_item(display_name)

	print("[CarTunerUI] Populated car list with %d cars (%d visible)" %
		[all_cars.size(), visible_cars.size()])

func _on_car_selected(index: int) -> void:
	if index < 0 or index >= visible_cars.size():
		return

	current_car = visible_cars[index]
	print("[CarTunerUI] Selected car: %s" % current_car.screen_name)
	_populate_from_car()

	if tune_button:
		if current_car.is_custom:
			tune_button.text = "Modify custom car"
		else:
			tune_button.text = "Make copy and modify car"

func set_car(c: Car) -> void:
	current_car = c
	_populate_from_car()

func _populate_from_car() -> void:
	var current_category = category_list.get_selected_items()
	if current_car == null:
		return

	var car := current_car
	var eng := car.get_node("Engine") as CarEngine
	var brakes := car.get_node_or_null("Brakes") as Brakes

	# Car name / title
	if car.screen_name != "":
		car_name_label.text = car.screen_name
	else:
		car_name_label.text = str(car.name)

	# Preview image from Car's child "Preview"
	_update_preview_texture()

	# Populate categories list
	category_list.clear()
	_categories.clear()

	# Root car category
	category_list.add_item("Car (car.ini)")
	_categories.append(car)

	# Child nodes with scripts
	for child in car.get_children():
		if typeof(child) != TYPE_OBJECT:
			continue
		if not child is Node:
			continue
		if child.name == "Preview":
			continue
		if child.get_script() == null:
			continue

		category_list.add_item(str(child.name))
		_categories.append(child)

	# Right-hand specs text
	specstext.text = ""
	specstext.text += "Power: %.0f bhp\n" % eng.estimated_hp
	specstext.text += "Weight: %.0f kg\n" % car.total_mass
	specstext.text += "P/W: %.2f hp/kg (%.0f hp/ton)\n" % [
		car.pw_ratio_hp_per_kg,
		car.pw_ratio_hp_per_ton
	]
	specstext.text += "Power index: %.1f / 10\n" % car.power_index
	specstext.text += "Braking index: %.1f / 10\n" % car.braking_index
	specstext.text += "Cornering index: %.1f / 10 (Aero: %.1f, Tyres: %.1f)\n" % [
		car.cornering_index,
		car.aero_cornering_index,
		car.tyre_cornering_index
	]
	specstext.text += "Total Performance index: %.1f / 10\n" % car.performance_index

	# Extra brake info
	if brakes != null:
		var brake_lines := brakes.get_summary_lines(car)
		if brake_lines.size() > 0:
			specstext.text += "\n"
			for line in brake_lines:
				specstext.text += "%s\n" % line

	# Select first category by default
	if current_category.size() > 0:
		if category_list.get_item_count() > 0:
			category_list.select(current_category.get(0))
			_on_category_selected(current_category.get(0))
	else:
		if category_list.get_item_count() > 0:
			category_list.select(0)
			_on_category_selected(0)


func _update_preview_texture() -> void:
	if current_car == null:
		preview_texrect.texture = null
		preview_texrect.queue_redraw()
		return
	
	var preview_node := current_car.get_node_or_null("Preview")
	if preview_node == null:
		preview_texrect.texture = null
		return
	
	var tex: Texture2D = null
	
	if preview_node is Sprite2D:
		tex = (preview_node as Sprite2D).texture
	elif preview_node is Sprite3D:
		tex = (preview_node as Sprite3D).texture
	elif preview_node is TextureRect:
		tex = (preview_node as TextureRect).texture
	
	if tex != null:
		preview_texrect.texture = tex
	else:
		preview_texrect.texture = null

func _on_category_selected(index: int) -> void:
	if index < 0 or index >= _categories.size():
		return
	
	var node := _categories[index]
	_populate_values_for_node(node)

func _populate_values_for_node(node: Node) -> void:
	value_list.clear()
	if node == null:
		return
	
	var props := node.get_property_list()
	for prop in props:
		var usage := int(prop.get("usage", 0))
		var prop_name := String(prop.get("name", ""))
		
		# Only script vars
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
			
		if prop_name.begins_with("_"):
			continue
		
		var value = node.get(prop_name)
		
		# Skip Node references
		if value is Node:
			continue
		
		# Handle arrays
		if value is Array:
			_add_array_items(prop_name, value)
			continue
		
		# Skip other Objects that aren't basic types
		if value is Object and not (value is Resource):
			# Check if it's an inner class instance
			if _is_inner_class_instance(value):
				_add_inner_class_items(prop_name, value)
				continue
			else:
				continue
		
		var value_str := _value_to_string(value)
		value_list.add_item("%s = %s" % [prop_name, value_str])

func _is_inner_class_instance(obj: Object) -> bool:
	# Check if an object is an inner class instance
	if obj is Node or obj is Resource:
		return false
	
	# Check if it has any script properties
	var props := obj.get_property_list()
	for prop in props:
		var usage := int(prop.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			return true
	
	return false

func _add_array_items(array_name: String, arr: Array) -> void:
	# Handle arrays
	if arr.is_empty():
		value_list.add_item("%s = []" % array_name)
		return
	
	# Check if array contains inner class instances
	var first_elem = arr[0]
	if first_elem is Object and _is_inner_class_instance(first_elem):
		# Add header for the array
		value_list.add_item("─── %s [%d items] ───" % [array_name, arr.size()])
		
		# Add each object's properties
		for i in range(arr.size()):
			var obj = arr[i]
			value_list.add_item("  [%d]" % i)
			_add_inner_class_items("", obj, "    ")
	else:
		# Regular array
		value_list.add_item("%s = %s" % [array_name, _value_to_string(arr)])

func _add_inner_class_items(thisclass_Name: String, obj: Object, indent: String = "  ") -> void:
	# Add properties of an inner class instance
	if thisclass_Name != "":
		value_list.add_item("─── %s ───" % thisclass_Name)
	
	var props := obj.get_property_list()
	for prop in props:
		var usage := int(prop.get("usage", 0))
		var prop_name := String(prop.get("name", ""))
		
		# Only script vars
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		
		if prop_name.begins_with("_"):
			continue
		
		var value = obj.get(prop_name)
		
		# Skip nested objects/nodes
		if value is Node or (value is Object and not (value is Resource)):
			continue
		
		var value_str := _value_to_string(value)
		value_list.add_item("%s%s = %s" % [indent, prop_name, value_str])

func _value_to_string(value) -> String:
	match typeof(value):
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4:
			return str(value)
		TYPE_FLOAT:
			return "%0.4f" % value
		TYPE_INT:
			return str(value)
		TYPE_STRING:
			return '"%s"' % value
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_ARRAY:
			# For nested arrays, show count
			if value is Array and value.size() > 10:
				return "[Array with %d items]" % value.size()
			return str(value)
		TYPE_DICTIONARY:
			return str(value)
		_:
			return str(value)


func _on_custom_only_toggled(pressed: bool) -> void:
	show_only_custom = pressed

	var previously_selected: Car = current_car

	_refresh_visible_cars()
	await get_tree().process_frame
	queue_redraw()
	root_hbox.queue_redraw()

	# If there are no cars at all after filtering
	if visible_cars.is_empty():
		# Clear selection and right-hand panel, but keep the UI alive
		car_list.unselect_all()
		current_car = null
		car_name_label.text = ""
		specstext.text = ""
		preview_texrect.texture = null
		return

	# Try to keep the same car selected if it’s still in the visible list
	if previously_selected != null:
		var idx := visible_cars.find(previously_selected)
		if idx != -1:
			car_list.select(idx)
			_on_car_selected(idx)
			return

	# Fallback: select the first visible car
	car_list.select(0)
	_on_car_selected(0)


func _on_modify_button_pressed() -> void:
	get_parent().switch_to_tuner(current_car)
