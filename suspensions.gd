# suspensions.gd
extends Node
class_name Suspensions

# [BASIC]
var wheelbase: float = 0.0
var cg_location: float = 0.0

# [ARB]
var arb_front: float = 0.0
var arb_rear: float = 0.0

class Axle:
	var type: String = ""
	var base_y: float = 0.0
	var track: float = 0.0
	var rod_length: float = 0.0
	var hub_mass: float = 0.0
	var rim_offset: float = 0.0

	var wbcar_top_front: Vector3 = Vector3.ZERO
	var wbcar_top_rear: Vector3 = Vector3.ZERO
	var wbcar_bottom_front: Vector3 = Vector3.ZERO
	var wbcar_bottom_rear: Vector3 = Vector3.ZERO
	var wbtyre_top: Vector3 = Vector3.ZERO
	var wbtyre_bottom: Vector3 = Vector3.ZERO
	var wbcar_steer: Vector3 = Vector3.ZERO
	var wbtyre_steer: Vector3 = Vector3.ZERO

	var toe_out: float = 0.0
	var static_camber: float = 0.0
	var spring_rate: float = 0.0
	var progressive_spring_rate: float = 0.0
	var bump_stop_rate: float = 0.0
	var bumpstop_up: float = 0.0
	var bumpstop_dn: float = 0.0
	var packer_range: float = 0.0
	var damp_bump: float = 0.0
	var damp_fast_bump: float = 0.0
	var damp_fast_bump_threshold: float = 0.0
	var damp_rebound: float = 0.0
	var damp_fast_rebound: float = 0.0
	var damp_fast_rebound_threshold: float = 0.0

var front: Axle = Axle.new()
var rear: Axle = Axle.new()

# [GRAPHICS_OFFSETS]
var wheel_lf: float = 0.0
var susp_lf: float = 0.0
var wheel_rf: float = 0.0
var susp_rf: float = 0.0
var wheel_lr: float = 0.0
var susp_lr: float = 0.0
var wheel_rr: float = 0.0
var susp_rr: float = 0.0

# [DAMAGE]
var damage_min_velocity: float = 0.0
var damage_gain: float = 0.0
var damage_max_damage: float = 0.0
var damage_debug_log: int = 0

func store_stock_values():
	pass

func load_from_data_dir(data_dir: String) -> void:
	var ini := IniParser.parse_file(data_dir + "/suspensions.ini")

	if ini.has("BASIC"):
		var b = ini["BASIC"]
		wheelbase = IniParser.get_float(b, "WHEELBASE", 0.0)
		cg_location = IniParser.get_float(b, "CG_LOCATION", 0.0)

	if ini.has("ARB"):
		var a = ini["ARB"]
		arb_front = IniParser.get_float(a, "FRONT", 0.0)
		arb_rear = IniParser.get_float(a, "REAR", 0.0)

	if ini.has("FRONT"):
		_load_axle(front, ini["FRONT"])
	if ini.has("REAR"):
		_load_axle(rear, ini["REAR"])

	if ini.has("GRAPHICS_OFFSETS"):
		var g = ini["GRAPHICS_OFFSETS"]
		wheel_lf = IniParser.get_float(g, "WHEEL_LF", 0.0)
		susp_lf = IniParser.get_float(g, "SUSP_LF", 0.0)
		wheel_rf = IniParser.get_float(g, "WHEEL_RF", 0.0)
		susp_rf = IniParser.get_float(g, "SUSP_RF", 0.0)
		wheel_lr = IniParser.get_float(g, "WHEEL_LR", 0.0)
		susp_lr = IniParser.get_float(g, "SUSP_LR", 0.0)
		wheel_rr = IniParser.get_float(g, "WHEEL_RR", 0.0)
		susp_rr = IniParser.get_float(g, "SUSP_RR", 0.0)

	if ini.has("DAMAGE"):
		var d = ini["DAMAGE"]
		damage_min_velocity = IniParser.get_float(d, "MIN_VELOCITY", 0.0)
		damage_gain = IniParser.get_float(d, "GAIN", 0.0)
		damage_max_damage = IniParser.get_float(d, "MAX_DAMAGE", 0.0)
		damage_debug_log = IniParser.get_int(d, "DEBUG_LOG", 0)

func _load_axle(axle: Axle, sec: Dictionary) -> void:
	axle.type = IniParser.get_str(sec, "TYPE", "")
	axle.base_y = IniParser.get_float(sec, "BASEY", 0.0)
	axle.track = IniParser.get_float(sec, "TRACK", 0.0)
	axle.rod_length = IniParser.get_float(sec, "ROD_LENGTH", 0.0)
	axle.hub_mass = IniParser.get_float(sec, "HUB_MASS", 0.0)
	axle.rim_offset = IniParser.get_float(sec, "RIM_OFFSET", 0.0)

	axle.wbcar_top_front = IniParser.parse_vec3(IniParser.get_str(sec, "WBCAR_TOP_FRONT", "0,0,0"))
	axle.wbcar_top_rear = IniParser.parse_vec3(IniParser.get_str(sec, "WBCAR_TOP_REAR", "0,0,0"))
	axle.wbcar_bottom_front = IniParser.parse_vec3(IniParser.get_str(sec, "WBCAR_BOTTOM_FRONT", "0,0,0"))
	axle.wbcar_bottom_rear = IniParser.parse_vec3(IniParser.get_str(sec, "WBCAR_BOTTOM_REAR", "0,0,0"))
	axle.wbtyre_top = IniParser.parse_vec3(IniParser.get_str(sec, "WBTYRE_TOP", "0,0,0"))
	axle.wbtyre_bottom = IniParser.parse_vec3(IniParser.get_str(sec, "WBTYRE_BOTTOM", "0,0,0"))
	axle.wbcar_steer = IniParser.parse_vec3(IniParser.get_str(sec, "WBCAR_STEER", "0,0,0"))
	axle.wbtyre_steer = IniParser.parse_vec3(IniParser.get_str(sec, "WBTYRE_STEER", "0,0,0"))

	axle.toe_out = IniParser.get_float(sec, "TOE_OUT", 0.0)
	axle.static_camber = IniParser.get_float(sec, "STATIC_CAMBER", 0.0)
	axle.spring_rate = IniParser.get_float(sec, "SPRING_RATE", 0.0)
	axle.progressive_spring_rate = IniParser.get_float(sec, "PROGRESSIVE_SPRING_RATE", 0.0)
	axle.bump_stop_rate = IniParser.get_float(sec, "BUMP_STOP_RATE", 0.0)
	axle.bumpstop_up = IniParser.get_float(sec, "BUMPSTOP_UP", 0.0)
	axle.bumpstop_dn = IniParser.get_float(sec, "BUMPSTOP_DN", 0.0)
	axle.packer_range = IniParser.get_float(sec, "PACKER_RANGE", 0.0)
	axle.damp_bump = IniParser.get_float(sec, "DAMP_BUMP", 0.0)
	axle.damp_fast_bump = IniParser.get_float(sec, "DAMP_FAST_BUMP", 0.0)
	axle.damp_fast_bump_threshold = IniParser.get_float(sec, "DAMP_FAST_BUMPTHRESHOLD", 0.0)
	axle.damp_rebound = IniParser.get_float(sec, "DAMP_REBOUND", 0.0)
	axle.damp_fast_rebound = IniParser.get_float(sec, "DAMP_FAST_REBOUND", 0.0)
	axle.damp_fast_rebound_threshold = IniParser.get_float(sec, "DAMP_FAST_REBOUNDTHRESHOLD", 0.0)
