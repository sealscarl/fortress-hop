extends Control
## Host / Join menu. Hosting also works as offline practice.

@onready var _status: Label = %Status
@onready var _address: LineEdit = %Address


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	%Host.pressed.connect(func(): Net.host(false))
	%Join.pressed.connect(func(): Net.join(_address.text))
	_address.text_submitted.connect(func(t): Net.join(t))
	%Quit.pressed.connect(func(): get_tree().quit())
	_status.text = Net.last_status
	Net.status_changed.connect(func(t): _status.text = t)
