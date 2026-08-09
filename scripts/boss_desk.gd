extends StaticBody3D
## Кабинет начальника. Здесь берут новый контракт — часы в этот момент стоят,
## поэтому дорога сюда никого не наказывает. Сдача игры осталась на сборке.


func _ready() -> void:
	add_to_group("interactable")


func can_focus(_p) -> bool:
	return true


func get_prompt(_p) -> String:
	if Game.naming or Game.voting:
		return "Начальник ждёт название игры"
	if Game.testing:
		return "Сначала закончите тестирование"
	if Game.contract_running:
		return "Контракт №%d в работе — иди работай" % int(Game.contract.get("index", 1))
	return "[E] Взять контракт №%d" % (Game.difficulty + 1)


func get_target() -> Array:
	return ["board", 0]
