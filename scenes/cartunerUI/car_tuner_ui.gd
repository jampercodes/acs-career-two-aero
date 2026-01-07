extends MarginContainer
class_name CarTunerUI

@onready var category_list: ItemList      = $MainLayout/ContentRow/LeftColumn/CategoryPanel/CategoryScroll/CategoryList
@onready var parts_list: ItemList         = $MainLayout/ContentRow/LeftColumn/PartsSection/PartsPanel/PartsScroll/PartsList
@onready var value_list: ItemList         = $MainLayout/ContentRow/MiddleColumn/StatsPanel/StatsScroll/StatsList
@onready var car_name_label: Label        = $MainLayout/HeaderPanel/HeaderRow/OverviewHeader
@onready var preview_texrect: TextureRect = $MainLayout/ContentRow/RightColumn/PreviewPanel/CarPreview
@onready var specstext: RichTextLabel = $MainLayout/ContentRow/RightColumn/OverviewPanel/SpecsOverview
@onready var stat_changes: RichTextLabel = $MainLayout/ContentRow/MiddleColumn/ChangesPanel/StatChanges
@onready var cost_label: RichTextLabel = $MainLayout/ContentRow/MiddleColumn/CostPanel/CostLabel
@onready var purchase_button: Button = $MainLayout/ContentRow/MiddleColumn/PurchaseButton
@onready var finalize_button: Button = $MainLayout/ContentRow/MiddleColumn/FinalizeButton
@onready var back_button: Button = $MainLayout/HeaderPanel/HeaderRow/BackButton
@onready var delete_button: Button = $MainLayout/HeaderPanel/HeaderRow/DeleteButton
@onready var remove_button: Button = $MainLayout/ContentRow/MiddleColumn/RemoveButton

var _engine_swap_popup: PopupPanel = null
var _engine_swap_list: ItemList = null
var _engine_swap_confirm: Button = null
var _selected_swap_car: Car = null

var current_car: Car = null
var _categories: Array[Node] = []
var current_modified_car : Car = null
var car_has_modifications: bool = false

# For tracking selected upgrade
var _selected_upgrade: Dictionary = {}
var _current_category_node: Node = null

func _ready() -> void:
	category_list.item_selected.connect(_on_category_selected)
	parts_list.item_selected.connect(_on_part_selected)
	purchase_button.pressed.connect(_on_purchase_pressed)
	finalize_button.pressed.connect(_on_finalize_pressed)
	back_button.pressed.connect(_on_back_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	remove_button.pressed.connect(_on_remove_pressed)
	# Initialize UI
	stat_changes.text = ""
	cost_label.text = ""
	purchase_button.disabled = true
	finalize_button.disabled = true
	remove_button.disabled = true 
	_setup_engine_swap_popup() 
	
func _setup_engine_swap_popup() -> void:
	# Create popup panel
	_engine_swap_popup = PopupPanel.new()
	_engine_swap_popup.title = "Select Engine Donor Car"
	_engine_swap_popup.size = Vector2(600, 400)
	add_child(_engine_swap_popup)
	
	# Create VBox layout
	var vbox = VBoxContainer.new()
	_engine_swap_popup.add_child(vbox)
	
	var label = Label.new()
	label.text = "Choose a car to swap engine from:"
	vbox.add_child(label)
	
	# Create item list for cars
	_engine_swap_list = ItemList.new()
	_engine_swap_list.custom_minimum_size = Vector2(0, 300)
	_engine_swap_list.item_selected.connect(_on_engine_swap_car_selected)
	vbox.add_child(_engine_swap_list)
	
	# Create button row
	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_engine_swap_cancel)
	hbox.add_child(cancel_btn)
	
	_engine_swap_confirm = Button.new()
	_engine_swap_confirm.text = "Confirm Swap"
	_engine_swap_confirm.disabled = true
	_engine_swap_confirm.pressed.connect(_on_engine_swap_confirm)
	hbox.add_child(_engine_swap_confirm)

func set_car(c: Car) -> void:
	current_car = c
	current_modified_car = current_car.duplicate()
	car_has_modifications = false
	finalize_button.disabled = true
	_populate_from_car()

func _populate_from_car() -> void:
	var current_category = category_list.get_selected_items()
	if current_car == null:
		return

	var car := current_car
	var eng := car.get_node("Engine") as CarEngine
	var brakes := car.get_node_or_null("Brakes") as Brakes
	var generalupgrades := car.get_node_or_null("GeneralUpgrades") as GeneralUpgrades
	if generalupgrades != null:
		var weight_lines := generalupgrades.get_summary_lines()
		if weight_lines.size() > 0:
			specstext.text += "\n"
			for line in weight_lines:
				specstext.text += "%s\n" % line
	# Car name / title
	if car.screen_name != "":
		car_name_label.text = car.screen_name
	else:
		car_name_label.text = str(car.name)

	# Preview
	_update_preview_texture()

	# Categories
	category_list.clear()
	_categories.clear()

	category_list.add_item("Car (car.ini)")
	_categories.append(car)

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
	# Engine summary 
	if eng != null and eng.has_method("get_summary_lines"):
		var engine_lines := eng.get_summary_lines()
		if engine_lines.size() > 0:
			specstext.text += "\n"
			for line in engine_lines:
				specstext.text += "%s\n" % line

	if brakes != null:
		var brake_lines := brakes.get_summary_lines(car)
		if brake_lines.size() > 0:
			specstext.text += "\n"
			for line in brake_lines:
				specstext.text += "%s\n" % line

	# Keep previous category selected if possible
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
		return

	# Load only for the selected car (downscaled)
	var tex := current_car.get_preview_texture(1024)
	preview_texrect.texture = tex

func _on_category_selected(index: int) -> void:
	if index < 0 or index >= _categories.size():
		return
	
	var node := _categories[index]
	_current_category_node = node
	
	_selected_upgrade = {}
	stat_changes.text = ""
	cost_label.text = ""
	purchase_button.disabled = true
	remove_button.disabled = true
	
	_populate_values_for_node(node)
	_populate_parts_for_node(node)

func _populate_parts_for_node(node: Node) -> void:
	parts_list.clear()
	remove_button.disabled = true
	
	if node is Aero:
		var aero := node as Aero
		var upgrades := aero.get_all_upgrade_options()

		# Group by stage
		var by_stage: Dictionary = {1: [], 2: [], 3: []}
		for upgrade in upgrades:
			var stage: int = upgrade.get("stage", 1)
			if by_stage.has(stage):
				by_stage[stage].append(upgrade)
		
		# Display parts organized by stage
		for stage in [1, 2, 3]:
			if by_stage[stage].is_empty():
				continue
			
			parts_list.add_item("─── STAGE %d ───" % stage)
			parts_list.set_item_disabled(parts_list.get_item_count() - 1, true)
			
			for upgrade in by_stage[stage]:
				var display_text: String = upgrade["display_name"]
				display_text += " - $%d" % upgrade["cost"]
				
				parts_list.add_item(display_text)
				parts_list.set_item_metadata(parts_list.get_item_count() - 1, upgrade)
		
		remove_button.disabled = true
		return

	if node is Brakes:
		var brakes := node as Brakes
		var upgrades := brakes.get_all_upgrade_options()
		
		# Group by stage
		var by_stage: Dictionary = {1: [], 2: [], 3: []}
		for upgrade in upgrades:
			var stage: int = upgrade.get("stage", 1)
			if by_stage.has(stage):
				by_stage[stage].append(upgrade)
		
		# Display parts organized by stage
		for stage in [1, 2, 3]:
			if by_stage[stage].is_empty():
				continue
			
			parts_list.add_item("─── STAGE %d ───" % stage)
			parts_list.set_item_disabled(parts_list.get_item_count() - 1, true)
			
			for upgrade in by_stage[stage]:
				var display_text: String = upgrade["display_name"]
				display_text += " - $%d" % upgrade["cost"]
				
				parts_list.add_item(display_text)
				parts_list.set_item_metadata(parts_list.get_item_count() - 1, upgrade)
		
		remove_button.disabled = not brakes.can_remove_upgrades()
		return
	
	# Engine upgrades (part-based system)
	if node is CarEngine:
		var engine := node as CarEngine
		
		# ENGINE SWAP option first
		parts_list.add_item("─── ENGINE SWAP ───")
		parts_list.set_item_disabled(parts_list.get_item_count() - 1, true)
		
		var swap_text := "Swap Engine from Another Car"
		if engine.is_swapped:
			swap_text = "(APPLIED) Swapped from: %s" % engine.swap_source_car_id
		parts_list.add_item(swap_text)
		parts_list.set_item_metadata(parts_list.get_item_count() - 1, {"is_engine_swap": true})
		
		parts_list.add_item("───────────────")
		parts_list.set_item_disabled(parts_list.get_item_count() - 1, true)
		
		# Add turbo options first if applicable
		if engine.can_add_turbo():
			var turbo_opts := engine.get_turbo_upgrade_options()
			
			if turbo_opts.size() > 0:
				parts_list.add_item("─── TURBO UPGRADES ───")
				parts_list.set_item_disabled(parts_list.get_item_count() - 1, true)
				
				for opt in turbo_opts:
					var display_text: String = opt["display_name"]
					display_text += " - $%d (+%.1f%%)" % [
						opt["cost"],
						(opt["mult"] - 1.0) * 100.0
					]
					
					parts_list.add_item(display_text)
					parts_list.set_item_metadata(parts_list.get_item_count() - 1, opt)
				
				parts_list.add_item("───────────────")
				parts_list.set_item_disabled(parts_list.get_item_count() - 1, true)
		
		# Regular engine upgrades
		var options := engine.get_all_upgrade_options()
		
		# Group by stage
		var by_stage: Dictionary = {1: [], 2: [], 3: []}
		for opt in options:
			var stage: int = opt.get("stage", 1)
			if by_stage.has(stage):
				by_stage[stage].append(opt)
		
		# Display by stage
		for stage in [1, 2, 3]:
			if by_stage[stage].is_empty():
				continue
			
			parts_list.add_item("─── STAGE %d ───" % stage)
			parts_list.set_item_disabled(parts_list.get_item_count() - 1, true)
			
			for opt in by_stage[stage]:
				var display_text: String = opt["display_name"]
				display_text += " - $%d (+%.1f%%)" % [
					opt["cost"],
					(opt["mult"] - 1.0) * 100.0
				]
				
				parts_list.add_item(display_text)
				parts_list.set_item_metadata(parts_list.get_item_count() - 1, opt)
		
		# Enable remove if any upgrades are installed
		remove_button.disabled = not engine.can_remove_upgrades()
		return
	
	# Tyres upgrades
	if node is Tyres:
		var tyres := node as Tyres
		var upgrades := tyres.get_all_upgrade_options()

		for upgrade in upgrades:
			var text := "%s - $%d (μ≈%.2f, %.1f/10)" % [
				upgrade["display_name"],
				upgrade["cost"],
				upgrade["target_mu"],
				upgrade["target_mech_index"]
			]

			if tyres.is_upgrade_applied(upgrade["tier"], upgrade["level"]):
				text = "APPLIED: " + text

			parts_list.add_item(text)
			parts_list.set_item_metadata(parts_list.get_item_count() - 1, upgrade)

		remove_button.disabled = not tyres.can_remove_tyre_upgrade()
		return
	
	if node is Electronics:
		var elec = node as Electronics
		
		# ABS/TC toggles first
		var toggles := []
		toggles.append({
			"id": "abs",
			"display_name": "ABS",
			"action": "remove" if elec.has_abs() else "add",
			"cost": 0 if elec.has_abs() else 2500,
			"is_toggle": true,
		})
		toggles.append({
			"id": "tc",
			"display_name": "Traction Control",
			"action": "remove" if elec.has_tc() else "add",
			"cost": 0 if elec.has_tc() else 3000,
			"is_toggle": true,
		})
		
		parts_list.add_item("─── DRIVER AIDS ───")
		parts_list.set_item_disabled(parts_list.get_item_count() - 1, true)
		
		for toggle in toggles:
			var action = toggle.get("action", "")
			var label = toggle.get("display_name", "")
			var cost := int(toggle.get("cost", 0))
			
			var text := "%s (%s) - $%d" % [label, action, cost]
			parts_list.add_item(text)
			parts_list.set_item_metadata(parts_list.get_item_count() - 1, toggle)
		
		# ECU/Fuel parts
		var upgrades := elec.get_all_upgrade_options()
		
		# Filter to only ECU parts (not toggles)
		var ecu_parts: Array = []
		for upgrade in upgrades:
			if not upgrade.get("is_toggle", false):
				ecu_parts.append(upgrade)
		
		if not ecu_parts.is_empty():
			parts_list.add_item("─── ECU / FUEL SYSTEM ───")
			parts_list.set_item_disabled(parts_list.get_item_count() - 1, true)
			
			# Group by stage
			var by_stage: Dictionary = {1: [], 2: [], 3: []}
			for part in ecu_parts:
				var stage: int = part.get("stage", 1)
				if by_stage.has(stage):
					by_stage[stage].append(part)
			
			# Display by stage
			for stage in [1, 2, 3]:
				if by_stage[stage].is_empty():
					continue
				
				parts_list.add_item("─── STAGE %d ───" % stage)
				parts_list.set_item_disabled(parts_list.get_item_count() - 1, true)
				
				for part in by_stage[stage]:
					var display_text: String = part["display_name"]
					display_text += " - $%d (+%.1f%%)" % [
						part["cost"],
						(part["mult"] - 1.0) * 100.0
					]
					
					parts_list.add_item(display_text)
					parts_list.set_item_metadata(parts_list.get_item_count() - 1, part)
		
		# Check if any electronics changes
		var abs_changed = (
			elec.stock_abs_present != 0 and elec.abs_present == 0
		) or (
			elec.stock_abs_present == 0 and elec.abs_present == 1
		)
		
		var tc_changed = (
			elec.stock_tc_present != 0 and elec.tc_present == 0
		) or (
			elec.stock_tc_present == 0 and elec.tc_present == 1
		)
		
		remove_button.disabled = not (abs_changed or tc_changed or elec.can_remove_ecu_upgrades())
		return
	
	# Drivetrain upgrades
	if node is Drivetrain:
		var dt := node as Drivetrain
		var upgrades := dt.get_all_upgrade_options()
		
		for upgrade in upgrades:
			var display_text := "%s - $%d" % [
				upgrade["display_name"],
				upgrade["cost"]
			]
			
			if dt.current_archetype == upgrade["archetype_id"]:
				display_text = "✓ " + display_text
			
			parts_list.add_item(display_text)
			parts_list.set_item_metadata(parts_list.get_item_count() - 1, upgrade)
		
		remove_button.disabled = not dt.can_remove_drivetrain_upgrade()
		return
	
	# Weight Reduction upgrades
	if node is GeneralUpgrades:
		var gu := node as GeneralUpgrades
		var upgrades := gu.get_all_upgrade_options()
		
		# Group by stage
		var by_stage: Dictionary = {1: [], 2: [], 3: []}
		for upgrade in upgrades:
			var stage: int = upgrade.get("stage", 1)
			if by_stage.has(stage):
				by_stage[stage].append(upgrade)
		
		# Display parts organized by stage
		for stage in [1, 2, 3]:
			if by_stage[stage].is_empty():
				continue
			
			parts_list.add_item("─── STAGE %d ───" % stage)
			parts_list.set_item_disabled(parts_list.get_item_count() - 1, true)
			
			for upgrade in by_stage[stage]:
				var display_text: String = upgrade["display_name"]
				display_text += " - $%d (-%.1f%%)" % [
					upgrade["cost"],
					(1.0 - upgrade["mult"]) * 100.0
				]
				
				parts_list.add_item(display_text)
				parts_list.set_item_metadata(parts_list.get_item_count() - 1, upgrade)
		
		remove_button.disabled = not gu.can_remove_upgrades()
		return
	# Other categories: no upgrades
	parts_list.add_item("No upgrades available for this category")
	remove_button.disabled = true
	
func _update_drivetrain_upgrade_preview() -> void:
	if _selected_upgrade.is_empty():
		stat_changes.text = ""
		cost_label.text = ""
		purchase_button.disabled = true
		return
	
	var dt := _current_category_node as Drivetrain
	var archetype_id: String = _selected_upgrade.get("archetype_id", "")
	var cost: int = _selected_upgrade.get("cost", 0)
	
	if archetype_id == "":
		return
	
	var new_traction: String = _selected_upgrade.get("traction_type", "")
	var tier: String = _selected_upgrade.get("tier", "")
	
	stat_changes.clear()
	stat_changes.text = "[b]Drivetrain Upgrade Preview[/b]\n\n"
	
	stat_changes.text += "[b]Current:[/b] %s\n" % dt.traction_type
	stat_changes.text += "[b]New:[/b] %s (%s)\n\n" % [new_traction, tier.capitalize()]
	
	stat_changes.text += "[color=yellow]This will replace your entire drivetrain configuration[/color]\n"
	
	cost_label.clear()
	cost_label.text = "[center][b]Cost: $%d[/b][/center]" % cost
	
	purchase_button.disabled = false
	remove_button.disabled = true
	
func _update_weight_upgrade_preview() -> void:
	if _selected_upgrade.is_empty():
		stat_changes.text = ""
		cost_label.text = ""
		purchase_button.disabled = true
		return
	
	if not _current_category_node is GeneralUpgrades:
		return
	
	var gu := _current_category_node as GeneralUpgrades
	var part_id: int = _selected_upgrade.get("id", 0)
	var cost: int = _selected_upgrade.get("cost", 0)
	var part_name: String = _selected_upgrade.get("name", "")
	var replaces_id: int = _selected_upgrade.get("replaces_id", 0)
	
	if part_id == 0:
		return
	
	# Get preview weight
	var current_weight := gu.get_current_weight()
	var new_weight := gu.get_preview_weight(part_id)
	var weight_diff := current_weight - new_weight  # Saved weight
	
	# Calculate power-to-weight changes
	var engine := current_car.get_node_or_null("Engine") as CarEngine
	var hp := engine.estimated_hp if engine else 0.0
	
	var current_pw := hp / current_weight if current_weight > 0.0 else 0.0
	var new_pw := hp / new_weight if new_weight > 0.0 else 0.0
	var pw_diff := new_pw - current_pw
	
	# Check if already installed
	var already_installed := gu.is_part_installed(part_id)
	
	stat_changes.clear()
	stat_changes.text = "[b]Weight Reduction Preview[/b]\n\n"
	
	if already_installed:
		stat_changes.text += "[color=yellow]Already Installed[/color]\n\n"
		stat_changes.text += "[b]Part:[/b] %s\n" % part_name
	else:
		if weight_diff > 0:
			stat_changes.text += "[color=green]Weight: %.0f kg → %.0f kg (-%.0f kg)[/color]\n" % [
				current_weight, new_weight, weight_diff
			]
			
			if hp > 0.0:
				stat_changes.text += "[color=green]P/W Ratio: %.3f → %.3f hp/kg (+%.3f)[/color]\n\n" % [
					current_pw, new_pw, pw_diff
				]
		else:
			stat_changes.text += "Weight: %.0f kg (no change)\n\n" % current_weight
		
		stat_changes.text += "[b]Installing:[/b] %s\n" % part_name
		
		# Show what it replaces
		if replaces_id > 0:
			var old_part = gu._get_part_by_id(replaces_id)
			if not old_part.is_empty():
				stat_changes.text += "[color=orange]Replaces:[/color] %s\n" % old_part["name"]
	
	# Update cost display
	cost_label.clear()
	if already_installed:
		cost_label.text = "[center][b]Already Installed[/b][/center]"
		purchase_button.disabled = true
	else:
		cost_label.text = "[center][b]Cost: $%d[/b][/center]" % cost
		purchase_button.disabled = false

func _on_part_selected(index: int) -> void:
	if index < 0 or index >= parts_list.get_item_count():
		return
	
	var upgrade_data = parts_list.get_item_metadata(index)
	if upgrade_data == null or not upgrade_data is Dictionary:
		_selected_upgrade = {}
		stat_changes.text = ""
		cost_label.text = ""
		purchase_button.disabled = true
		remove_button.disabled = true
		return
	
	_selected_upgrade = upgrade_data
	if _selected_upgrade.get("is_engine_swap", false):
		_show_engine_swap_dialog()
		return
	if _current_category_node is Aero:
		_update_aero_upgrade_preview()
	if _current_category_node is Brakes:
		_update_brake_upgrade_preview()
	elif _current_category_node is CarEngine:
		_update_engine_upgrade_preview()
	elif _current_category_node is Electronics:
		_update_electronics_upgrade_preview()
		return
	elif _current_category_node is Drivetrain:
		_update_drivetrain_upgrade_preview()
		return
	elif _current_category_node is Tyres:
		_update_tyre_upgrade_preview()
		return
	elif _current_category_node is GeneralUpgrades:
		_update_weight_upgrade_preview()
		return
	else:
		_selected_upgrade = {}
		stat_changes.text = ""
		cost_label.text = ""
		purchase_button.disabled = true
		remove_button.disabled = true
		
func _show_engine_swap_dialog() -> void:
	_engine_swap_list.clear()
	_selected_swap_car = null
	_engine_swap_confirm.disabled = true
	
	var carloader = get_tree().root.get_node("Carloader")
	if not carloader:
		return
	
	var current_engine := current_car.get_node_or_null("Engine") as CarEngine
	if not current_engine:
		return
	
	# Populate list with all cars except current
	for car in carloader.loaded_cars:
		if car.car_id == current_car.car_id:
			continue
		
		var other_engine := car.get_node_or_null("Engine") as CarEngine
		if not other_engine:
			continue
		
		var hp := other_engine.stock_hp
		var diff := hp - current_engine.stock_hp
		var thissign := "+" if diff > 0 else ""
		
		var text := "%s - %.0f bhp (%s%.0f bhp)" % [
			car.screen_name if car.screen_name != "" else car.car_id,
			hp,
			thissign,
			diff
		]
		
		_engine_swap_list.add_item(text)
		_engine_swap_list.set_item_metadata(_engine_swap_list.get_item_count() - 1, car)
	
	_engine_swap_popup.popup_centered()
	
func _on_engine_swap_car_selected(index: int) -> void:
	_selected_swap_car = _engine_swap_list.get_item_metadata(index)
	_engine_swap_confirm.disabled = (_selected_swap_car == null)

	if _selected_swap_car:
		# Mark that purchase should perform a swap
		_selected_upgrade = {"is_engine_swap": true}
		_update_engine_swap_preview(_selected_swap_car)
		
func _update_engine_swap_preview(swap_car: Car) -> void:
	var current_engine := current_car.get_node_or_null("Engine") as CarEngine
	var swap_engine := swap_car.get_node_or_null("Engine") as CarEngine
	
	if not current_engine or not swap_engine:
		return
	
	var current_hp := current_engine.get_current_hp()
	var new_hp := swap_engine.stock_hp
	var diff_hp := new_hp - current_hp
	
	# Calculate cost based on HP difference
	var cost = _calculate_swap_cost(current_hp, new_hp)
	
	# Calculate refund from current upgrades
	var refund := current_engine.get_upgrade_refund_value()
	var net_cost = cost - refund
	
	stat_changes.clear()
	stat_changes.text = "[b]Engine Swap Preview[/b]\n\n"
	stat_changes.text += "[b]Donor Car:[/b] %s\n\n" % (swap_car.screen_name if swap_car.screen_name != "" else swap_car.car_id)
	
	if diff_hp > 0:
		stat_changes.text += "[color=green]Power: %.0f bhp → %.0f bhp (+%.0f)[/color]\n" % [current_hp, new_hp, diff_hp]
		stat_changes.text += "[color=green]Gain: +%.1f%%[/color]\n\n" % [(diff_hp / current_hp) * 100.0]
	elif diff_hp < 0:
		stat_changes.text += "[color=orange]Power: %.0f bhp → %.0f bhp (%.0f)[/color]\n" % [current_hp, new_hp, diff_hp]
		stat_changes.text += "[color=orange]Loss: %.1f%%[/color]\n\n" % [(diff_hp / current_hp) * 100.0]
	else:
		stat_changes.text += "Power: %.0f bhp (no change)\n\n" % current_hp
	
	if refund > 0:
		stat_changes.text += "[color=yellow]Current upgrades will be removed[/color]\n"
		stat_changes.text += "Refund: $%d\n\n" % refund
	
	if swap_engine.has_stock_turbo:
		stat_changes.text += "[color=cyan]Donor engine has turbocharger[/color]\n"
	
	cost_label.clear()
	cost_label.text = "[center][b]Swap Cost: $%d[/b][/center]\n" % cost
	if refund > 0:
		cost_label.text += "[center]Refund: $%d[/center]\n" % refund
		cost_label.text += "[center][b]Net Cost: $%d[/b][/center]" % net_cost
	
	purchase_button.disabled = false
	
func _calculate_swap_cost(current_hp: float, new_hp: float) -> int:
	# Base cost scaling: $10 per HP difference
	var hp_diff = abs(new_hp - current_hp)
	var base_cost := int(hp_diff * 10.0)
	
	# Minimum cost for any swap
	var min_cost := 1000
	
	# Downgrade is cheaper
	if new_hp < current_hp:
		return max(min_cost / 2, base_cost / 2)
	
	return max(min_cost, base_cost)
	
func _on_engine_swap_cancel() -> void:
	_engine_swap_popup.hide()
	stat_changes.text = ""
	cost_label.text = ""
	purchase_button.disabled = true
	
func _on_engine_swap_confirm() -> void:
	if not _selected_swap_car:
		return
	
	_engine_swap_popup.hide()
	
	var current_engine := current_car.get_node_or_null("Engine") as CarEngine
	var swap_engine := _selected_swap_car.get_node_or_null("Engine") as CarEngine
	
	if not current_engine or not swap_engine:
		return
	
	# Perform the swap
	current_engine.copy_from_engine(swap_engine, _selected_swap_car.car_id)
	current_car._compute_performance_metrics()
	
	car_has_modifications = true
	finalize_button.disabled = false
	
	_populate_from_car()
	print("Engine swapped from %s" % _selected_swap_car.car_id)
		
func _update_tyre_upgrade_preview() -> void:
	if _selected_upgrade.is_empty():
		stat_changes.text = ""
		cost_label.text = ""
		purchase_button.disabled = true
		remove_button.disabled = true
		return

	var tyres := _current_category_node as Tyres
	var tier: String = _selected_upgrade.get("tier", "")
	var level: int = _selected_upgrade.get("level", 0)
	var cost: int = _selected_upgrade.get("cost", 0)
	var target_mu: float = float(_selected_upgrade.get("target_mu", 0.0))
	var target_idx: float = float(_selected_upgrade.get("target_mech_index", 0.0))
	if tier == "" or level <= 0:
		return

	tyres.preview_with_upgrade(tier, level)

	stat_changes.clear()
	stat_changes.text = "[b]Tyre Upgrade Preview[/b]\n\n"

	stat_changes.text += "[b]Current:[/b] %s L%d\n" % [
		Tyres.TIER_DISPLAY.get(tyres.current_tier, "Unknown"),
		tyres.current_level
	]
	stat_changes.text += "[b]Selected:[/b] %s L%d\n" % [
		Tyres.TIER_DISPLAY.get(tier, tier),
		level
	]

	stat_changes.text += "\nμ target: %.2f\n" % target_mu
	stat_changes.text += "Mechanical grip index: %.1f / 10\n" % target_idx

	cost_label.clear()
	cost_label.text = "[center][b]Cost: $%d[/b][/center]" % cost

	purchase_button.disabled = false
	remove_button.disabled = true


func _update_electronics_upgrade_preview() -> void:
	if _selected_upgrade.is_empty():
		stat_changes.text = ""
		cost_label.text = ""
		purchase_button.disabled = true
		remove_button.disabled = true
		return

	var elec := _current_category_node as Electronics
	var is_toggle: bool = _selected_upgrade.get("is_toggle", false)
	
	if is_toggle:
		# ABS/TC toggle preview
		var id: String = _selected_upgrade.get("id", "")
		if id == "":
			return

		elec.preview_toggle(id)

		var label = _selected_upgrade.get("display_name", id)
		var action = _selected_upgrade.get("action", "")
		var cost := int(_selected_upgrade.get("cost", 0))

		stat_changes.clear()
		stat_changes.text = "[b]Electronics Upgrade Preview[/b]\n\n"
		stat_changes.text += "[b]%s[/b] -> %s\n\n" % [label, action]

		if id == "abs":
			var abs_before := "Enabled" if elec.has_abs() else "Disabled"
			var abs_after_enabled := elec.proposed_abs_present == 1 and elec.proposed_abs_active == 1
			var abs_after := "Enabled" if abs_after_enabled else "Disabled"
			stat_changes.text += "ABS: %s → %s\n" % [abs_before, abs_after]
		elif id == "tc":
			var tc_before := "Enabled" if elec.has_tc() else "Disabled"
			var tc_after_enabled := elec.proposed_tc_present == 1 and elec.proposed_tc_active == 1
			var tc_after := "Enabled" if tc_after_enabled else "Disabled"
			stat_changes.text += "TC: %s → %s\n" % [tc_before, tc_after]

		cost_label.clear()
		if cost > 0:
			cost_label.text = "[center][b]Cost: $%d[/b][/center]" % cost
		else:
			cost_label.text = "[center][b]Cost: FREE[/b][/center]"

		purchase_button.disabled = false
		remove_button.disabled = true
	else:
		# ECU part preview
		var part_id: int = _selected_upgrade.get("id", 0)
		var cost: int = _selected_upgrade.get("cost", 0)
		var part_name: String = _selected_upgrade.get("name", "")
		var replaces_id: int = _selected_upgrade.get("replaces_id", 0)
		
		if part_id == 0:
			return
		
		# Get preview multiplier
		var current_mult := elec.get_ecu_power_multiplier()
		var new_mult := elec.get_preview_multiplier(part_id)
		var mult_diff := new_mult - current_mult
		
		# Get engine power to show HP impact
		var engine := current_car.get_node_or_null("Engine") as CarEngine
		var current_power := engine.get_current_hp() if engine else 0.0
		var new_power := current_power * (new_mult / current_mult) if current_mult > 0.0 else current_power
		var power_diff := new_power - current_power
		
		# Check if already installed
		var already_installed := elec.is_part_installed(part_id)
		
		stat_changes.clear()
		stat_changes.text = "[b]ECU Upgrade Preview[/b]\n\n"
		
		if already_installed:
			stat_changes.text += "[color=yellow]Already Installed[/color]\n\n"
			stat_changes.text += "[b]Part:[/b] %s\n" % part_name
		else:
			if mult_diff > 0.0:
				stat_changes.text += "[color=green]ECU Multiplier: x%.3f → x%.3f (+%.3f)[/color]\n" % [
					current_mult, new_mult, mult_diff
				]
				
				if engine:
					stat_changes.text += "[color=green]Engine Power: %.0f bhp → %.0f bhp (+%.0f)[/color]\n\n" % [
						current_power, new_power, power_diff
					]
			else:
				stat_changes.text += "ECU Multiplier: x%.3f (no change)\n\n" % current_mult
			
			stat_changes.text += "[b]Installing:[/b] %s\n" % part_name
			
			# Show what it replaces
			if replaces_id > 0:
				var old_part = elec._get_part_by_id(replaces_id)
				if not old_part.is_empty():
					stat_changes.text += "[color=orange]Replaces:[/color] %s\n" % old_part["name"]
		
		# Update cost display
		cost_label.clear()
		if already_installed:
			cost_label.text = "[center][b]Already Installed[/b][/center]"
			purchase_button.disabled = true
		else:
			cost_label.text = "[center][b]Cost: $%d[/b][/center]" % cost
			purchase_button.disabled = false

func _update_aero_upgrade_preview() ->void:
	if _selected_upgrade.is_empty():
		stat_changes.text = ""
		cost_label.text = ""
		purchase_button.disabled = true
		return
	
	if not _current_category_node is Aero:
		return
	
	var aero := _current_category_node as Aero
	var part_id: int = _selected_upgrade.get("id", 0)
	var cost: int = _selected_upgrade.get("cost", 0)
	var part_name: String = _selected_upgrade.get("name", "")
	var replaces_id: int = _selected_upgrade.get("replaces_id", 0)
	
	if part_id == 0:
		return
	
	# Check if already installed
	var already_installed := aero.is_part_installed(part_id)
	
	stat_changes.clear()
	stat_changes.text = "[b]Brake Upgrade Preview[/b]\n\n"
	
	if already_installed:
		stat_changes.text += "[color=yellow]Already Installed[/color]\n\n"
		stat_changes.text += "[b]Part:[/b] %s\n" % part_name
	# else:

	
	# Update cost display
	cost_label.clear()
	if already_installed:
		cost_label.text = "[center][b]Already Installed[/b][/center]"
		purchase_button.disabled = true
	else:
		cost_label.text = "[center][b]Cost: $%d[/b][/center]" % cost
		purchase_button.disabled = false
		print("hello")

func _update_brake_upgrade_preview() -> void:
	if _selected_upgrade.is_empty():
		stat_changes.text = ""
		cost_label.text = ""
		purchase_button.disabled = true
		return
	
	if not _current_category_node is Brakes:
		return
	
	var brakes := _current_category_node as Brakes
	var part_id: int = _selected_upgrade.get("id", 0)
	var cost: int = _selected_upgrade.get("cost", 0)
	var part_name: String = _selected_upgrade.get("name", "")
	var replaces_id: int = _selected_upgrade.get("replaces_id", 0)
	
	if part_id == 0:
		return
	
	# Get preview torque
	var current_torque := brakes.get_current_torque()
	var new_torque := brakes.get_preview_torque(current_car, part_id)
	var torque_diff := new_torque - current_torque
	
	# Calculate ratios
	var current_ratio := brakes.get_brake_ratio(current_car)
	var new_ratio := new_torque / current_car.total_mass if current_car.total_mass > 0.0 else 0.0
	var ratio_diff := new_ratio - current_ratio
	
	# Check if already installed
	var already_installed := brakes.is_part_installed(part_id)
	
	stat_changes.clear()
	stat_changes.text = "[b]Brake Upgrade Preview[/b]\n\n"
	
	if already_installed:
		stat_changes.text += "[color=yellow]Already Installed[/color]\n\n"
		stat_changes.text += "[b]Part:[/b] %s\n" % part_name
	else:
		if torque_diff > 0:
			stat_changes.text += "[color=green]Max Torque: %.0f Nm → %.0f Nm (+%.0f)[/color]\n" % [
				current_torque, new_torque, torque_diff
			]
			stat_changes.text += "[color=green]Brake Ratio: %.2f → %.2f Nm/kg (+%.2f)[/color]\n\n" % [
				current_ratio, new_ratio, ratio_diff
			]
		else:
			stat_changes.text += "Max Torque: %.0f Nm (no change)\n" % current_torque
			stat_changes.text += "Brake Ratio: %.2f Nm/kg\n\n" % current_ratio
		
		stat_changes.text += "[b]Installing:[/b] %s\n" % part_name
		
		# Show what it replaces
		if replaces_id > 0:
			var old_part = brakes._get_part_by_id(replaces_id)
			if not old_part.is_empty():
				stat_changes.text += "[color=orange]Replaces:[/color] %s\n" % old_part["name"]
	
	# Update cost display
	cost_label.clear()
	if already_installed:
		cost_label.text = "[center][b]Already Installed[/b][/center]"
		purchase_button.disabled = true
	else:
		cost_label.text = "[center][b]Cost: $%d[/b][/center]" % cost
		purchase_button.disabled = false
	
func _update_engine_upgrade_preview() -> void:
	if _selected_upgrade.is_empty():
		stat_changes.text = ""
		cost_label.text = ""
		purchase_button.disabled = true
		remove_button.disabled = true
		return
	
	if not _current_category_node is CarEngine:
		return
	
	var engine := _current_category_node as CarEngine
	var part_id: int = _selected_upgrade.get("id", 0)
	var cost: int = _selected_upgrade.get("cost", 0)
	var part_name: String = _selected_upgrade.get("name", "")
	var is_turbo: bool = _selected_upgrade.get("is_turbo", false)
	var replaces_id: int = _selected_upgrade.get("replaces_id", 0)
	
	if part_id == 0:
		return
	
	# Get preview HP
	engine.preview_with_upgrade(part_id)
	
	var current_power := engine.get_current_hp()
	var new_power := engine.proposed_hp
	var diff_power := new_power - current_power
	
	# Check if already installed
	var already_installed := engine.is_part_installed(part_id)
	
	stat_changes.clear()
	stat_changes.text = "[b]Engine Upgrade Preview[/b]\n\n"
	
	if already_installed:
		stat_changes.text += "[color=yellow]Already Installed[/color]\n\n"
		stat_changes.text += "[b]Part:[/b] %s\n" % part_name
	else:
		if diff_power > 0:
			stat_changes.text += "[color=green]Power: %.0f bhp → %.0f bhp (+%.0f)[/color]\n" % [
				current_power, new_power, diff_power
			]
			stat_changes.text += "[color=green]Gain: +%.1f%%[/color]\n\n" % [
				(diff_power / current_power) * 100.0
			]
		else:
			stat_changes.text += "Power: %.0f bhp (no change)\n\n" % current_power
		
		stat_changes.text += "[b]Installing:[/b] %s\n" % part_name
		
		# Show what it replaces
		if replaces_id > 0:
			var old_part = engine._get_part_by_id(replaces_id)
			if not old_part.is_empty():
				stat_changes.text += "[color=orange]Replaces:[/color] %s\n" % old_part["name"]
		
		# Special note for turbo
		if is_turbo:
			if not engine.has_stock_turbo:
				stat_changes.text += "\n[color=cyan]Adds turbocharger to naturally aspirated engine[/color]\n"
			else:
				stat_changes.text += "\n[color=cyan]Upgrades existing turbocharger[/color]\n"
	
	# Update cost display
	cost_label.clear()
	if already_installed:
		cost_label.text = "[center][b]Already Installed[/b][/center]"
		purchase_button.disabled = true
	else:
		cost_label.text = "[center][b]Cost: $%d[/b][/center]" % cost
		purchase_button.disabled = false
	
	# Enable remove if this part is installed
	remove_button.disabled = not already_installed


func _update_turbo_upgrade_preview() -> void:
	if not _current_category_node is CarEngine:
		return
	
	var engine := _current_category_node as CarEngine
	var tier: String = _selected_upgrade.get("tier", "")
	var cost: int = _selected_upgrade.get("cost", 0)
	
	if tier == "":
		return
	
	engine.preview_turbo_upgrade(tier)
	
	var base_hp := engine.current_hp
	var new_hp := engine.proposed_hp
	var diff_hp := new_hp - base_hp
	
	stat_changes.clear()
	stat_changes.text = "[b]Turbo Upgrade Preview[/b]\n\n"
	
	stat_changes.text += "[color=green]Power: %.0f bhp → %.0f bhp (+%.0f)[/color]\n" % [
		base_hp, new_hp, diff_hp
	]
	
	var boost = _selected_upgrade.get("max_boost", 0.0)
	stat_changes.text += "\n[b]Max Boost:[/b] %.2f (+%.0f%%)\n" % [boost, boost * 100.0]
	
	# Show aspiration change
	if engine.has_stock_turbo:
		if engine.current_turbo_tier == "stock":
			stat_changes.text += "[b]Aspiration:[/b] Stock Turbo → Upgraded Turbo\n"
		else:
			stat_changes.text += "[b]Aspiration:[/b] Turbo Upgrade\n"
	else:
		stat_changes.text += "[b]Aspiration:[/b] Naturally Aspirated → Turbocharged\n"
	
	cost_label.clear()
	cost_label.text = "[center][b]Cost: $%d[/b][/center]" % cost
	
	purchase_button.disabled = false
	remove_button.disabled = true

func _tier_label(tier: String) -> String:
	match tier:
		"street":
			return "Street Brakes"
		"sport":
			return "Sport Brakes"
		"race":
			return "Race Brakes"
		_:
			return tier

func _on_purchase_pressed() -> void:
	if _selected_upgrade.is_empty():
		return
	if _current_category_node is Aero:
		var aero := _current_category_node as Aero
		var part_id: int = _selected_upgrade.get("id", 0)
		
		if part_id == 0:
			return
		
		if aero.apply_aero_upgrade(current_car, part_id):
			current_car._compute_performance_metrics()
			
			car_has_modifications = true
			finalize_button.disabled = false
			
			_populate_from_car()
			print("Purchased aero upgrade: %s" % _selected_upgrade.get("name", ""))
		return
	# Brakes: part-based system
	if _current_category_node is Brakes:
		var brakes := _current_category_node as Brakes
		var part_id: int = _selected_upgrade.get("id", 0)
		
		if part_id == 0:
			return
		
		if brakes.apply_brake_upgrade(current_car, part_id):
			current_car._compute_performance_metrics()
			
			car_has_modifications = true
			finalize_button.disabled = false
			
			_populate_from_car()
			print("Purchased brake upgrade: %s" % _selected_upgrade.get("name", ""))
		return
	
	# Engine: part-based system
	if _current_category_node is CarEngine:
		# Engine swap uses purchase button (no part id)
		if _selected_upgrade.get("is_engine_swap", false):
			if not _selected_swap_car:
				return

			var current_engine := current_car.get_node_or_null("Engine") as CarEngine
			var swap_engine := _selected_swap_car.get_node_or_null("Engine") as CarEngine
			if not current_engine or not swap_engine:
				return

			current_engine.copy_from_engine(swap_engine, _selected_swap_car.car_id)
			current_car._compute_performance_metrics()

			car_has_modifications = true
			finalize_button.disabled = false

			_engine_swap_popup.hide()
			_populate_from_car()
			print("Purchased engine swap from %s" % _selected_swap_car.car_id)
			return

		# Normal engine upgrades (parts)
		var engine := _current_category_node as CarEngine
		var part_id: int = _selected_upgrade.get("id", 0)
		if part_id == 0:
			return

		if engine.apply_engine_upgrade(part_id):
			current_car._compute_performance_metrics()
			car_has_modifications = true
			finalize_button.disabled = false
			_populate_from_car()
			print("Purchased engine upgrade: %s" % _selected_upgrade.get("name", ""))
		return
	
	# Tyres
	if _current_category_node is Tyres:
		var tyres := _current_category_node as Tyres
		var tier: String = _selected_upgrade.get("tier", "")
		var level: int = _selected_upgrade.get("level", 0)
		if tier == "" or level <= 0:
			return

		tyres.apply_tyre_upgrade(tier, level)
		current_car._compute_performance_metrics()

		car_has_modifications = true
		finalize_button.disabled = false

		_populate_from_car()
		print("Purchased tyre upgrade: %s L%d" % [tier, level])
		return
	
	# Electronics: toggles + ECU parts
	if _current_category_node is Electronics:
		var elec := _current_category_node as Electronics
		var is_toggle: bool = _selected_upgrade.get("is_toggle", false)
		
		if is_toggle:
			# ABS/TC toggle
			var id: String = _selected_upgrade.get("id", "")
			if id == "":
				return

			elec.apply_toggle(id)
			current_car._compute_performance_metrics()

			car_has_modifications = true
			finalize_button.disabled = false

			_populate_from_car()
			print("Toggled electronics upgrade: %s" % id)
		else:
			# ECU part
			var part_id: int = _selected_upgrade.get("id", 0)
			if part_id == 0:
				return
			
			if elec.apply_ecu_upgrade(part_id):
				current_car._compute_performance_metrics()
				
				car_has_modifications = true
				finalize_button.disabled = false
				
				_populate_from_car()
				print("Purchased ECU upgrade: %s" % _selected_upgrade.get("name", ""))
		return
	# Weight Reduction: part-based system
	if _current_category_node is GeneralUpgrades:
		var gu := _current_category_node as GeneralUpgrades
		var part_id: int = _selected_upgrade.get("id", 0)
		
		if part_id == 0:
			return
		
		if gu.apply_weight_upgrade(part_id):
			current_car._compute_performance_metrics()
			
			car_has_modifications = true
			finalize_button.disabled = false
			
			_populate_from_car()
			print("Purchased weight reduction: %s" % _selected_upgrade.get("name", ""))
		return
	# Drivetrain: archetype replacement
	if _current_category_node is Drivetrain:
		var dt := _current_category_node as Drivetrain
		var archetype_id: String = _selected_upgrade.get("archetype_id", "")
		if archetype_id == "":
			return
		
		var carloader = get_tree().root.get_node("Carloader")
		if carloader == null:
			push_error("Could not find Carloader!")
			return
		
		if carloader._apply_drivetrain_archetype(current_car, archetype_id):
			dt.apply_drivetrain_upgrade(archetype_id)
			
			car_has_modifications = true
			finalize_button.disabled = false
			
			_populate_from_car()
			print("Applied drivetrain upgrade: %s" % archetype_id)
		else:
			push_error("Failed to apply drivetrain archetype")
		return
		
func _on_remove_pressed() -> void:
	if _current_category_node == null:
		return
	
	# Brakes: remove specific part or revert to stock
	if _current_category_node is Brakes:
		var brakes := _current_category_node as Brakes
		
		# If a specific part is selected, remove it
		if not _selected_upgrade.is_empty():
			var part_id: int = _selected_upgrade.get("id", 0)
			if part_id > 0 and brakes.is_part_installed(part_id):
				brakes.remove_brake_upgrade(part_id)
				current_car._compute_performance_metrics()
				
				car_has_modifications = true
				finalize_button.disabled = false
				
				_populate_from_car()
				print("Removed brake upgrade: %s" % _selected_upgrade.get("name", ""))
				return
		
		# Otherwise revert all to stock
		brakes.revert_to_stock()
		current_car._compute_performance_metrics()
		
		car_has_modifications = true
		finalize_button.disabled = false
		
		_populate_from_car()
		print("Reverted brakes to stock")
		return
	
	# Engine: remove specific part or revert to stock
	if _current_category_node is CarEngine:
		var engine := _current_category_node as CarEngine
		
		# If a specific part is selected, remove it
		if not _selected_upgrade.is_empty():
			var part_id: int = _selected_upgrade.get("id", 0)
			if part_id > 0 and engine.is_part_installed(part_id):
				engine.remove_engine_upgrade(part_id)
				current_car._compute_performance_metrics()
				
				car_has_modifications = true
				finalize_button.disabled = false
				
				_populate_from_car()
				print("Removed engine upgrade: %s" % _selected_upgrade.get("name", ""))
				return
		
		# Check if we should remove turbo
		if engine.can_remove_turbo():
			engine.remove_turbo_upgrade()
			current_car._compute_performance_metrics()
			
			car_has_modifications = true
			finalize_button.disabled = false
			
			_populate_from_car()
			print("Removed turbo upgrade")
			return
		
		# Otherwise revert all to stock
		engine.revert_to_stock()
		current_car._compute_performance_metrics()
		
		car_has_modifications = true
		finalize_button.disabled = false
		
		_populate_from_car()
		print("Reverted engine to stock")
		return
	
	# Tyres: revert to stock
	if _current_category_node is Tyres:
		var tyres := _current_category_node as Tyres
		tyres.revert_to_stock()
		current_car._compute_performance_metrics()

		car_has_modifications = true
		finalize_button.disabled = false

		_populate_from_car()
		print("Reverted tyres to stock")
		return
	
	# Electronics: revert to stock state
	if _current_category_node is Electronics:
		var elec := _current_category_node as Electronics
		
		# If a specific ECU part is selected, remove it
		if not _selected_upgrade.is_empty() and not _selected_upgrade.get("is_toggle", false):
			var part_id: int = _selected_upgrade.get("id", 0)
			if part_id > 0 and elec.is_part_installed(part_id):
				elec.remove_ecu_upgrade(part_id)
				current_car._compute_performance_metrics()
				
				car_has_modifications = true
				finalize_button.disabled = false
				
				_populate_from_car()
				print("Removed ECU upgrade: %s" % _selected_upgrade.get("name", ""))
				return
		
		# Otherwise revert everything to stock
		elec.revert_to_stock()
		current_car._compute_performance_metrics()

		car_has_modifications = true
		finalize_button.disabled = false

		_populate_from_car()
		print("Reverted electronics to stock")
		return
	# Weight Reduction: remove specific part or revert to stock
	if _current_category_node is GeneralUpgrades:
		var gu := _current_category_node as GeneralUpgrades
		
		# If a specific part is selected, remove it
		if not _selected_upgrade.is_empty():
			var part_id: int = _selected_upgrade.get("id", 0)
			if part_id > 0 and gu.is_part_installed(part_id):
				gu.remove_weight_upgrade(part_id)
				current_car._compute_performance_metrics()
				
				car_has_modifications = true
				finalize_button.disabled = false
				
				_populate_from_car()
				print("Removed weight reduction: %s" % _selected_upgrade.get("name", ""))
				return
		
		# Otherwise revert all to stock
		gu.revert_to_stock()
		current_car._compute_performance_metrics()
		
		car_has_modifications = true
		finalize_button.disabled = false
		
		_populate_from_car()
		print("Reverted weight to stock")
		return
	# Drivetrain: revert to stock
	if _current_category_node is Drivetrain:
		var dt := _current_category_node as Drivetrain
		
		var carloader = get_tree().root.get_node("Carloader")
		if carloader == null:
			push_error("Could not find Carloader!")
			return
		
		if carloader._remove_drivetrain_archetype(current_car):
			dt.remove_drivetrain_upgrade()
			
			car_has_modifications = true
			finalize_button.disabled = false
			
			_populate_from_car()
			print("Reverted drivetrain to stock")
		else:
			push_error("Failed to remove drivetrain archetype")
		return

func _on_finalize_pressed() -> void:
	if current_car == null:
		return
	
	if not current_car.is_custom:
		push_error("Cannot finalize a non-custom car!")
		return
	
	# Get the carloader node
	var carloader = get_tree().root.get_node("Carloader")
	if carloader == null:
		push_error("Could not find Carloader node!")
		return
	
	# Call the finalize method on carloader
	var success = carloader.finalize_car_build(current_car)
	
	if success:
		print("Car build finalized successfully!")
		car_has_modifications = false
		finalize_button.disabled = true
		# Show success message
		_show_finalize_success()
	else:
		push_error("Failed to finalize car build")

func _show_finalize_success() -> void:
	print("Build finalized! Car exported to Assetto Corsa.")
	
func _on_delete_pressed() -> void:
	# Return to car list
	var carloader = get_tree().root.get_node("Carloader")
	if carloader:
		carloader.delete_car(current_car.car_id)

func _on_back_pressed() -> void:
	# Return to car list
	var carloader = get_tree().root.get_node("Carloader")
	if carloader:
		carloader.return_to_car_list()

func _populate_values_for_node(node: Node) -> void:
	value_list.clear()
	if node == null:
		return
	
	var props := node.get_property_list()
	for prop in props:
		var usage := int(prop.get("usage", 0))
		var prop_name := String(prop.get("name", ""))
		
		# Only script vars, skip engine/internal stuff
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
			
		if prop_name.begins_with("_"):
			continue
		
		var value = node.get(prop_name)
		
		if value is Node:
			continue
		
		if value is Array:
			_add_array_items(prop_name, value)
			continue
		
		if value is Object and not (value is Resource):
			if _is_inner_class_instance(value):
				_add_inner_class_items(prop_name, value)
				continue
			else:
				continue
		
		var value_str := _value_to_string(value)
		value_list.add_item("%s = %s" % [prop_name, value_str])

func _is_inner_class_instance(obj: Object) -> bool:
	if obj is Node or obj is Resource:
		return false
	
	var props := obj.get_property_list()
	for prop in props:
		var usage := int(prop.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			return true
	
	return false

func _add_array_items(array_name: String, arr: Array) -> void:
	if arr.is_empty():
		value_list.add_item("%s = []" % array_name)
		return
	
	var first_elem = arr[0]
	if first_elem is Object and _is_inner_class_instance(first_elem):
		value_list.add_item("─── %s [%d items] ───" % [array_name, arr.size()])
		
		for i in range(arr.size()):
			var obj = arr[i]
			value_list.add_item("  [%d]" % i)
			_add_inner_class_items("", obj, "    ")
	else:
		value_list.add_item("%s = %s" % [array_name, _value_to_string(arr)])

func _add_inner_class_items(thisclass_Name: String, obj: Object, indent: String = "  ") -> void:
	# Add properties of an inner class instance (like Aero.Wing)
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
