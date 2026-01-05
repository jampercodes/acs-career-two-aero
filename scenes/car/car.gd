# car.gd
extends Node2D
class_name Car

@export var car_dir: String = ""

# Identity / custom flags
@export var car_id: String = ""        # usually the folder name
@export var original_id: String = ""   # base folder name without js_ prefix
@export var is_custom: bool = false    # true if this is a user-space clone

var preview_image_path: String = ""
var _preview_texture: Texture2D = null

# Basic car.ini values
var screen_name: String = ""
var graphics_offset: Vector3 = Vector3.ZERO
var graphics_pitch_rotation: float = 0.0
var total_mass: float = 0.0
var inertia: Vector3 = Vector3.ZERO
var current_turbo_tier = 0
var parent_unmodified_car = null

@onready var aero = $Aero
@onready var engine = $Engine
@onready var brakes = $Brakes
@onready var suspensions = $Suspensions
@onready var drivetrain = $Drivetrain
@onready var electronics = $Electronics
@onready var tyres = $Tyres
@onready var generalupgrades = $General

# PERFORMANCE METRICS
# Raw ratios
var pw_ratio_hp_per_kg: float = 0.0
var pw_ratio_hp_per_ton: float = 0.0
# aero
var aero_downforce_ratio_200: float = 0.0
var aero_cornering_index: float = 0.0       # 1–10 from aero only
# tyre / mechanical grip metrics
var tyre_cornering_index: float = 0.0       # 1–10 from tyres only (best compound)
var w_tyre := 0.7
var w_aero := 0.3

# Indices (1–10)
var power_index: float = 0.0
var braking_index: float = 0.0
var cornering_index: float = 0.0

# unified
var wc = 0.5
var wb = 0.15
var wp = 0.35
var performance_index: float = 0.0

func _ready() -> void:
	if car_dir != "":
		load_from_folder(car_dir)


func load_from_folder(car_dir_path: String) -> void:
	car_dir = car_dir_path
	var base := car_dir_path.replace("\\", "/").rstrip("/")
	var folder_name := base.get_file()
	# print("loading car : " + folder_name)
	car_id = folder_name
	if folder_name.begins_with("js_"):
		original_id = folder_name.substr(3)
	else:
		original_id = folder_name

	var data_dir := base + "/data"

	# CAR.INI
	var car_ini_path := data_dir + "/car.ini"
	var ini := IniParser.parse_file(car_ini_path)
	_load_car_ini(ini)

	# UI name from ui_car.json, with fallback to car.ini SCREEN_NAME
	_load_ui_name(base, ini)

	# If this is a custom clone, make sure UI name shows it
	if is_custom and screen_name != "":
		if not screen_name.ends_with(" CUSTOM EDITION"):
			screen_name = "%s CUSTOM EDITION" % screen_name
	
	if has_node("Aero"):
		aero.load_from_data_dir(data_dir)
	if has_node("Engine"):
		engine.load_from_data_dir(data_dir)
	if has_node("Brakes"):
		brakes.load_from_data_dir(data_dir)
		# classify brakes on the base values
		brakes.classify_brakes(self)
	if has_node("Suspensions"):
		suspensions.load_from_data_dir(data_dir)
	if has_node("Drivetrain"):
		drivetrain.load_from_data_dir(data_dir)
	if has_node("Electronics"):
		electronics.load_from_data_dir(data_dir)
	if has_node("Tyres"):
		tyres.load_from_data_dir(data_dir)
	if has_node("GeneralUpgrades"):
		generalupgrades.load_from_data_dir(data_dir)

	# Once all parts are loaded, compute performance metrics
	_compute_performance_metrics()
	preview_image_path = _find_preview_image_path(base)

func _store_stock_values():
	if has_node("Brakes"):
		brakes.store_stock_values()
	var stocktyres := get_node_or_null("Tyres") as Tyres
	if stocktyres:
		stocktyres.store_stock_values()
	if has_node("GeneralUpgrades"):
		generalupgrades.store_stock_values()

func _load_car_ini(ini: Dictionary) -> void:
	# Only physics / layout stuff.
	var global_sec: Dictionary = ini.get("GLOBAL", {})

	# BASIC
	var secb: Dictionary
	if ini.has("BASIC"):
		secb = ini["BASIC"]
	else:
		secb = global_sec  # fallback

	graphics_offset = IniParser.parse_vec3(
		IniParser.get_str(secb, "GRAPHICS_OFFSET", "0,0,0")
	)
	graphics_pitch_rotation = IniParser.get_float(secb, "GRAPHICS_PITCH_ROTATION", 0.0)
	total_mass = IniParser.get_float(secb, "TOTALMASS", total_mass)
	inertia = IniParser.parse_vec3(
		IniParser.get_str(secb, "INERTIA", "0,0,0")
	)


func _find_preview_image_path(base_dir: String) -> String:
	var skins_dir := base_dir + "/skins"
	if not DirAccess.dir_exists_absolute(skins_dir):
		return ""

	var d := DirAccess.open(skins_dir)
	if d == null:
		return ""

	for skin_name in d.get_directories():
		if skin_name == "." or skin_name == "..":
			continue

		var skin_dir := skins_dir + "/" + skin_name
		var png_path := skin_dir + "/preview.png"
		var jpg_path := skin_dir + "/preview.jpg"

		if FileAccess.file_exists(png_path):
			return png_path
		if FileAccess.file_exists(jpg_path):
			return jpg_path

	return ""

func get_preview_texture(max_size: int = 1024) -> Texture2D:
	# Cache
	if _preview_texture != null:
		return _preview_texture

	if preview_image_path == "":
		return null

	var img := Image.new()
	var err := img.load(preview_image_path)
	if err != OK:
		printerr("Failed to load preview image: ", preview_image_path, " (err ", err, ")")
		return null

	# Downscale to reduce VRAM usage (key for low-end GPUs)
	var w := img.get_width()
	var h := img.get_height()
	if w > max_size or h > max_size:
		var scale := float(max_size) / float(max(w, h))
		var nw := int(round(w * scale))
		var nh := int(round(h * scale))
		img.resize(nw, nh, Image.INTERPOLATE_LANCZOS)

	# Ensure sane format (optional but helpful)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)

	var tex := ImageTexture.create_from_image(img)
	_preview_texture = tex
	return _preview_texture

func clear_preview_cache() -> void:
	_preview_texture = null

func _load_ui_name(base_dir: String, ini: Dictionary) -> void:
	# Try ui/ui_car.json first
	var ui_path := base_dir + "/ui/ui_car.json"
	var name_from_json := ""

	if FileAccess.file_exists(ui_path):
		var f := FileAccess.open(ui_path, FileAccess.READ)
		if f != null:
			var text := f.get_as_text()
			f.close()

			var json := JSON.new()
			var err := json.parse(text)
			if err == OK:
				var root = json.data
				if typeof(root) == TYPE_DICTIONARY:
					name_from_json = str(root.get("name", "")).strip_edges()

	# If JSON name exists, use it
	if name_from_json != "":
		screen_name = name_from_json
		return

	# Fallback: use SCREEN_NAME from car.ini if present
	var global_sec: Dictionary = ini.get("GLOBAL", {})
	var sec
	if ini.has("INFO"):
		sec = ini["INFO"]
	else:
		sec = global_sec

	var ini_name := IniParser.get_str(sec, "SCREEN_NAME", "").strip_edges()
	if ini_name != "":
		screen_name = ini_name


func _load_preview_sprite(base_dir: String) -> void:
	if not has_node("Preview"):
		return

	var preview_node = get_node("Preview")

	var skins_dir := base_dir + "/skins"
	if not DirAccess.dir_exists_absolute(skins_dir):
		return

	var d := DirAccess.open(skins_dir)
	if d == null:
		return

	var found_path := ""

	for skin_name in d.get_directories():
		if skin_name == "." or skin_name == "..":
			continue

		var skin_dir := skins_dir + "/" + skin_name
		var png_path := skin_dir + "/preview.png"
		var jpg_path := skin_dir + "/preview.jpg"

		if FileAccess.file_exists(png_path):
			found_path = png_path
			break
		elif FileAccess.file_exists(jpg_path):
			found_path = jpg_path
			break

	if found_path == "":
		return

	var img := Image.new()
	var err := img.load(found_path)
	if err != OK:
		printerr("Failed to load preview image: ", found_path, " (err ", err, ")")
		return

	var tex := ImageTexture.create_from_image(img)

	if preview_node is Sprite2D:
		(preview_node as Sprite2D).texture = tex
	elif preview_node is Sprite3D:
		(preview_node as Sprite3D).texture = tex
	elif preview_node is TextureRect:
		(preview_node as TextureRect).texture = tex
	else:
		printerr("Preview node is not a known sprite type: ", preview_node)


# PERFORMANCE METRIC CALCS

func _compute_performance_metrics() -> void:
	# Reset first
	pw_ratio_hp_per_kg = 0.0
	pw_ratio_hp_per_ton = 0.0
	power_index = 0.0
	braking_index = 0.0
	tyre_cornering_index = 0.0
	aero_cornering_index = 0.0
	cornering_index = 0.0
	performance_index = 0.0
	aero_downforce_ratio_200 = 0.0

	if total_mass <= 0.0:
		return

	# Power-related 
	if has_node("Engine"):
		var hp = engine.estimated_hp

		if hp > 0.0:
			pw_ratio_hp_per_kg = hp / total_mass
			pw_ratio_hp_per_ton = pw_ratio_hp_per_kg * 1000.0

			var min_pw := 0.1    # hp per kg ~ slow hatch
			var max_pw := 1.0    # hp per kg ~ Koenigsegg 1:1 / LMP1
			var pw := pw_ratio_hp_per_kg
			var norm_pw := (pw - min_pw) / (max_pw - min_pw)
			power_index = clamp(1.0 + 9.0 * norm_pw, 1.0, 10.0)

	# Braking-related
	if has_node("Brakes"):
		var max_torque = brakes.max_torque

		if max_torque > 0.0:
			var brake_ratio = max_torque / total_mass
			var min_ratio := 0.5     # weak old stuff
			var max_ratio := 4.0     # serious race brakes
			var norm_br = (brake_ratio - min_ratio) / (max_ratio - min_ratio)
			braking_index = clamp(1.0 + 9.0 * norm_br, 1.0, 10.0)
	
	var drivetrain_index := 1.0
	if has_node("Drivetrain"):
		var dt := drivetrain as Drivetrain
		
		# AWD bonus for traction, RWD neutral, FWD slight penalty
		match dt.traction_type:
			"AWD":
				drivetrain_index = 1.2  # 20% bonus
			"RWD":
				drivetrain_index = 1.0  # Neutral
			"FWD":
				drivetrain_index = 0.90 # 10% penalty

	# Apply drivetrain multiplier to power and cornering
	if drivetrain_index != 1.0:
		power_index *= drivetrain_index
		cornering_index *= drivetrain_index
		
		# Keep within 1-10 range
		power_index = clamp(power_index, 1.0, 10.0)
		cornering_index = clamp(cornering_index, 1.0, 10.0)
	
	# Tyre / mechanical grip (best compound)
	if has_node("Tyres"):
		tyre_cornering_index = tyres.best_mechanical_grip_index
	else:
		tyre_cornering_index = 0.0

	# Aero / downforce contribution 
	if has_node("Aero"):
		if aero.ref_downforce_N > 0.0:
			var weight_N := total_mass * 9.81
			if weight_N > 0.0:
				var raw_ratio = aero.ref_downforce_N / weight_N
				aero_downforce_ratio_200 = max(raw_ratio, 0.0)

				var max_df := 1.0
				var norm_df = clamp(aero_downforce_ratio_200 / max_df, 0.0, 1.0)

				var gamma := 0.7
				norm_df = pow(norm_df, gamma)

				aero_cornering_index = clamp(1.0 + 9.0 * norm_df, 1.0, 10.0)
		else:
			aero_cornering_index = 1.0   # treat as "no aero"
	else:
		aero_cornering_index = 0.0

	# Combined cornering index (tyres + aero)
	if tyre_cornering_index > 0.0 and aero_cornering_index > 0.0:
		cornering_index = clamp(
			tyre_cornering_index * w_tyre + aero_cornering_index * w_aero,
			1.0,
			10.0
		)
	elif tyre_cornering_index > 0.0:
		cornering_index = tyre_cornering_index
	elif aero_cornering_index > 0.0:
		cornering_index = aero_cornering_index
	else:
		cornering_index = 0.0

	# Overall performance index (weighted)
	var sum := 0.0
	var weight_sum := 0.0

	if cornering_index > 0.0:
		sum += cornering_index * wc
		weight_sum += wc

	if power_index > 0.0:
		sum += power_index * wp
		weight_sum += wp

	if braking_index > 0.0:
		sum += braking_index * wb
		weight_sum += wb

	if weight_sum > 0.0:
		performance_index = sum / weight_sum
	else:
		performance_index = 0.0
