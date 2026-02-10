extends Control

var _curent_face = 1
var _last_face = null

var _face_node = null
var _next_buton = null

var _wing = null
var _wing_pos = Vector3(0, 0, 0)

var _cam_settings = {"fov": 10, "pos": Vector3(-20, 1.2, 0), "width": 1920, "height": 1080}

# Called when the node enters the scene tree for the first time.
func _ready():
	_face_node = [get_node("face 1"), get_node("face 2")]
	_next_buton = get_node("next") as Button
	_wing = get_node("face 1/wing") as Node

	_last_face = _face_node.size()

	_next_buton.pressed.connect(_next_buton_pressed)

func _next_buton_pressed():
	if _last_face == _curent_face:
		_finish_placement()
		return

	_curent_face += 1

	if _last_face == _curent_face:
		_next_buton.text = "finish"

	_face_node[_curent_face - 2].visible = false
	_face_node[_curent_face - 1].visible = true

	# calk the wing pos
	var px = _wing.position.x - _cam_settings["width"] * 0.5
	var py = _cam_settings["height"] * 0.5 - _wing.position.y  # flip Y

	var dir = Vector3(
		1.0,
		py / _cam_settings["fov"],
		px / _cam_settings["fov"]
	)

	dir.y -= _cam_settings["pos"].y / _cam_settings["fov"]

	dir = dir.normalized()

	var origin: Vector3 = _cam_settings["pos"]

	# Avoid division by zero (ray parallel to plane)
	if abs(dir.x) < 0.00001:
		return Vector3.ZERO

	var t = (0 - origin.x) / dir.x

	print(origin + dir * t)

	return


func _finish_placement():
	get_tree().quit()
