extends CanvasLayer
## Local menu only: block this map's input without pausing the whole SceneTree.
## A future network transport/simulation can continue processing while it is open.

@onready var overlay: Control = $Overlay
var _previous_focus: Control

func _ready() -> void:
	$Overlay/Center/Panel/Content/MainMenuButton.pressed.connect(_return_to_menu)
	$Overlay/Center/Panel/Content/ExitButton.pressed.connect(func(): get_tree().quit())
	overlay.hide()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		if not overlay.visible and get_parent().has_method("dismiss_order_menu") and get_parent().dismiss_order_menu():
			return
		set_menu_open(not overlay.visible)

func set_menu_open(is_open: bool) -> void:
	if overlay.visible == is_open:
		return
	overlay.visible = is_open
	# SceneTree.paused would freeze a future TCP poller; disable only map input.
	var map_view: Control = get_parent().get_node("%USMap")
	map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE if is_open else Control.MOUSE_FILTER_STOP
	if is_open:
		_previous_focus = get_viewport().gui_get_focus_owner()
		map_view._set_hovered("")
		$Overlay/Center/Panel/Content/MainMenuButton.grab_focus()
	else:
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null and overlay.is_ancestor_of(focused):
			focused.release_focus()
		if is_instance_valid(_previous_focus):
			_previous_focus.grab_focus()

func _return_to_menu() -> void:
	var result: Error = get_node("/root/GameSession").return_to_main_menu()
	if result != OK:
		$Overlay/Center/Panel/Content/Hint.text = "无法返回主菜单：" + error_string(result)
