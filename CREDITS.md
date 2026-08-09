# Благодарности и лицензии

## Музыка
**Not Jam Music Pack** — https://not-jam.itch.io/not-jam-music-pack
Трек `audio/music/theme_loop.ogg` играет в офисе.
Автор не требует обязательного упоминания, но упоминание здесь оставлено
намеренно: если позже условия изменятся или проект пойдёт в публикацию,
источник должен быть известен без раскопок.

## 3D-модель
**Ретро-компьютер** (`models/pc.glb`) — сделан Amon в Blender по собственному
скрипту `retro_90s_computer_blender.py`. Скрипт лежит в `tools/`.
Исходник экспортирован из FBX в glTF, чтобы Godot импортировал его
без внешнего конвертера. Папка `tools/` помечена файлом `.gdignore`
и движком не сканируется.

**Дискета** (`models/floppy.glb`) — сделана Amon в Blender по скрипту
`tools/stylized_35_floppy_disk_blender.py`. Экспорт сразу в glTF.

**Сборочная машина** (`models/assembler.glb`) — сделана Amon в Blender
по техзаданию из `tools/ASSEMBLER_SPEC.md`.

## Звуковые эффекты
`audio/*.wav` синтезированы программно для этого проекта, сторонних прав нет.

## Движок
Godot Engine 4.7 — MIT License, https://godotengine.org
