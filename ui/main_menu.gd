extends Control
## Host / Join menu. Hosting also works as offline practice.

@onready var _status: Label = %Status
@onready var _address: LineEdit = %Address


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	%Name.text = Net.player_name
	%Host.pressed.connect(func(): _save_name(); Net.host(false))
	%Join.pressed.connect(func(): _save_name(); Net.join(_address.text))
	_address.text_submitted.connect(func(t): _save_name(); Net.join(t))
	%Quit.pressed.connect(func(): get_tree().quit())
	_status.text = Net.last_status
	Net.status_changed.connect(func(t): _status.text = t)


func _save_name() -> void:
	Net.set_player_name(%Name.text)
