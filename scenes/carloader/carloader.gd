# carloader.gd
extends Node2D

var cars_base_dir := ""
var loaded_cars: Array[Car] = []

const CONFIG_PATH := "user://car_tuner_settings.cfg"
const CFG_SECTION := "paths"
const CFG_KEY_AC_ROOT := "ac_root"
const CFG_FINALIZED_CARS := "finalized_cars"
@onready var cartunerui = $CarTunerUI
var ac_root_path: String = ""
const USER_CARS_ROOT := "user://cars"
const CUSTOM_PREFIX := "js_"
# Drivetrain archetype storage
var drivetrain_archetypes: Dictionary = {}
const DRIVETRAIN_ARCHETYPE_PATH := "res://drivetrain_archetypes"

# Drivetrain costs 
const DRIVETRAIN_COSTS := {
	"fwd_street": 2000,
	"fwd_sport": 5000,
	"fwd_race": 12000,
	"rwd_street": 4000,
	"rwd_sport": 8000,
	"rwd_race": 18000,
	"awd_street": 8000,
	"awd_sport": 15000,
	"awd_race": 30000,
}
# Track which cars have been finalized (exported to AC folder)
var finalized_cars: Array[String] = []

func _ready() -> void:
	cartunerui.set_process_input(false)
	_load_drivetrain_archetypes()
	if _load_saved_ac_path():
		_load_finalized_cars_list()
		load_all_cars()
		setup_ui()
	else:
		ask_for_ac_location()

func _load_drivetrain_archetypes() -> void:
	print("[CarLoader] Loading drivetrain archetypes...")
	
	drivetrain_archetypes.clear()
	
	var traction_types := ["fwd", "rwd", "awd"]
	var tiers := ["street", "sport", "race"]
	
	for traction in traction_types:
		for tier in tiers:
			var archetype_id := "%s_%s" % [traction, tier]
			var archetype_path := DRIVETRAIN_ARCHETYPE_PATH.path_join(archetype_id)
			
			if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(archetype_path)):
				push_warning("Drivetrain archetype directory not found: %s" % archetype_path)
				continue
			
			# Get all files in the archetype directory
			var archetype_files: Array[String] = []
			var dir := DirAccess.open(archetype_path)
			if dir:
				dir.list_dir_begin()
				while true:
					var file := dir.get_next()
					if file == "":
						break
					if file == "." or file == "..":
						continue
					if not dir.current_is_dir():
						archetype_files.append(file)
				dir.list_dir_end()
			
			# Store archetype info
			drivetrain_archetypes[archetype_id] = {
				"path": archetype_path,
				"files": archetype_files,
				"traction_type": traction.to_upper(),
				"tier": tier,
				"display_name": "%s %s" % [traction.to_upper(), tier.capitalize()],
				"cost": DRIVETRAIN_COSTS.get(archetype_id, 5000),
			}
			
			print("[CarLoader] Loaded archetype: %s (%d files)" % [archetype_id, archetype_files.size()])
	
	print("[CarLoader] Loaded %d drivetrain archetypes" % drivetrain_archetypes.size())


func get_drivetrain_archetypes() -> Dictionary:
	return drivetrain_archetypes

func ask_for_ac_location() -> void:
	$FileDialog.popup_centered()

func _classify_drivetrain_archetype(car: Car) -> void:
	var dt := car.get_node_or_null("Drivetrain") as Drivetrain
	if dt == null:
		return
	
	# Determine tier based on performance
	var tier := "street"
	if car.performance_index >= 7.0:
		tier = "race"
	elif car.performance_index >= 5.0:
		tier = "sport"
	
	# Build archetype ID
	var traction := dt.traction_type.to_lower()
	var archetype_id := "%s_%s" % [traction, tier]
	
	# Set as stock archetype
	dt.stock_archetype = archetype_id
	dt.current_archetype = archetype_id

#  Config handling

func _load_saved_ac_path() -> bool:
	var root := str(ConfigFile.new().get_value(CFG_SECTION, CFG_KEY_AC_ROOT, ""))
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		return false

	root = str(cfg.get_value(CFG_SECTION, CFG_KEY_AC_ROOT, ""))
	if root == "":
		return false

	var acs_path := root.path_join("acs.exe")
	if not FileAccess.file_exists(acs_path):
		return false

	ac_root_path = root
	cars_base_dir = ac_root_path.path_join("content/cars")
	return true

func _save_ac_root_path(ac_root: String) -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		cfg = ConfigFile.new()

	cfg.set_value(CFG_SECTION, CFG_KEY_AC_ROOT, ac_root)
	cfg.save(CONFIG_PATH)


func _load_finalized_cars_list() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		finalized_cars = []
		return
	
	var list = cfg.get_value(CFG_SECTION, CFG_FINALIZED_CARS, [])
	if list is Array:
		finalized_cars = list
	else:
		finalized_cars = []


func _save_finalized_cars_list() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		cfg = ConfigFile.new()
	
	cfg.set_value(CFG_SECTION, CFG_FINALIZED_CARS, finalized_cars)
	cfg.save(CONFIG_PATH)


func _mark_car_finalized(original_folder: String) -> void:
	var custom_id := "%s%s" % [CUSTOM_PREFIX, original_folder]
	if not finalized_cars.has(custom_id):
		finalized_cars.append(custom_id)
		_save_finalized_cars_list()


func _is_car_finalized(folder_name: String) -> bool:
	return finalized_cars.has(folder_name)


#  Car loading

func load_all_cars() -> void:
	loaded_cars.clear()

	print("[CarLoader] Scanning AC cars directory: %s" % cars_base_dir)
	_load_cars_from_root(cars_base_dir, false)

	print("[CarLoader] Scanning user cars directory: %s" % USER_CARS_ROOT)
	_load_cars_from_root(USER_CARS_ROOT, true)

	print("[CarLoader] Loaded %d cars total" % loaded_cars.size())


func _load_cars_from_root(root_dir: String, is_user_space: bool) -> void:
	var dir := DirAccess.open(root_dir)
	if dir == null:
		if not is_user_space:
			push_error("Failed to open cars directory: %s" % root_dir)
		return

	var car_folders := dir.get_directories()
	print("[CarLoader] [%s] Found %d folders" % [root_dir, car_folders.size()])

	var acd_extractor := AcdExtractor.new()
	var extracted_count := 0

	for folder_name in car_folders:
		if not is_user_space and (folder_name.begins_with("__cm") or folder_name.begins_with("_cm") or folder_name.contains("cm_tmp_")):
			continue

		# Skip if this is a userdata car that's been finalized
		if is_user_space and _is_car_finalized(folder_name):
			continue
		
		# Skip if this is an AC folder car that matches a finalized custom car
		if not is_user_space and folder_name.begins_with(CUSTOM_PREFIX):
			if _is_car_finalized(folder_name):
				# Load it normally - it's the finalized version
				pass
			else:
				# Skip - there might be an unfinalized version in userdata
				continue

		var car_dir := root_dir.path_join(folder_name)
		var data_dir := car_dir.path_join("data")
		var data_acd := car_dir.path_join("data.acd")

		# Extract ACD if data folder doesn't exist but data.acd does
		if not DirAccess.dir_exists_absolute(data_dir) and FileAccess.file_exists(data_acd):
			print("[CarLoader] Extracting data.acd for: %s" % folder_name)
			acd_extractor.extract_acd_to_data(car_dir)
			extracted_count += 1

		if not DirAccess.dir_exists_absolute(data_dir):
			continue

		var original_id := ""
		if is_user_space and folder_name.begins_with(CUSTOM_PREFIX):
			original_id = folder_name.substr(CUSTOM_PREFIX.length())

			# Make sure patched
			var abs_dir := ProjectSettings.globalize_path(car_dir)
			_patch_car_ini_labels(abs_dir)
			_patch_ui_car_json_labels(abs_dir)

		_load_car(car_dir, is_user_space, original_id)
	
	if extracted_count > 0:
		print("[CarLoader] Extracted %d data.acd files" % extracted_count)
	
	for carthing in loaded_cars:
		carthing._store_stock_values()
		_classify_drivetrain_archetype(carthing)

func _apply_drivetrain_archetype(car: Car, archetype_id: String) -> bool:
	if not drivetrain_archetypes.has(archetype_id):
		push_error("Unknown drivetrain archetype: %s" % archetype_id)
		return false
	
	var archetype = drivetrain_archetypes[archetype_id]
	var custom_abs := _get_custom_abs_dir_for(car)
	var car_data_dir := custom_abs.path_join("data")
	
	# Copy all files from archetype to car data directory
	var archetype_abs := ProjectSettings.globalize_path(archetype["path"])
	
	for file in archetype["files"]:
		var src := archetype_abs.path_join(file)
		var dst := car_data_dir.path_join(file)
		
		var f_src := FileAccess.open(src, FileAccess.READ)
		if f_src == null:
			push_warning("Failed to open archetype file: %s" % src)
			continue
		
		var data := f_src.get_buffer(f_src.get_length())
		f_src.close()
		
		var f_dst := FileAccess.open(dst, FileAccess.WRITE)
		if f_dst == null:
			push_warning("Failed to write archetype file: %s" % dst)
			continue
		
		f_dst.store_buffer(data)
		f_dst.close()
		
		print("[CarLoader] Copied archetype file: %s" % file)
	
	# Reload drivetrain from the new files
	var dt := car.get_node_or_null("Drivetrain") as Drivetrain
	if dt:
		dt.load_from_data_dir(car_data_dir)
		dt.current_archetype = archetype_id
	
	return true


func _remove_drivetrain_archetype(car: Car) -> bool:
	var dt := car.get_node_or_null("Drivetrain") as Drivetrain
	if dt == null:
		return false
	
	var old_archetype_id := dt.current_archetype
	if not drivetrain_archetypes.has(old_archetype_id):
		return false
	
	var custom_abs := _get_custom_abs_dir_for(car)
	var car_data_dir := custom_abs.path_join("data")
	
	# Get original car to restore files from
	var orig_id := car.original_id
	if orig_id == "":
		push_error("Cannot remove drivetrain: no original car reference")
		return false
	
	var orig_car = get_car(orig_id)
	if orig_car == null:
		push_error("Cannot find original car: %s" % orig_id)
		return false
	
	var orig_abs := ProjectSettings.globalize_path(orig_car.car_dir)
	var orig_data_dir := orig_abs.path_join("data")
	
	# Delete archetype files that don't exist in original
	var archetype = drivetrain_archetypes[old_archetype_id]
	for file in archetype["files"]:
		var orig_file := orig_data_dir.path_join(file)
		var custom_file := car_data_dir.path_join(file)
		
		# If file doesn't exist in original, delete it
		if not FileAccess.file_exists(orig_file):
			if FileAccess.file_exists(custom_file):
				DirAccess.remove_absolute(custom_file)
				print("[CarLoader] Removed archetype file: %s" % file)
	
	# Restore original drivetrain.ini
	var orig_dt_ini := orig_data_dir.path_join("drivetrain.ini")
	var custom_dt_ini := car_data_dir.path_join("drivetrain.ini")
	
	if FileAccess.file_exists(orig_dt_ini):
		var f_src := FileAccess.open(orig_dt_ini, FileAccess.READ)
		if f_src:
			var data := f_src.get_buffer(f_src.get_length())
			f_src.close()
			
			var f_dst := FileAccess.open(custom_dt_ini, FileAccess.WRITE)
			if f_dst:
				f_dst.store_buffer(data)
				f_dst.close()
				print("[CarLoader] Restored original drivetrain.ini")
	
	# Reload drivetrain
	if dt:
		dt.load_from_data_dir(car_data_dir)
		dt.current_archetype = dt.stock_archetype
	
	return true

func _load_car(car_dir: String, is_custom: bool = false, original_id: String = "") -> Car:
	var CarScene := preload("res://scenes/car/car.tscn")
	var car := CarScene.instantiate() as Car
	car.car_dir = car_dir
	car.is_custom = is_custom
	car.original_id = original_id

	add_child(car)
	loaded_cars.append(car)
	return car

func find_car(car, id):
	return car.car_id == id
	
func get_car(id):
	var index = loaded_cars.find_custom(find_car.bind(id))
	return loaded_cars.get(index)

#  Helpers for custom cars

func _is_custom_car(car: Car) -> bool:
	return car.is_custom or car.car_dir.begins_with(USER_CARS_ROOT)


func _get_original_folder_name(car: Car) -> String:
	var base := car.car_dir.replace("\\", "/").rstrip("/")
	var folder := base.get_file()
	if folder.begins_with(CUSTOM_PREFIX):
		return folder.substr(CUSTOM_PREFIX.length())
	return folder


func _get_custom_virtual_dir_for(car: Car) -> String:
	var orig_folder := _get_original_folder_name(car)
	return USER_CARS_ROOT.path_join("%s%s" % [CUSTOM_PREFIX, orig_folder])


func _get_custom_abs_dir_for(car: Car) -> String:
	return ProjectSettings.globalize_path(_get_custom_virtual_dir_for(car))


func _find_loaded_custom_for_original(orig_folder: String) -> Car:
	for c in loaded_cars:
		if _is_custom_car(c):
			var base := c.car_dir.replace("\\", "/").rstrip("/")
			var folder := base.get_file()
			if folder == "%s%s" % [CUSTOM_PREFIX, orig_folder]:
				return c
	return null


func _ensure_dir_exists_abs(abs_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(abs_path)


func _copy_dir_recursive(src_abs: String, dst_abs: String) -> void:
	var src_dir := DirAccess.open(src_abs)
	if src_dir == null:
		printerr("Failed to open source dir for copy: ", src_abs)
		return

	DirAccess.make_dir_recursive_absolute(dst_abs)

	src_dir.list_dir_begin()
	while true:
		var dirname := src_dir.get_next()
		if dirname == "":
			break
		if dirname == "." or dirname == "..":
			continue

		var src_path := src_abs.path_join(dirname)
		var dst_path := dst_abs.path_join(dirname)

		if src_dir.current_is_dir():
			_copy_dir_recursive(src_path, dst_path)
		else:
			var f_src := FileAccess.open(src_path, FileAccess.READ)
			if f_src == null:
				continue
			var data := f_src.get_buffer(f_src.get_length())
			f_src.close()

			var f_dst := FileAccess.open(dst_path, FileAccess.WRITE)
			if f_dst == null:
				continue
			f_dst.store_buffer(data)
			f_dst.close()

	src_dir.list_dir_end()


func _get_or_create_custom_car(original_car: Car) -> Car:
	var orig_base := original_car.car_dir.replace("\\", "/").rstrip("/")
	var orig_folder := orig_base.get_file()

	# already-loaded custom
	var existing := _find_loaded_custom_for_original(orig_folder)
	if existing != null:
		var exist_abs := _get_custom_abs_dir_for(original_car)
		_patch_car_ini_labels(exist_abs)
		_patch_ui_car_json_labels(exist_abs)
		print("loading existing custom car : " + original_car.screen_name)
		return existing

	# directory exists but not loaded
	var custom_virtual := _get_custom_virtual_dir_for(original_car)
	var custom_abs := _get_custom_abs_dir_for(original_car)

	if DirAccess.dir_exists_absolute(custom_abs):
		_patch_car_ini_labels(custom_abs)
		_patch_ui_car_json_labels(custom_abs)
		print("loading existing custom car : " + original_car.screen_name)
		var loaded := _load_car(custom_virtual, true, orig_folder)
		loaded._store_stock_values()
		_classify_drivetrain_archetype(loaded)
		return loaded

	#  create new copy
	_ensure_dir_exists_abs(ProjectSettings.globalize_path(USER_CARS_ROOT))
	_copy_dir_recursive(orig_base, custom_abs)
	print("creating custom version of : " + original_car.screen_name)

	_patch_car_ini_labels(custom_abs)
	_patch_ui_car_json_labels(custom_abs)
	var custom_car := _load_car(custom_virtual, true, orig_folder)
	custom_car.parent_unmodified_car = original_car
	custom_car._store_stock_values()
	_classify_drivetrain_archetype(custom_car)
	print("custom car created and now loaded : " + custom_car.screen_name)
	return custom_car

func _write_engine_ini(data_dir: String, eng: CarEngine) -> bool:
	var engine_ini_path := data_dir.path_join("engine.ini")
	print("[CarLoader] Writing engine.ini to: %s" % engine_ini_path)
	
	var text := ""
	
	# [HEADER]
	text += "[HEADER]\n"
	text += "VERSION=1\n"
	var curve_name := eng.power_curve_file if eng.power_curve_file != "" else "power.lut"
	text += "POWER_CURVE=%s\n" % curve_name
	if eng.coast_curve_mode != "":
		text += "COAST_CURVE=%s\n" % eng.coast_curve_mode
	
	# Add swap info as comment
	if eng.is_swapped:
		text += "; ENGINE_SWAP_SOURCE=%s\n" % eng.swap_source_car_id
	
	text += "\n"
	
	# [ENGINE_DATA]
	text += "[ENGINE_DATA]\n"
	text += "ALTITUDE_SENSITIVITY=%.3f\n" % eng.altitude_sensitivity
	text += "INERTIA=%.3f\n" % eng.inertia
	text += "LIMITER=%d\n" % eng.limiter
	text += "LIMITER_HZ=%d\n" % eng.limiter_hz
	text += "MINIMUM=%d\n" % eng.minimum_rpm
	
	# Add DEFAULT_TURBO_ADJUSTMENT if we have a turbo
	if eng.has_turbo():
		text += "DEFAULT_TURBO_ADJUSTMENT=0.5\n"
	
	var hp_mult := eng.get_hp_multiplier()
	text += "; TUNER_POWER=%.0f bhp (mult=%.3f)\n" % [eng.current_hp, hp_mult]
	text += "\n"
	
	# [COAST_REF]
	text += "[COAST_REF]\n"
	text += "RPM=%.0f\n" % eng.coast_ref_rpm
	text += "TORQUE=%.1f\n" % eng.coast_ref_torque
	text += "NON_LINEARITY=%.3f\n" % eng.coast_ref_non_linearity
	text += "\n"
	
	# [COAST_DATA]
	text += "[COAST_DATA]\n"
	text += "COAST0=%.6f\n" % eng.coast0
	text += "COAST1=%.6f\n" % eng.coast1
	text += "COAST=%.6f\n" % eng.coast
	text += "\n"
	
	# [COAST_CURVE]
	text += "[COAST_CURVE]\n"
	if eng.coast_curve_file != "":
		text += "FILENAME=%s\n" % eng.coast_curve_file
	else:
		text += "FILENAME=coast.lut\n"
	text += "\n"
	
	# [TURBO_*] sections
	# Check if we have an upgraded turbo part installed
	var turbo_part_id = eng.installed_parts.get(110, 0)
	
	if turbo_part_id > 0:
		# We have an upgraded turbo part installed
		var turbo_part = eng._get_part_by_id(turbo_part_id)
		if not turbo_part.is_empty():
			text += "[TURBO_0]\n"
			
			# Calculate turbo parameters based on the part's multiplier
			var turbo_mult := float(turbo_part.get("mult", 1.0))
			var stage := int(turbo_part.get("stage", 1))
			
			# Scale turbo parameters based on stage
			var lag_dn := 0.95 - (stage - 1) * 0.05  # Faster response at higher stages
			var lag_up := 0.97 - (stage - 1) * 0.05
			var max_boost := 0.3 + (stage - 1) * 0.4  # More boost at higher stages
			var wastegate := 0.5 + (stage - 1) * 0.2
			var gamma := 1.0 + (stage - 1) * 0.2
			
			text += "LAG_DN=%.3f\n" % lag_dn
			text += "LAG_UP=%.3f\n" % lag_up
			text += "MAX_BOOST=%.2f\n" % max_boost
			text += "WASTEGATE=%.2f\n" % wastegate
			text += "DISPLAY_MAX_BOOST=%.2f\n" % max_boost
			
			# Calculate reference RPM based on limiter
			var ref_rpm := int(eng.limiter * 0.7)
			text += "REFERENCE_RPM=%d\n" % ref_rpm
			text += "GAMMA=%.2f\n" % gamma
			text += "COCKPIT_ADJUSTABLE=0\n"
			text += "\n"
			
			# Adjust damage thresholds for upgraded turbo
			text += "[DAMAGE]\n"
			text += "TURBO_BOOST_THRESHOLD=%.2f\n" % (max_boost + 0.2)
			text += "TURBO_DAMAGE_K=5.0\n"
			text += "RPM_THRESHOLD=%.0f\n" % eng.rpm_threshold
			text += "RPM_DAMAGE_K=%.3f\n" % eng.rpm_damage_k
			text += "\n"
	elif eng.has_stock_turbo and not eng.turbos.is_empty():
		# Write stock turbos
		for i in range(eng.turbos.size()):
			var t = eng.turbos[i]
			text += "[TURBO_%d]\n" % i
			text += "LAG_DN=%.4f\n" % float(t["lag_dn"])
			text += "LAG_UP=%.4f\n" % float(t["lag_up"])
			text += "MAX_BOOST=%.3f\n" % float(t["max_boost"])
			text += "WASTEGATE=%.2f\n" % float(t["wastegate"])
			text += "DISPLAY_MAX_BOOST=%.3f\n" % float(t["display_max_boost"])
			text += "REFERENCE_RPM=%d\n" % int(t["reference_rpm"])
			text += "GAMMA=%.3f\n" % float(t["gamma"])
			text += "COCKPIT_ADJUSTABLE=%d\n" % (1 if bool(t["cockpit_adjustable"]) else 0)
			text += "\n"
		
		# [DAMAGE]
		text += "[DAMAGE]\n"
		if eng.turbo_boost_threshold > 0.0:
			text += "TURBO_BOOST_THRESHOLD=%.3f\n" % eng.turbo_boost_threshold
			text += "TURBO_DAMAGE_K=%.3f\n" % eng.turbo_damage_k
		text += "RPM_THRESHOLD=%.0f\n" % eng.rpm_threshold
		text += "RPM_DAMAGE_K=%.3f\n" % eng.rpm_damage_k
		text += "\n"
	else:
		# No turbo at all - just write damage section
		text += "[DAMAGE]\n"
		text += "RPM_THRESHOLD=%.0f\n" % eng.rpm_threshold
		text += "RPM_DAMAGE_K=%.3f\n" % eng.rpm_damage_k
		text += "\n"
	
	var f := FileAccess.open(engine_ini_path, FileAccess.WRITE)
	if f == null:
		push_error("Failed to open engine.ini for writing: %s" % engine_ini_path)
		return false
	
	f.store_string(text)
	f.close()
	
	print("[CarLoader] Successfully wrote engine.ini")
	return true

func _write_power_lut(data_dir: String, eng: CarEngine) -> bool:
	var curve_name := eng.power_curve_file if eng.power_curve_file != "" else "power.lut"
	var lut_path := data_dir.path_join(curve_name)
	
	if eng.power_curve.is_empty():
		print("[CarLoader] Engine has no power_curve data, skipping power.lut write")
		return true  # fine I guess?
	
	var mult := eng.get_hp_multiplier()
	print("[CarLoader] Writing power LUT to: %s (multiplier=%.3f)" % [lut_path, mult])
	
	var f := FileAccess.open(lut_path, FileAccess.WRITE)
	if f == null:
		push_error("Failed to open power LUT for writing: %s" % lut_path)
		return false
	
	for p in eng.power_curve:
		var rpm := int(round(p.x))
		var torque := float(p.y) * mult
		f.store_line("%d|%.2f" % [rpm, torque])
	
	f.close()
	
	print("[CarLoader] Successfully wrote power.lut")
	return true

func _patch_ui_car_json_power(custom_car_abs_dir: String, car: Car) -> void:
	var ui_path := custom_car_abs_dir.path_join("ui").path_join("ui_car.json")
	if not FileAccess.file_exists(ui_path):
		print("[CarLoader] ui_car.json not found for power patch: %s" % ui_path)
		return
	
	var f := FileAccess.open(ui_path, FileAccess.READ)
	if f == null:
		push_warning("Failed to open ui_car.json for power patch: %s" % ui_path)
		return
	
	var text := f.get_as_text()
	f.close()
	
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_warning("Failed to parse ui_car.json (power patch): %s" % ui_path)
		return
	
	var root = json.data
	if typeof(root) != TYPE_DICTIONARY:
		return
	
	var eng := car.get_node_or_null("Engine") as CarEngine
	if eng == null:
		return
	
	var hp := eng.current_hp
	if hp <= 0.0:
		hp = eng.estimated_hp
	if hp <= 0.0:
		return
	
	# specs.bhp, specs.pwratio, specs.weight
	var specs = root.get("specs", {})
	if typeof(specs) != TYPE_DICTIONARY:
		specs = {}
	
	specs["bhp"] = "%d bhp" % int(round(hp))
	
	if car.total_mass > 0.0:
		var kg_per_hp := car.total_mass / hp
		specs["pwratio"] = "%.2f kg/hp" % kg_per_hp

		var total_with_driver := int(round(car.total_mass))
		specs["weight"] = "%d kg*" % total_with_driver
	
	root["specs"] = specs
	
	# powerCurve & torqueCurve
	#  Prefer rescaling existing torqueCurve from JSON
	#  Fallback: use eng.power_curve, skipping negative RPMs
	var mult := eng.get_hp_multiplier()
	if mult <= 0.0:
		mult = 1.0
	
	var new_tcurve: Array = []
	var new_pcurve: Array = []
	
	var existing_tcurve = root.get("torqueCurve", null)
	
	if typeof(existing_tcurve) == TYPE_ARRAY and existing_tcurve.size() > 0:
		# Re-use original UI grid, just scale torque by multiplier
		for pt in existing_tcurve:
			if not (pt is Array) or pt.size() < 2:
				continue
			
			var rpm_raw = pt[0]
			var tq_raw = pt[1]
			
			# Handle string or numeric
			var rpm := float(str(rpm_raw))
			var torque := float(str(tq_raw)) * mult
			
			# UI: skip negative RPM points
			if rpm < 0.0:
				continue
			
			var bhp_pt: float = 0.0
			if rpm > 0.0:
				bhp_pt = torque * rpm / 7127.0
			
			new_tcurve.append([rpm, torque])
			new_pcurve.append([rpm, bhp_pt])
	else:
		# Fallback: build curves from physics LUT (eng.power_curve), but skip negative RPMs
		if not eng.power_curve.is_empty():
			for p in eng.power_curve:
				var rpm := float(p.x)
				var torque := float(p.y) * mult
				
				if rpm < 0.0:
					continue
				
				var bhp_pt: float = 0.0
				if rpm > 0.0:
					bhp_pt = torque * rpm / 7127.0
				
				new_tcurve.append([rpm, torque])
				new_pcurve.append([rpm, bhp_pt])
	# Save electronics metadata
	var electronics := car.get_node_or_null("Electronics") as Electronics
	if electronics:
		root["js_tuner_electronics"] = electronics.get_tuner_metadata()
	if new_tcurve.size() > 0 and new_pcurve.size() > 0:
		root["torqueCurve"] = new_tcurve
		root["powerCurve"] = new_pcurve
	
	# Store tuner metadata so we can restore upgrade state later
	var tuner_meta := {
		"stock_hp": eng.stock_hp,
		"current_hp": eng.current_hp,
		"installed_parts": eng.installed_parts,
	}
	root["js_tuner"] = tuner_meta
	var brakes := car.get_node_or_null("Brakes") as Brakes
	if brakes:
		root["js_tuner_brakes"] = brakes.get_tuner_metadata()
	var out_text := JSON.stringify(root, "\t")
	var fw := FileAccess.open(ui_path, FileAccess.WRITE)
	if fw == null:
		push_warning("Failed to write ui_car.json (power patch): %s" % ui_path)
		return
	fw.store_string(out_text)
	fw.close()
	
	print("[CarLoader] Patched ui_car.json power/curves & tuner meta for: %s" % ui_path)


func _write_engine_files(car: Car) -> bool:
	var eng := car.get_node_or_null("Engine") as CarEngine
	if eng == null:
		print("[CarLoader] No Engine node found, skipping engine.ini/power.lut/ui_car.json")
		return true
	
	var custom_abs := _get_custom_abs_dir_for(car)
	var data_dir := custom_abs.path_join("data")
	
	var ok_ini := _write_engine_ini(data_dir, eng)
	var ok_lut := _write_power_lut(data_dir, eng)
	
	# Update ui_car.json to match new power + curves + store tuner metadata
	_patch_ui_car_json_power(custom_abs, car)
	
	return ok_ini and ok_lut


#  FINALIZE CAR BUILD

func finalize_car_build(car: Car) -> bool:
	if not car.is_custom:
		push_error("Cannot finalize a non-custom car!")
		return false
	
	var orig_folder := _get_original_folder_name(car)
	var custom_folder := "%s%s" % [CUSTOM_PREFIX, orig_folder]
	
	# Write brakes.ini with current values
	if not _write_brakes_ini(car):
		push_error("Failed to write brakes.ini")
		return false
	
	# Write engine.ini + power.lut with upgraded values
	if not _write_engine_files(car):
		push_error("Failed to write engine.ini / power.lut")
		return false
	#  Write electronics.ini
	if not _write_electronics_ini(car):
		push_error("Failed to write electronics.ini")
		return false
	# Write tyres.ini with upgrade compounds appended
	if not _write_tyres_ini(car):
		push_error("Failed to write tyres.ini")
		return false
	#  Ensure electronics LUTs are present if referenced
	_ensure_electronics_luts_present(car)
	# Rename soundbank file to match new car ID
	var src_abs := _get_custom_abs_dir_for(car)
	if not _rename_soundbank(src_abs, custom_folder):
		push_warning("Failed to rename soundbank (non-critical)")
	
	# Patch GUIDs.txt to use the custom car ID
	_patch_guids_for_custom(src_abs, orig_folder, custom_folder)
	
	#  Build data.acd from data folder
	if not _build_acd_file(src_abs):
		push_error("Failed to build data.acd")
		return false
	
	# Copy custom car folder to AC cars directory
	var dst_abs := cars_base_dir.path_join(custom_folder)
	
	print("[CarLoader] Finalizing car: %s" % car.screen_name)
	print("[CarLoader] Source: %s" % src_abs)
	print("[CarLoader] Destination: %s" % dst_abs)
	
	_copy_dir_recursive(src_abs, dst_abs)
	
	#  Mark as finalized
	_mark_car_finalized(custom_folder)
	
	print("[CarLoader] Car finalized successfully!")
	return true
	
func _patch_existing_local_guids(guids_path: String, old_id: String, new_id: String) -> void:
	var f := FileAccess.open(guids_path, FileAccess.READ)
	if f == null:
		push_warning("Failed to open GUIDs.txt for reading: %s" % guids_path)
		return

	var text := f.get_as_text()
	f.close()

	var lines: Array = text.split("\n", false)
	var new_lines: Array = []

	var bank_old_pattern := " bank:/%s" % old_id
	var bank_new_pattern := " bank:/%s" % new_id
	var event_old_prefix := "event:/cars/%s/" % old_id
	var event_new_prefix := "event:/cars/%s/" % new_id

	var saw_custom_bank := false

	for line in lines:
		var original_line = line
		var trimmed = line.strip_edges()

		if trimmed == "":
			new_lines.append(original_line)
			continue

		if bank_new_pattern in original_line:
			saw_custom_bank = true
			new_lines.append(original_line)
			continue

		if bank_old_pattern in original_line:
			if not saw_custom_bank:
				var rewritten = original_line.replace(bank_old_pattern, bank_new_pattern)
				new_lines.append(rewritten)
				saw_custom_bank = true
			continue

		if event_old_prefix in original_line:
			original_line = original_line.replace(event_old_prefix, event_new_prefix)

		new_lines.append(original_line)

	var out_text := "\n".join(new_lines)
	var fw := FileAccess.open(guids_path, FileAccess.WRITE)
	if fw == null:
		push_warning("Failed to open GUIDs.txt for writing: %s" % guids_path)
		return

	fw.store_string(out_text)
	fw.close()

	print("[CarLoader] Patched existing GUIDs.txt for custom car: %s" % new_id)


func _create_local_guids_from_shared(sfx_dir: String, old_id: String, new_id: String) -> void:
	if ac_root_path == "":
		push_warning("AC root path unknown, cannot read shared GUIDs.txt")
		return

	var shared_guids_path := ac_root_path.path_join("content/sfx/GUIDs.txt")
	if not FileAccess.file_exists(shared_guids_path):
		push_warning("Shared GUIDs.txt not found: %s" % shared_guids_path)
		return

	var f := FileAccess.open(shared_guids_path, FileAccess.READ)
	if f == null:
		push_warning("Failed to open shared GUIDs.txt: %s" % shared_guids_path)
		return

	var text := f.get_as_text()
	f.close()

	var lines: Array = text.split("\n", false)
	var new_lines: Array = []

	var bank_old_pattern := " bank:/%s" % old_id
	var bank_new_pattern := " bank:/%s" % new_id
	var event_old_prefix := "event:/cars/%s/" % old_id
	var event_new_prefix := "event:/cars/%s/" % new_id

	for line in lines:
		var trimmed = line.strip_edges()
		if trimmed == "":
			continue

		var matches_bank = bank_old_pattern in line
		var matches_event = event_old_prefix in line

		if not matches_bank and not matches_event:
			continue

		var out_line = line

		if matches_bank:
			out_line = out_line.replace(bank_old_pattern, bank_new_pattern)

		if matches_event:
			out_line = out_line.replace(event_old_prefix, event_new_prefix)

		new_lines.append(out_line)

	if new_lines.is_empty():
		print("[CarLoader] No entries found in shared GUIDs.txt for car '%s', skipping local GUIDs creation" % old_id)
		return

	var local_guids_path := sfx_dir.path_join("GUIDs.txt")
	var fw := FileAccess.open(local_guids_path, FileAccess.WRITE)
	if fw == null:
		push_warning("Failed to create local GUIDs.txt for custom car: %s" % local_guids_path)
		return

	fw.store_string("\n".join(new_lines) + "\n")
	fw.close()

	print("[CarLoader] Created local GUIDs.txt for custom car '%s' from shared GUIDs" % new_id)

func _patch_guids_for_custom(car_abs_dir: String, old_id: String, new_id: String) -> void:
	var sfx_dir := car_abs_dir.path_join("sfx")
	if not DirAccess.dir_exists_absolute(sfx_dir):
		print("[CarLoader] No sfx directory found, skipping GUIDs patch")
		return

	var guids_path := sfx_dir.path_join("GUIDs.txt")

	# If there is already a local GUIDs.txt (mods, some custom cars), patch it in-place.
	if FileAccess.file_exists(guids_path):
		_patch_existing_local_guids(guids_path, old_id, new_id)
		return

	# Otherwise, this is most likely a vanilla car whose GUIDs live in content/sfx/GUIDs.txt.
	# Create a local GUIDs.txt for the custom car by copying relevant lines from the shared file.
	_create_local_guids_from_shared(sfx_dir, old_id, new_id)
	
func _ensure_electronics_luts_present(car: Car) -> void:
	var elec := car.get_node_or_null("Electronics") as Electronics
	if elec == null:
		return

	var custom_abs := _get_custom_abs_dir_for(car)
	var data_dir := custom_abs.path_join("data")

	# If curve files are referenced..
	var orig_id := car.original_id
	if orig_id == "":
		return

	var orig_car = get_car(orig_id)
	if orig_car == null:
		return

	var orig_abs := ProjectSettings.globalize_path(orig_car.car_dir)
	var orig_data_dir := orig_abs.path_join("data")

	_copy_lut_if_missing(orig_data_dir, data_dir, elec.abs_curve_file)
	_copy_lut_if_missing(orig_data_dir, data_dir, elec.tc_curve_file)


func _copy_lut_if_missing(src_data_dir: String, dst_data_dir: String, filename: String) -> void:
	if filename == "":
		return

	var src := src_data_dir.path_join(filename)
	var dst := dst_data_dir.path_join(filename)

	if FileAccess.file_exists(dst):
		return
	if not FileAccess.file_exists(src):
		return

	var f_src := FileAccess.open(src, FileAccess.READ)
	if f_src == null:
		return
	var data := f_src.get_buffer(f_src.get_length())
	f_src.close()

	var f_dst := FileAccess.open(dst, FileAccess.WRITE)
	if f_dst == null:
		return
	f_dst.store_buffer(data)
	f_dst.close()

	print("[CarLoader] Copied LUT: %s" % filename)
	
func _write_tyres_ini(car: Car) -> bool:
	var tyres := car.get_node_or_null("Tyres") as Tyres
	if tyres == null:
		print("[CarLoader] No Tyres node found, skipping tyres.ini")
		return true

	var custom_abs := _get_custom_abs_dir_for(car)
	var data_dir := custom_abs.path_join("data")
	var tyres_ini_path := data_dir.path_join("tyres.ini")

	print("[CarLoader] Writing tyres.ini to: %s" % tyres_ini_path)

	var text := tyres.build_upgraded_tyres_ini_text()
	if text == "":
		push_warning("[CarLoader] Tyres returned empty ini text, skipping")
		return true

	var f := FileAccess.open(tyres_ini_path, FileAccess.WRITE)
	if f == null:
		push_error("Failed to open tyres.ini for writing: %s" % tyres_ini_path)
		return false

	f.store_string(text)
	f.close()

	print("[CarLoader] Successfully wrote tyres.ini")
	return true


func _write_electronics_ini(car: Car) -> bool:
	var elec = car.get_node_or_null("Electronics") as Electronics
	if elec == null:
		print("[CarLoader] No Electronics node found, skipping electronics.ini")
		return true

	var custom_abs := _get_custom_abs_dir_for(car)
	var data_dir := custom_abs.path_join("data")
	var electronics_ini_path := data_dir.path_join("electronics.ini")

	print("[CarLoader] Writing electronics.ini to: %s" % electronics_ini_path)

	# Keep curve references if present
	var text := ""

	text += "[ABS]\n"
	text += "SLIP_RATIO_LIMIT=%.2f\n" % elec.abs_slip_ratio_limit
	text += "CURVE=%s\n" % elec.abs_curve_file
	text += "PRESENT=%d\n" % elec.abs_present
	text += "ACTIVE=%d\n" % elec.abs_active
	text += "RATE_HZ=%d\n" % int(elec.abs_rate_hz)
	text += "\n"

	text += "[TRACTION_CONTROL]\n"
	text += "SLIP_RATIO_LIMIT=%.2f\n" % elec.tc_slip_ratio_limit
	text += "CURVE=%s\n" % elec.tc_curve_file
	text += "PRESENT=%d\n" % elec.tc_present
	text += "ACTIVE=%d\n" % elec.tc_active
	text += "RATE_HZ=%d\n" % int(elec.tc_rate_hz)
	text += "MIN_SPEED_KMH=%d\n" % int(elec.tc_min_speed_kmh)
	text += "\n"

	var f := FileAccess.open(electronics_ini_path, FileAccess.WRITE)
	if f == null:
		push_error("Failed to open electronics.ini for writing: %s" % electronics_ini_path)
		return false

	f.store_string(text)
	f.close()

	print("[CarLoader] Successfully wrote electronics.ini")
	return true

func _write_brakes_ini(car: Car) -> bool:
	var brakes := car.get_node_or_null("Brakes") as Brakes
	if brakes == null:
		push_error("Car has no Brakes node!")
		return false
	
	var custom_abs := _get_custom_abs_dir_for(car)
	var brakes_ini_path := custom_abs.path_join("data").path_join("brakes.ini")
	
	print("[CarLoader] Writing brakes.ini to: %s" % brakes_ini_path)
	
	# Build INI content
	var content := ""
	
	# [DATA] section
	content += "[DATA]\n"
	content += "MAX_TORQUE=%.0f\n" % brakes.max_torque
	content += "FRONT_SHARE=%.2f\n" % brakes.front_share
	content += "HANDBRAKE_TORQUE=%.0f\n" % brakes.handbrake_torque
	content += "COCKPIT_ADJUSTABLE=%d\n" % brakes.cockpit_adjustable
	content += "ADJUST_STEP=%.2f\n" % brakes.adjust_step
	content += "\n"
	
	# [DISCS_GRAPHICS] section
	content += "[DISCS_GRAPHICS]\n"
	content += "DISC_LF=%s\n" % brakes.disc_lf
	content += "DISC_RF=%s\n" % brakes.disc_rf
	content += "DISC_LR=%s\n" % brakes.disc_lr
	content += "DISC_RR=%s\n" % brakes.disc_rr
	content += "FRONT_MAX_GLOW=%.1f\n" % brakes.front_max_glow
	content += "REAR_MAX_GLOW=%.1f\n" % brakes.rear_max_glow
	content += "LAG_HOT=%.1f\n" % brakes.lag_hot
	content += "LAG_COOL=%.1f\n" % brakes.lag_cool
	
	# Write to file
	var file := FileAccess.open(brakes_ini_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open brakes.ini for writing: %s" % brakes_ini_path)
		return false
	
	file.store_string(content)
	file.close()
	
	print("[CarLoader] Successfully wrote brakes.ini")
	return true


func _build_acd_file(car_abs_dir: String) -> bool:
	var acd_builder := AcdBuilder.new()
	var success := acd_builder.build_acd_from_data(car_abs_dir)
	
	if not success:
		push_error("AcdBuilder failed to create data.acd for: %s" % car_abs_dir)
	
	return success


func _rename_soundbank(car_abs_dir: String, new_id: String) -> bool:
	var sfx_dir := car_abs_dir.path_join("sfx")
	
	if not DirAccess.dir_exists_absolute(sfx_dir):
		print("[CarLoader] No sfx directory found, skipping soundbank rename")
		return true  # Not an error, just no soundbank to rename
	
	# Look for .bank files in sfx directory
	var dir := DirAccess.open(sfx_dir)
	if dir == null:
		push_warning("Failed to open sfx directory: %s" % sfx_dir)
		return false
	
	var found_bank := ""
	dir.list_dir_begin()
	while true:
		var file := dir.get_next()
		if file == "":
			break
		if file.ends_with(".bank"):
			found_bank = file
			break
	dir.list_dir_end()
	
	if found_bank == "":
		print("[CarLoader] No .bank file found in sfx directory")
		return true 
	
	# Build new filename
	var old_bank_path := sfx_dir.path_join(found_bank)
	var new_bank_name := "%s.bank" % new_id
	var new_bank_path := sfx_dir.path_join(new_bank_name)
	
	# Skip if already correctly named
	if found_bank == new_bank_name:
		print("[CarLoader] Soundbank already correctly named: %s" % new_bank_name)
		return true
	
	print("[CarLoader] Renaming soundbank: %s -> %s" % [found_bank, new_bank_name])
	
	# Rename the file
	var err := DirAccess.rename_absolute(old_bank_path, new_bank_path)
	if err != OK:
		push_warning("Failed to rename soundbank: %s (error %d)" % [found_bank, err])
		return false
	
	print("[CarLoader] Successfully renamed soundbank")
	return true


#  UI

func setup_ui() -> void:
	if loaded_cars.is_empty():
		push_error("No cars loaded!")
		return

	var ui := $CarListUI as CarListUI
	if ui == null:
		push_error("CarListUI not found in scene!")
		return
	ui.show()
	ui.set_cars(loaded_cars)


func switch_to_tuner(current_car: Car) -> void:
	var car_to_edit := current_car

	if not _is_custom_car(current_car):
		car_to_edit = _get_or_create_custom_car(current_car)

	$CarTunerUI.set_car(car_to_edit)
	$CarListUI.hide()
	$CarListUI.set_process_input(false)
	$CarTunerUI.show()
	$CarTunerUI.set_process_input(true)


func return_to_car_list() -> void:
	$CarTunerUI.hide()
	$CarTunerUI.set_process_input(false)
	$CarListUI.show()
	$CarListUI.set_process_input(true)


func delete_car(car_id: String) -> void:
	print("[CarLoader] Attempting to delete car: %s" % car_id)
	
	# Find the car in loaded_cars
	var car: Car = null
	for c in loaded_cars:
		if c.car_id == car_id:
			car = c
			break
	
	if car == null:
		push_error("Car not found: %s" % car_id)
		return
	
	var deleted_something := false
	
	# Check if it's a custom car (starts with js_ prefix)
	if car_id.begins_with(CUSTOM_PREFIX):
		# Delete from userdata if it exists
		var userdata_path := ProjectSettings.globalize_path(USER_CARS_ROOT.path_join(car_id))
		if DirAccess.dir_exists_absolute(userdata_path):
			print("[CarLoader] Deleting from userdata: %s" % userdata_path)
			_delete_directory_recursive(userdata_path)
			deleted_something = true
		
		# Delete from AC folder if it exists
		var ac_path := cars_base_dir.path_join(car_id)
		if DirAccess.dir_exists_absolute(ac_path):
			print("[CarLoader] Deleting from AC folder: %s" % ac_path)
			_delete_directory_recursive(ac_path)
			
			# Remove from finalized list
			if finalized_cars.has(car_id):
				finalized_cars.erase(car_id)
				_save_finalized_cars_list()
			
			deleted_something = true
	else:
		# It's a stock car, we shouldn't delete it
		push_warning("Cannot delete stock car: %s" % car_id)
		return_to_car_list()
		return
	
	if deleted_something:
		# Remove from loaded_cars array
		loaded_cars.erase(car)
		
		# Remove the node from scene tree
		car.queue_free()
		
		print("[CarLoader] Successfully deleted car: %s" % car_id)
		
		# Return to car list and refresh
		return_to_car_list()
		
		# Refresh the car list UI
		var ui := $CarListUI as CarListUI
		if ui != null:
			ui.set_cars(loaded_cars)
	else:
		push_warning("No files found to delete for car: %s" % car_id)
		return_to_car_list()


func _delete_directory_recursive(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("Failed to open directory for deletion: %s" % dir_path)
		return
	
	# Delete all files and subdirectories
	dir.list_dir_begin()
	while true:
		var item := dir.get_next()
		if item == "":
			break
		if item == "." or item == "..":
			continue
		
		var item_path := dir_path.path_join(item)
		
		if dir.current_is_dir():
			# Recursively delete subdirectory
			_delete_directory_recursive(item_path)
		else:
			# Delete file
			var _err = DirAccess.remove_absolute(item_path)
			if _err != OK:
				push_warning("Failed to delete file: %s (error %d)" % [item_path, _err])
	
	dir.list_dir_end()
	
	# Delete the now-empty directory itself
	var err := DirAccess.remove_absolute(dir_path)
	if err != OK:
		push_error("Failed to delete directory: %s (error %d)" % [dir_path, err])
	else:
		print("[CarLoader] Deleted directory: %s" % dir_path)


#  Dialog callbacks

func _on_file_dialog_file_selected(path: String) -> void:
	if not path.ends_with("acs.exe"):
		$FileDialog.hide()
		$findacserror.popup_centered()
		return

	var ac_root := path.get_base_dir()
	var cars_dir := ac_root.path_join("content/cars")

	if not DirAccess.dir_exists_absolute(cars_dir):
		$FileDialog.hide()
		$findacserror.popup_centered()
		return

	_save_ac_root_path(ac_root)
	ac_root_path = ac_root
	cars_base_dir = cars_dir

	$FileDialog.hide()
	load_all_cars()
	setup_ui()


func _on_findacserror_canceled() -> void:
	get_tree().quit()


func _on_findacserror_confirmed() -> void:
	$findacserror.hide()
	$FileDialog.popup_centered()


#  Patching helpers (car.ini + ui_car.json)

func _patch_car_ini_labels(custom_car_abs_dir: String) -> void:
	var car_ini_path := custom_car_abs_dir.path_join("data").path_join("car.ini")
	if not FileAccess.file_exists(car_ini_path):
		return

	var f := FileAccess.open(car_ini_path, FileAccess.READ)
	if f == null:
		return

	var text := f.get_as_text()
	f.close()

	var lines := text.split("\n", false)
	var in_info := false

	for i in range(lines.size()):
		var line: String = lines[i]
		var trimmed := line.strip_edges()

		if trimmed.begins_with("[") and trimmed.ends_with("]"):
			in_info = (trimmed == "[INFO]")
			continue

		if not in_info:
			continue

		if trimmed.begins_with("SCREEN_NAME="):
			var parts := line.split("=", false, 1)
			var left := parts[0]
			var right := ""
			if parts.size() > 1:
				right = parts[1]

			var val_and_comment := right.split(";", false, 1)
			var value := ""
			var comment := ""
			if val_and_comment.size() > 0:
				value = val_and_comment[0].strip_edges()
			if val_and_comment.size() > 1:
				comment = ";" + val_and_comment[1]

			if not value.ends_with("CUSTOM EDITION"):
				value += " CUSTOM EDITION"

			lines[i] = "%s=%s%s" % [left, value, comment]

		elif trimmed.begins_with("SHORT_NAME="):
			var parts2 := line.split("=", false, 1)
			var left2 := parts2[0]
			var right2 := ""
			if parts2.size() > 1:
				right2 = parts2[1]

			var val_and_comment2 := right2.split(";", false, 1)
			var value2 := ""
			var comment2 := ""
			if val_and_comment2.size() > 0:
				value2 = val_and_comment2[0].strip_edges()
			if val_and_comment2.size() > 1:
				comment2 = ";" + val_and_comment2[1]

			if not value2.ends_with("CUSTOM"):
				value2 += " CUSTOM"

			lines[i] = "%s=%s%s" % [left2, value2, comment2]

	var out := FileAccess.open(car_ini_path, FileAccess.WRITE)
	if out == null:
		return

	out.store_string("\n".join(lines))
	out.close()


func _patch_ui_car_json_labels(custom_car_abs_dir: String) -> void:
	var ui_path := custom_car_abs_dir.path_join("ui").path_join("ui_car.json")
	if not FileAccess.file_exists(ui_path):
		return

	var f := FileAccess.open(ui_path, FileAccess.READ)
	if f == null:
		return

	var text := f.get_as_text()
	f.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_warning("Failed to parse ui_car.json when patching: %s" % ui_path)
		return

	var root = json.data
	if typeof(root) != TYPE_DICTIONARY:
		return

	var name_val := str(root.get("name", "")).strip_edges()
	if name_val == "":
		return

	if name_val.ends_with("CUSTOM EDITION"):
		return 

	name_val += " CUSTOM EDITION"
	root["name"] = name_val

	var out_text := JSON.stringify(root, "\t")
	var fw := FileAccess.open(ui_path, FileAccess.WRITE)
	if fw == null:
		return
	fw.store_string(out_text)
	fw.close()
