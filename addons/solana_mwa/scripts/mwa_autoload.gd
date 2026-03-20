extends Node
## MWA Autoload — provides a global MobileWalletAdapter instance.
## Access via MWA singleton: MWA.adapter.authorize()

var adapter: MobileWalletAdapter

func _ready() -> void:
	adapter = MobileWalletAdapter.new()
	adapter.name = "MobileWalletAdapter"
	add_child(adapter)
