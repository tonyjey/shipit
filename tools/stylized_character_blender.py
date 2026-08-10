"""
============================================================
STYLIZED GAME CHARACTER - NO ARMATURE (v2)
Blender 4.x  |  height exactly 1.70 m  |  front +Y  |  Z up
============================================================

Как это устроено
----------------
Вся модель описана одной таблицей RIG (секция между маркерами
RIG SPEC START/END). Таблица — чистый Python, без bpy: её можно
прочитать и пересчитать любым сторонним скриптом. Билдер ниже
просто обходит таблицу.

Три правила, на которых держится анимация кодом:

1. loc у каждого узла — ЛОКАЛЬНЫЕ координаты относительно сустава
   родителя. matrix_parent_inverse остаётся единичной. Поэтому
   мировая поза = цепочка родительских трансформов, ровно как в
   glTF. Ничего не «уезжает» при повторном парентинге и при экспорте.

2. Геометрия каждого объекта построена в его локальной системе,
   сустав = (0,0,0). Origin физически стоит в суставе.

3. Rest-поворот у ВСЕХ объектов нулевой, локальные оси совпадают
   с мировыми. Значит:
       rotation_euler.x  > 0  -> мах вперёд (+Y)
       rotation_euler.x  < 0  -> мах назад
       rotation_euler.z       -> поворот вокруг вертикали
       rotation_euler.y       -> разведение в стороны
   Никаких «а почему рука крутится не туда».

Пример анимации кодом — функция demo_pose() в конце файла.
"""

import math

# ------------------------------------------------------------
# Настройки
# ------------------------------------------------------------
HEIGHT = 1.70
CLEAN_SCENE = True          # снести всё из сцены перед сборкой
EXPORT_GLB_PATH = "C:/Users/tonyj/Documents/game-game/models/character.glb"        # укажи путь -> экспортнёт .glb
EXPORT_YUP = True           # True = стандартный glTF (Y-up).
                            # False = сырой Z-up, ломает большинство импортёров.
SMOOTH_HEAD = True

MATERIALS = {
    #  имя            цвет RGBA                        roughness
    "Char_Body":   ((0.43, 0.48, 0.52, 1.0), 0.68),
    "Char_Head":   ((0.48, 0.53, 0.57, 1.0), 0.68),
    "Char_Collar": ((0.90, 0.89, 0.84, 1.0), 0.68),
    "Char_Tie":    ((0.65, 0.08, 0.06, 1.0), 0.68),
    "Char_Eyes":   ((0.015, 0.012, 0.010, 1.0), 0.35),
    "Char_Shoes":  ((0.055, 0.055, 0.050, 1.0), 0.68),
}


# ============================================================
# --- RIG SPEC START ---   (чистый Python, без bpy)
# ============================================================

# Мировые Z суставов. Меняешь тут — меняется вся модель.
ANKLE_Z    = 0.10
KNEE_Z     = 0.51
HIP_Z      = 0.92
SHOULDER_Z = 1.34
ELBOW_Z    = 1.08
WRIST_Z    = 0.84
NECK_Z     = 1.42

HEAD_R     = 0.21           # радиус головы
HEAD_C_Z   = 1.49           # центр головы -> макушка = 1.49 + 0.21 = 1.70

HIP_X      = 0.12
SHOULDER_X = 0.23

THIGH   = HIP_Z - KNEE_Z            # 0.41
SHIN    = KNEE_Z - ANKLE_Z          # 0.41
UPPER_A = SHOULDER_Z - ELBOW_Z      # 0.26
FORE_A  = ELBOW_Z - WRIST_Z         # 0.24

TORSO_BOTTOM = 0.90
TORSO_TOP    = NECK_Z               # 1.42
TORSO_H      = TORSO_TOP - TORSO_BOTTOM

# Воротник шире головы (0.44 против шара 0.42), иначе он целиком
# прячется внутри силуэта головы и базовый атрибут не читается.
COLLAR_Z     = 1.36
COLLAR_W     = 0.44
TIE_KNOT_Z   = 1.30
TIE_Y        = 0.150


def build_rig():
    """Возвращает список узлов в порядке иерархии.

    Ключи узла:
      name, parent, loc        - локальная позиция относительно родителя
      boxes  [(center,size)]   - геометрия из коробок, локально
      sphere (center, radius)  - геометрия-шар, локально
      mat, bevel, role
      empty=True               - пустышка-аттачпоинт
    """
    R = []

    def node(name, parent, loc, role, mat=None, boxes=None,
             sphere=None, bevel=0.02, empty=False, smooth=False):
        R.append(dict(name=name, parent=parent, loc=tuple(loc), role=role,
                      mat=mat, boxes=boxes or [], sphere=sphere,
                      bevel=bevel, empty=empty, smooth=smooth))

    # ---------------- корень / таз ----------------
    node("Character_ROOT", None, (0, 0, 0),
         "начало координат, между ступнями на полу", empty=True)

    node("Hips", "Character_ROOT", (0, 0, HIP_Z),
         "таз; origin в тазобедренном центре", "Char_Body",
         boxes=[((0, 0, 0), (0.34, 0.24, 0.18))], bevel=0.045)

    # ---------------- корпус ----------------
    node("Torso", "Hips", (0, 0, 0),
         "корпус; origin в тазу", "Char_Body",
         boxes=[((0, 0, TORSO_BOTTOM + TORSO_H / 2 - HIP_Z),
                 (0.42, 0.28, TORSO_H))], bevel=0.06)

    node("Collar", "Torso", (0, 0, COLLAR_Z - HIP_Z),
         "воротник; origin в основании шеи", "Char_Collar",
         boxes=[((0, 0, 0), (COLLAR_W, 0.30, 0.08))], bevel=0.022)

    node("Tie", "Torso", (0, TIE_Y, TIE_KNOT_Z - HIP_Z),
         "галстук; origin в узле", "Char_Tie",
         boxes=[((0, 0, 0), (0.085, 0.055, 0.080)),          # узел
                ((0, 0, -0.140), (0.080, 0.040, 0.200))],    # полотно
         bevel=0.014)

    # ---------------- голова ----------------
    node("Head", "Torso", (0, 0, NECK_Z - HIP_Z),
         "голова; origin в шее", "Char_Head",
         sphere=((0, 0, HEAD_C_Z - NECK_Z), HEAD_R), smooth=True)

    for side, sx in (("L", -1), ("R", 1)):
        node("Eye_%s" % side, "Head", (sx * 0.08, 0.185, HEAD_C_Z - NECK_Z + 0.04),
             "глаз", "Char_Eyes", sphere=((0, 0, 0), 0.030), smooth=True)

    node("Head_Top", "Head", (0, 0, HEIGHT - NECK_Z),
         "макушка; точка крепления шапок", empty=True)

    # ---------------- руки ----------------
    for side, sx in (("L", -1), ("R", 1)):
        node("Arm_%s_Upper" % side, "Torso",
             (sx * SHOULDER_X, 0, SHOULDER_Z - HIP_Z),
             "%s плечо; origin в плечевом суставе" % side, "Char_Body",
             boxes=[((0, 0, -UPPER_A / 2), (0.11, 0.11, UPPER_A))], bevel=0.024)

        node("Arm_%s_Lower" % side, "Arm_%s_Upper" % side, (0, 0, -UPPER_A),
             "%s предплечье; origin в локте" % side, "Char_Body",
             boxes=[((0, 0, -FORE_A / 2), (0.11, 0.11, FORE_A))], bevel=0.024)

        node("Hand_%s" % side, "Arm_%s_Lower" % side, (0, 0, -FORE_A),
             "%s кисть; origin в запястье" % side, "Char_Body",
             boxes=[((0, 0, -0.065), (0.13, 0.13, 0.13))], bevel=0.042)

        node("Grip_%s" % side, "Hand_%s" % side, (0, 0.045, -0.065),
             "%s точка предмета в ладони" % side, empty=True)

    # ---------------- ноги ----------------
    for side, sx in (("L", -1), ("R", 1)):
        node("Leg_%s_Upper" % side, "Hips", (sx * HIP_X, 0, 0),
             "%s бедро; origin в тазобедренном суставе" % side, "Char_Body",
             boxes=[((0, 0, -THIGH / 2), (0.14, 0.14, THIGH))], bevel=0.030)

        node("Leg_%s_Lower" % side, "Leg_%s_Upper" % side, (0, 0, -THIGH),
             "%s голень; origin в колене" % side, "Char_Body",
             boxes=[((0, 0, -SHIN / 2), (0.14, 0.14, SHIN))], bevel=0.030)

        node("Foot_%s" % side, "Leg_%s_Lower" % side, (0, 0, -SHIN),
             "%s ступня; origin в лодыжке, подошва на полу" % side, "Char_Shoes",
             boxes=[((0, 0.055, -ANKLE_Z / 2), (0.15, 0.24, ANKLE_Z))],
             bevel=0.030)

    return R


RIG = build_rig()

# ============================================================
# --- RIG SPEC END ---
# ============================================================


import bpy                      # noqa: E402
import bmesh                    # noqa: E402
from mathutils import Vector, Matrix   # noqa: E402


# ------------------------------------------------------------
# Сборка
# ------------------------------------------------------------
def make_material(name, color, roughness):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    return m


def box_mesh(name, boxes):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    for center, size in boxes:
        m = Matrix.Translation(Vector(center)) @ Matrix.Diagonal(Vector(size).to_4d())
        bmesh.ops.create_cube(bm, size=1.0, matrix=m, calc_uvs=True)
    bm.to_mesh(me)
    bm.free()
    return me


def sphere_mesh(name, center, radius, u=24, v=16):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    kw = dict(u_segments=u, v_segments=v,
              matrix=Matrix.Translation(Vector(center)), calc_uvs=True)
    try:                                   # Blender 4.x
        bmesh.ops.create_uvsphere(bm, radius=radius, **kw)
    except TypeError:                      # Blender 3.x
        bmesh.ops.create_uvsphere(bm, diameter=radius, **kw)
    bm.to_mesh(me)
    bm.free()
    return me


def build():
    if CLEAN_SCENE:
        for o in list(bpy.data.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        for c in list(bpy.data.collections):
            if c.name == "Character":
                bpy.data.collections.remove(c)

    mats = {n: make_material(n, c, r) for n, (c, r) in MATERIALS.items()}

    col = bpy.data.collections.new("Character")
    bpy.context.scene.collection.children.link(col)

    made = {}
    for n in RIG:
        if n["empty"]:
            obj = bpy.data.objects.new(n["name"], None)
            obj.empty_display_type = "PLAIN_AXES"
            obj.empty_display_size = 0.08 if n["parent"] is None else 0.03
        else:
            if n["sphere"]:
                center, radius = n["sphere"]
                me = sphere_mesh(n["name"], center, radius)
            else:
                me = box_mesh(n["name"], n["boxes"])
            if n["smooth"] and SMOOTH_HEAD:
                for p in me.polygons:
                    p.use_smooth = True
            if n["mat"]:
                me.materials.append(mats[n["mat"]])
            obj = bpy.data.objects.new(n["name"], me)
            if n["bevel"] and not n["sphere"]:
                b = obj.modifiers.new("Soft_Bevel", "BEVEL")
                b.width = n["bevel"]
                b.segments = 2
                b.limit_method = "ANGLE"
                b.angle_limit = math.radians(40)

        col.objects.link(obj)

        parent = made.get(n["parent"])
        if parent:
            obj.parent = parent
            # ВАЖНО: matrix_parent_inverse оставляем единичной —
            # loc уже задан в локальных координатах родителя.
            obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.rotation_mode = "XYZ"
        obj.location = Vector(n["loc"])

        obj["game_ready"] = True
        obj["asset"] = "Character"
        obj["role"] = n["role"]
        obj["joint_local"] = n["loc"]
        obj["code_driven_rotation"] = not n["empty"]
        made[n["name"]] = obj

    root = made["Character_ROOT"]
    for k, v in {
        "asset_name": "Stylized_Character_No_Armature",
        "height_m": HEIGHT,
        "shoulder_width_m": round(2 * (SHOULDER_X + 0.055), 3),
        "max_shoulder_width_m": 0.80,
        "front_direction": "+Y",
        "axis": "Z_up",
        "animation_system": "code_driven_joint_objects",
        "has_armature": False,
        "origin": "between feet on floor",
        "rotation_convention": "+X = swing forward, +Z = yaw, rest = identity",
    }.items():
        root[k] = v
        bpy.context.scene[k] = v

    return made


# ------------------------------------------------------------
# Проверка (печатает мировые координаты суставов и габариты)
# ------------------------------------------------------------
def report(objs):
    deps = bpy.context.evaluated_depsgraph_get()
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    print("\n%-16s %-18s %s" % ("OBJECT", "JOINT (world)", "ROLE"))
    for n in RIG:
        o = objs[n["name"]]
        p = o.matrix_world.translation
        print("%-16s (%6.3f %6.3f %6.3f)  %s"
              % (o.name, p.x, p.y, p.z, o["role"]))
        if o.type != "MESH":
            continue
        ev = o.evaluated_get(deps)
        for c in ev.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector((min(lo[i], w[i]) for i in range(3)))
            hi = Vector((max(hi[i], w[i]) for i in range(3)))
    print("\nBBOX  X %.3f..%.3f  (width %.3f)" % (lo.x, hi.x, hi.x - lo.x))
    print("BBOX  Y %.3f..%.3f  (depth %.3f)" % (lo.y, hi.y, hi.y - lo.y))
    print("BBOX  Z %.3f..%.3f  (height %.3f)" % (lo.z, hi.z, hi.z - lo.z))
    print("floor contact: %s   height 1.70: %s   width <= 0.80: %s"
          % (abs(lo.z) < 1e-4, abs(hi.z - HEIGHT) < 1e-4, (hi.x - lo.x) <= 0.80))


# ------------------------------------------------------------
# Пример анимации кодом
# ------------------------------------------------------------
def demo_pose(objs, phase=0.0, speed=1.0):
    """Шаг ходьбы. phase в радианах. Всё в rotation_euler.x."""
    s = math.sin(phase) * math.radians(35) * speed
    objs["Leg_L_Upper"].rotation_euler.x = s
    objs["Leg_R_Upper"].rotation_euler.x = -s
    # колено подгибается только у ноги, которая идёт назад (фаза переноса)
    objs["Leg_L_Lower"].rotation_euler.x = max(0.0, -s) * 0.9
    objs["Leg_R_Lower"].rotation_euler.x = max(0.0, s) * 0.9
    objs["Arm_L_Upper"].rotation_euler.x = -s * 0.7
    objs["Arm_R_Upper"].rotation_euler.x = s * 0.7
    objs["Hips"].rotation_euler.z = math.sin(phase) * math.radians(4)


def reset_pose(objs):
    for o in objs.values():
        o.rotation_euler = (0, 0, 0)


# ------------------------------------------------------------
# Экспорт
# ------------------------------------------------------------
def export_glb(objs, filepath):
    for o in bpy.data.objects:
        o.select_set(False)
    for o in objs.values():
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs["Character_ROOT"]
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_extras=True,
        export_yup=EXPORT_YUP,
    )
    print("GLB exported:", filepath)


# ------------------------------------------------------------
if __name__ == "__main__":
    OBJECTS = build()
    report(OBJECTS)
    if EXPORT_GLB_PATH:
        export_glb(OBJECTS, EXPORT_GLB_PATH)
    print("\nOK: 1.70 m, без скелета, origin'ы в суставах, rest-поворот нулевой.")
    print("Ключевой аттачпоинт предмета: Grip_R")
