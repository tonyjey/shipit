extends StaticBody3D
## Прилавок магазина. Холодная комната: часы здесь не идут,
## поэтому дорога сюда никого не наказывает.


func _ready() -> void:
	add_to_group("interactable")


func can_focus(_p) -> bool:
	return true


func get_prompt(_p) -> String:
	return "[E] Магазин навыков   ·   у тебя $%d" % Boot.wallet


func get_target() -> Array:
	return ["shop", 0]
