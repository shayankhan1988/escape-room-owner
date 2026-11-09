extends StaticBody3D
## Anything the player can look at and press E on.

var prompt: String = ""
var on_use: Callable
var enabled: bool = true

func use() -> void:
	if enabled and on_use.is_valid():
		on_use.call()
