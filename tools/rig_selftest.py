"""
============================================================
ПРОВЕРКА РИГА — запускать в Blender ПОСЛЕ character_v2.py
============================================================

Как пользоваться
----------------
1. Прогони character_v2.py (персонаж собран).
2. Открой этот файл в текстовом редакторе Blender, поменяй POSE
   на нужную и нажми Run Script.
3. Смотри в System Console (Window -> Toggle System Console).
   Все строки должны быть "OK". Заодно персонаж встанет в позу —
   проверь глазами, что она выглядит осмысленно.

POSE = "rest"    -> вернуть в исходную позу
       "walk"    -> шаг
       "typing"  -> работа за столом
       "carry"   -> несёт предмет, обе руки вперёд
       "swat"    -> замах правой рукой (ловля багов)
       "sit"     -> сидит

Что именно проверяется
----------------------
Тест ловит ровно ту ошибку, из-за которой предыдущая модель
разъезжалась: если origin объекта стоит не в суставе, то при
повороте расстояние до дочернего сустава меняется — «кость»
растягивается. Тест меряет все длины до и после позы.
"""

import bpy
import math
from mathutils import Matrix, Vector

POSE = "walk"
VERBOSE = True

HEIGHT = 1.70
MAX_WIDTH = 0.80

# родитель -> ребёнок : ожидаемая длина «кости», м
BONES = {
    ("Arm_L_Upper", "Arm_L_Lower"): 0.26,
    ("Arm_L_Lower", "Hand_L"): 0.24,
    ("Arm_R_Upper", "Arm_R_Lower"): 0.26,
    ("Arm_R_Lower", "Hand_R"): 0.24,
    ("Leg_L_Upper", "Leg_L_Lower"): 0.41,
    ("Leg_L_Lower", "Foot_L"): 0.41,
    ("Leg_R_Upper", "Leg_R_Lower"): 0.41,
    ("Leg_R_Lower", "Foot_R"): 0.41,
    ("Hand_R", "Grip_R"): 0.0790569,   # sqrt(0.045^2 + 0.065^2)
    ("Head", "Head_Top"): 0.28,
}

# у этих объектов origin обязан лежать НА КРАЮ меша по Z (в суставе),
# а не в его середине
END_ORIGIN = ["Arm_L_Upper", "Arm_L_Lower", "Arm_R_Upper", "Arm_R_Lower",
              "Hand_L", "Hand_R", "Leg_L_Upper", "Leg_L_Lower",
              "Leg_R_Upper", "Leg_R_Lower", "Foot_L", "Foot_R"]

REQUIRED = ["Character_ROOT", "Hips", "Torso", "Collar", "Tie", "Head",
            "Eye_L", "Eye_R", "Head_Top",
            "Arm_L_Upper", "Arm_L_Lower", "Hand_L", "Grip_L",
            "Arm_R_Upper", "Arm_R_Lower", "Hand_R", "Grip_R",
            "Leg_L_Upper", "Leg_L_Lower", "Foot_L",
            "Leg_R_Upper", "Leg_R_Lower", "Foot_R"]

D = math.radians


def POSES(name):
    """Позы: {имя объекта: (rx, ry, rz) в градусах}."""
    if name == "rest":
        return {}
    if name == "walk":
        return {"Leg_L_Upper": (32, 0, 0), "Leg_R_Upper": (-32, 0, 0),
                "Leg_R_Lower": (29, 0, 0),
                "Arm_L_Upper": (-22, 0, 0), "Arm_R_Upper": (22, 0, 0),
                "Arm_L_Lower": (-12, 0, 0), "Arm_R_Lower": (-12, 0, 0),
                "Hips": (0, 0, 4), "Head": (0, 0, -4)}
    if name == "typing":
        return {"Arm_L_Upper": (58, 0, 0), "Arm_R_Upper": (58, 0, 0),
                "Arm_L_Lower": (-38, 0, 12), "Arm_R_Lower": (-38, 0, -12),
                "Hand_L": (25, 0, 0), "Hand_R": (25, 0, 0),
                "Torso": (10, 0, 0), "Head": (-14, 0, 0)}
    if name == "carry":
        return {"Arm_L_Upper": (82, 0, 0), "Arm_R_Upper": (82, 0, 0),
                "Arm_L_Lower": (14, 0, 0), "Arm_R_Lower": (14, 0, 0),
                "Torso": (-4, 0, 0)}
    if name == "swat":
        return {"Arm_R_Upper": (-58, 0, 0), "Arm_R_Lower": (-72, 0, 0),
                "Arm_L_Upper": (18, 0, 0),
                "Torso": (0, 0, -22), "Hips": (0, 0, -10), "Head": (0, 0, 14)}
    if name == "sit":
        return {"Leg_L_Upper": (88, 0, 0), "Leg_R_Upper": (88, 0, 0),
                "Leg_L_Lower": (-88, 0, 0), "Leg_R_Lower": (-88, 0, 0),
                "Arm_L_Upper": (50, 0, 0), "Arm_R_Upper": (50, 0, 0),
                "Arm_L_Lower": (-40, 0, 0), "Arm_R_Lower": (-40, 0, 0)}
    raise ValueError("неизвестная поза: %s" % name)


# ------------------------------------------------------------
RESULTS = []


def check(label, cond, detail=""):
    RESULTS.append((bool(cond), label, detail))


def obj(name):
    return bpy.data.objects.get(name)


def joints_now():
    bpy.context.view_layer.update()
    return {n: obj(n).matrix_world.translation.copy()
            for n in REQUIRED if obj(n)}


def set_pose(pose):
    for n in REQUIRED:
        o = obj(n)
        if o:
            o.rotation_mode = "XYZ"
            o.rotation_euler = (0, 0, 0)
    for n, (rx, ry, rz) in pose.items():
        o = obj(n)
        if o:
            o.rotation_euler = (D(rx), D(ry), D(rz))
    bpy.context.view_layer.update()


def world_bbox():
    deps = bpy.context.evaluated_depsgraph_get()
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    for n in REQUIRED:
        o = obj(n)
        if not o or o.type != "MESH":
            continue
        ev = o.evaluated_get(deps)
        for c in ev.bound_box:
            w = o.matrix_world @ Vector(c)
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return lo, hi


def run():
    # --- 1. все объекты на месте
    missing = [n for n in REQUIRED if obj(n) is None]
    check("все 23 объекта существуют", not missing,
          "нет: %s" % ", ".join(missing) if missing else "23/23")
    if missing:
        return

    set_pose({})

    # --- 2. matrix_parent_inverse единичная
    bad = [n for n in REQUIRED
           if obj(n).parent and obj(n).matrix_parent_inverse != Matrix.Identity(4)]
    check("matrix_parent_inverse единичная у всех", not bad,
          "испорчены: %s" % ", ".join(bad) if bad else
          "локальные координаты честные, экспорт не поедет")

    # --- 3. rest-поворот нулевой
    bad = [n for n in REQUIRED
           if max(abs(a) for a in obj(n).rotation_euler) > 1e-6]
    check("rest-поворот нулевой у всех", not bad,
          "ненулевые: %s" % ", ".join(bad) if bad else
          "rotation.x = мах вперёд, без сюрпризов")

    # --- 4. origin в суставе, а не в центре меша
    bad = []
    for n in END_ORIGIN:
        o = obj(n)
        zs = [v.co.z for v in o.data.vertices]
        if min(abs(min(zs)), abs(max(zs))) > 1e-4:
            bad.append("%s (меш по Z: %.3f..%.3f)" % (n, min(zs), max(zs)))
    check("origin конечностей стоит в суставе", not bad,
          "; ".join(bad) if bad else "%d/%d" % (len(END_ORIGIN), len(END_ORIGIN)))

    # --- 5. габариты в rest
    lo, hi = world_bbox()
    check("макушка ровно %.2f м" % HEIGHT, abs(hi.z - HEIGHT) < 5e-4,
          "max Z = %.4f" % hi.z)
    check("подошвы на полу", abs(lo.z) < 5e-4, "min Z = %.4f" % lo.z)
    check("ширина <= %.2f м" % MAX_WIDTH, (hi.x - lo.x) <= MAX_WIDTH,
          "ширина = %.3f" % (hi.x - lo.x))
    check("модель по центру X", abs(hi.x + lo.x) < 1e-3,
          "центр = %.4f" % ((hi.x + lo.x) / 2))

    # --- 6. ГЛАВНОЕ: кости не растягиваются при повороте
    rest = joints_now()
    rest_len = {k: (rest[k[1]] - rest[k[0]]).length for k in BONES}
    bad = []
    for k, expect in BONES.items():
        if abs(rest_len[k] - expect) > 1e-3:
            bad.append("%s->%s = %.4f, ждали %.4f" % (k[0], k[1], rest_len[k], expect))
    check("длины костей в rest", not bad,
          "; ".join(bad) if bad else "%d/%d" % (len(BONES), len(BONES)))

    set_pose(POSES(POSE))
    posed = joints_now()
    bad = []
    for k in BONES:
        L = (posed[k[1]] - posed[k[0]]).length
        if abs(L - rest_len[k]) > 1e-4:
            bad.append("%s->%s: %.4f -> %.4f (растянулась на %.4f)"
                       % (k[0], k[1], rest_len[k], L, L - rest_len[k]))
    check("кости не растянулись в позе '%s'" % POSE, not bad,
          "; ".join(bad) if bad else
          "%d/%d — значит origin'ы реально в суставах" % (len(BONES), len(BONES)))

    # --- 7. неподвижные суставы остались на месте
    frozen = [n for n in ("Character_ROOT", "Hips") if n in posed]
    bad = [n for n in frozen if (posed[n] - rest[n]).length > 1e-9]
    check("корень и таз не сдвинулись", not bad, ", ".join(bad) or "ok")

    # --- 8. поза не проваливает персонажа под пол слишком глубоко
    lo2, hi2 = world_bbox()
    check("в позе '%s' ничего не ушло под пол глубже 2 см" % POSE, lo2.z > -0.02,
          "min Z = %.4f" % lo2.z)

    # --- отчёт
    print("\n" + "=" * 64)
    print("ПРОВЕРКА РИГА   поза: %s" % POSE)
    print("=" * 64)
    for ok, label, detail in RESULTS:
        print(" %s  %-44s %s" % ("OK  " if ok else "FAIL", label, detail))
    n_bad = sum(1 for ok, _, _ in RESULTS if not ok)
    print("-" * 64)
    print("ИТОГ: %d из %d. %s" % (len(RESULTS) - n_bad, len(RESULTS),
                                  "Риг здоров." if n_bad == 0 else "ЕСТЬ ПРОБЛЕМЫ."))

    if VERBOSE:
        print("\nМировые координаты суставов в позе '%s':" % POSE)
        for n in REQUIRED:
            p = posed[n]
            print("  %-16s (%7.3f %7.3f %7.3f)" % (n, p.x, p.y, p.z))
    print("\nПерсонаж оставлен в позе '%s' — посмотри во вьюпорте." % POSE)
    print("Чтобы вернуть: поставь POSE = \"rest\" и запусти снова.\n")


run()
