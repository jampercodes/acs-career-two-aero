# fuel_cons.gd
extends Node
class_name FuelCons

var km_per_liter: float = 0.0

func store_stock_values():
	pass

func load_from_data_dir(data_dir: String) -> void:
	var ini := IniParser.parse_file(data_dir + "/fuel_cons.ini")
	if ini.has("FUEL_EVAL"):
		var f = ini["FUEL_EVAL"]
		km_per_liter = IniParser.get_float(f, "KM_PER_LITER", 0.0)
