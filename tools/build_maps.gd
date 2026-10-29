@tool
extends EditorScript
## Rebuilds every map in maps/source/ after you edit it in TrenchBroom.
## Open this file in the Script editor and choose File → Run (Ctrl+Shift+X).

func _run() -> void:
	for f in DirAccess.get_files_at("res://maps/source/"):
		if f.get_extension() == "map":
			MapBuilder.build(f.get_basename())
	EditorInterface.get_resource_filesystem().scan()
