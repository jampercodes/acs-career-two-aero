# escmode.gd
extends Node
class_name EscMode

var position: Vector3 = Vector3.ZERO
var fov: float = 60.0

func store_stock_values():
	pass

func load_from_data_dir(data_dir: String) -> void:
	var ini := IniParser.parse_file(data_dir + "/escmode.ini")
	if ini.has("SETTINGS"):
		var s = ini["SETTINGS"]
		position = IniParser.parse_vec3(IniParser.get_str(s, "POSITION", "0,0,0"))
		fov = IniParser.get_float(s, "FOV", 60.0)
