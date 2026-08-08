extends StaticBody3D
## Доска контрактов. Между релизами игра ничего не начинает сама —
## контракт берут отсюда, чтобы была пауза перевести дух.


func can_focus(_p) -> bool:
	return true


func get_prompt(_p) -> String:
	if Game.testing:
		return "Идёт тестирование — доска подождёт"
	if Game.contract_running:
		return "Контракт №%d в работе" % int(Game.contract.get("index", 1))
	return "[E] Взять контракт №%d" % (Game.difficulty + 1)


func get_target() -> Array:
	return ["board", 0]
