class_name StartMenu
extends CanvasLayer
## Practice, host or join. Command-line arguments skip this: -- practice, -- host, -- join <ip>.

signal practice_chosen
signal host_chosen
signal join_chosen(address: String)

var _address: LineEdit
var _message: Label

func _ready() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0.03, 0.75)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(340, 0)
	box.position -= Vector2(170, 150)
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var title := Label.new()
	title.text = "ATC RAYCRASH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.6, 0.85, 1))
	box.add_child(title)

	_button(box, "Practice against a target", func() -> void: practice_chosen.emit())
	_button(box, "Host a match (player 1)", func() -> void: host_chosen.emit())

	var row := HBoxContainer.new()
	box.add_child(row)
	_address = LineEdit.new()
	_address.text = "127.0.0.1"
	_address.placeholder_text = "host address"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_address)
	_button(row, "Join (player 2)", func() -> void: join_chosen.emit(_address.text.strip_edges()))

	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color", Color(1, 0.6, 0.5))
	box.add_child(_message)

func _button(parent: Control, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	parent.add_child(b)

func show_message(text: String) -> void:
	_message.text = text
