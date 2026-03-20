@tool
extends EditorPlugin

func _enter_tree() -> void:
	add_autoload_singleton("MWA", "res://addons/solana_mwa/scripts/mwa_autoload.gd")

func _exit_tree() -> void:
	remove_autoload_singleton("MWA")
