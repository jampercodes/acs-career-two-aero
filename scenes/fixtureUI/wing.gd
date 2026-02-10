extends TextureRect

var _dragging = false
var _ofset = Vector2(0, 0)



# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if _dragging:
		position = get_global_mouse_position() - _ofset


func _on_button_button_down():
	_dragging = true
	_ofset = get_global_mouse_position() - global_position


func _on_button_button_up():
	_dragging = false
