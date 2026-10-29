extends Node
## Autoload "Net": hosting, joining and leaving games.
##
## Command-line shortcuts (handy for testing two copies on one PC):
##   --host               host and play
##   --server             dedicated server (no local player)
##   --join=192.168.1.20  join that address (no address = this PC)

const PORT := 27500          ## QuakeWorld's classic port.
const MAX_PLAYERS := 16
const MAP := "res://maps/test_hop.tscn"
const MENU := "res://ui/main_menu.tscn"

signal status_changed(text: String)

var dedicated := false
var last_status := ""


func _ready() -> void:
	multiplayer.server_disconnected.connect(func(): leave("Lost connection to the server."))
	multiplayer.connection_failed.connect(func(): leave("Couldn't connect to the server."))
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg == "--host":
			host.call_deferred(false)
		elif arg == "--server":
			host.call_deferred(true)
		elif arg.begins_with("--join"):
			var ip := arg.get_slice("=", 1) if "=" in arg else "127.0.0.1"
			join.call_deferred(ip)


func host(p_dedicated := false) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		_set_status("Couldn't host on port %d (is another copy already hosting?)" % PORT)
		return
	dedicated = p_dedicated
	multiplayer.multiplayer_peer = peer
	if dedicated:
		print("Dedicated server running on port %d" % PORT)
	get_tree().change_scene_to_file(MAP)


func join(address: String) -> void:
	address = address.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		_set_status("Couldn't start connecting to %s." % address)
		return
	dedicated = false
	multiplayer.multiplayer_peer = peer
	_set_status("Connecting to %s..." % address)
	# Load the map right away so it's ready when the server starts sending players.
	get_tree().change_scene_to_file(MAP)


func leave(reason := "") -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	dedicated = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_status(reason)
	get_tree().change_scene_to_file(MENU)


func _set_status(text: String) -> void:
	last_status = text
	status_changed.emit(text)
