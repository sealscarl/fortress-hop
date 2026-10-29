extends Node
## Autoload "Net": hosting, joining and leaving games.
##
## Command-line shortcuts (handy for testing two copies on one PC):
##   --host               host and play
##   --server             dedicated server (no local player)
##   --join=192.168.1.20  join that address (no address = this PC)
##   --map=test_hop       which map to host (see MAPS)

const PORT := 27500          ## QuakeWorld's classic port.
const MAX_PLAYERS := 16
## Maps you can host. The first one is the default.
const MAPS := {
	"Phantom (CTF)": "res://maps/ff-phantom/ff-phantom.tscn",
	"Test Hop (movement)": "res://maps/test_hop.tscn",
}
const MENU := "res://ui/main_menu.tscn"

signal status_changed(text: String)

var dedicated := false
var last_status := ""
var player_name := "Player"
## The map being played (the server tells clients which one to load).
var current_map: String = MAPS.values()[0]


func _ready() -> void:
	multiplayer.server_disconnected.connect(func(): leave("Lost connection to the server."))
	multiplayer.connection_failed.connect(func(): leave("Couldn't connect to the server."))
	_load_name()
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with("--name="):
			player_name = arg.get_slice("=", 1)
		elif arg.begins_with("--map="):
			var want := arg.get_slice("=", 1)
			for path in MAPS.values():
				if want in path:
					current_map = path
		elif arg == "--host":
			host.call_deferred(false)
		elif arg == "--server":
			host.call_deferred(true)
		elif arg.begins_with("--join"):
			var ip := arg.get_slice("=", 1) if "=" in arg else "127.0.0.1"
			join.call_deferred(ip)


func host(p_dedicated := false, map_path := "") -> void:
	if map_path:
		current_map = map_path
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		_set_status("Couldn't host on port %d (is another copy already hosting?)" % PORT)
		return
	dedicated = p_dedicated
	multiplayer.multiplayer_peer = peer
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if dedicated:
		print("Dedicated server running on port %d, map %s" % [PORT, current_map])
	get_tree().change_scene_to_file(current_map)


## Server: a client connected. Tell it which map to load; it reports back
## (Game._client_ready) once loaded, and only then gets a player.
func _on_peer_connected(id: int) -> void:
	_load_map.rpc_id(id, current_map)


@rpc("authority", "call_remote", "reliable")
func _load_map(path: String) -> void:
	if not path in MAPS.values():
		leave("The server is running a map this version doesn't have.")
		return
	current_map = path
	get_tree().change_scene_to_file(path)


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
	# The server tells us which map to load once we're connected.


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


const _SETTINGS := "user://settings.cfg"


func set_player_name(n: String) -> void:
	n = n.strip_edges().substr(0, 24)
	if n.is_empty():
		return
	player_name = n
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS)
	cfg.set_value("player", "name", n)
	cfg.save(_SETTINGS)


func _load_name() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS) == OK:
		player_name = cfg.get_value("player", "name", player_name)
