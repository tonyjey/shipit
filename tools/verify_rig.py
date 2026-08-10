"""Проверка риги без Blender.

1. Вытаскивает секцию RIG SPEC из character_v2.py и исполняет её
   (никакого bpy) — значит проверяются ровно те же числа, что уйдут
   в Blender, без риска рассинхрона.
2. Считает мировые матрицы по тем же правилам, что Blender/glTF:
   world = parent_world @ T(loc) @ R(euler XYZ).
3. Ассертит рост, ширину, контакт с полом, целостность цепочек.
4. Растеризует превью (T-поза и шаг) в PNG.
"""

import math
import re
import sys
import numpy as np

SRC = sys.argv[1] if len(sys.argv) > 1 else "character_v2.py"
OUT = sys.argv[2] if len(sys.argv) > 2 else "character_preview.png"

# ---------- 1. извлечь спецификацию ----------
text = open(SRC, encoding="utf-8").read()
block = re.search(r"# --- RIG SPEC START ---[^\n]*\n(.*?)# --- RIG SPEC END ---",
                  text, re.S).group(1)
ns = {"math": math, "HEIGHT": 1.70}
exec(compile(block, "RIG_SPEC", "exec"), ns)
RIG = ns["RIG"]
BY = {n["name"]: n for n in RIG}

MATCOL = {
    "Char_Body":   (0.43, 0.48, 0.52),
    "Char_Head":   (0.48, 0.53, 0.57),
    "Char_Collar": (0.90, 0.89, 0.84),
    "Char_Tie":    (0.65, 0.08, 0.06),
    "Char_Eyes":   (0.05, 0.05, 0.05),
    "Char_Shoes":  (0.10, 0.10, 0.10),
}


# ---------- 2. трансформы ----------
def euler_xyz(rx, ry, rz):
    cx, sx = math.cos(rx), math.sin(rx)
    cy, sy = math.cos(ry), math.sin(ry)
    cz, sz = math.cos(rz), math.sin(rz)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Rz @ Ry @ Rx           # порядок 'XYZ' как в Blender


def mat(loc, rot=(0, 0, 0)):
    m = np.eye(4)
    m[:3, :3] = euler_xyz(*rot)
    m[:3, 3] = loc
    return m


def world_matrices(pose=None):
    pose = pose or {}
    W = {}
    for n in RIG:
        local = mat(n["loc"], pose.get(n["name"], (0, 0, 0)))
        p = n["parent"]
        W[n["name"]] = local if p is None else W[p] @ local
    return W


# ---------- 3. геометрия ----------
def box_faces(center, size):
    cx, cy, cz = center
    hx, hy, hz = [s / 2 for s in size]
    v = [(cx + sx * hx, cy + sy * hy, cz + sz * hz)
         for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    idx = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
           (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return [[v[i] for i in f] for f in idx]


def sphere_faces(center, r, u=20, v=12):
    cx, cy, cz = center
    P = lambda i, j: (cx + r * math.sin(math.pi * j / v) * math.cos(2 * math.pi * i / u),
                      cy + r * math.sin(math.pi * j / v) * math.sin(2 * math.pi * i / u),
                      cz + r * math.cos(math.pi * j / v))
    return [[P(i, j), P(i + 1, j), P(i + 1, j + 1), P(i, j + 1)]
            for i in range(u) for j in range(v)]


def collect(pose=None):
    """-> список (face_world_np, rgb). Плюс мировые точки суставов."""
    W = world_matrices(pose)
    faces = []
    for n in RIG:
        if n["empty"]:
            continue
        col = MATCOL[n["mat"]]
        local = []
        if n["sphere"]:
            local += sphere_faces(n["sphere"][0], n["sphere"][1])
        for c, s in n["boxes"]:
            local += box_faces(c, s)
        M = W[n["name"]]
        for f in local:
            pts = np.array([M @ np.array([*p, 1.0]) for p in f])[:, :3]
            faces.append((pts, col))
    return faces, W


# ---------- 4. проверки ----------
def check():
    faces, W = collect()
    allpts = np.vstack([f for f, _ in faces])
    lo, hi = allpts.min(0), allpts.max(0)
    res = []

    def ok(label, cond, detail):
        res.append((cond, label, detail))

    ok("макушка ровно 1.70", abs(hi[2] - 1.70) < 1e-6, "max Z = %.4f" % hi[2])
    ok("подошвы на полу", abs(lo[2]) < 1e-6, "min Z = %.4f" % lo[2])
    ok("ширина <= 0.80", (hi[0] - lo[0]) <= 0.80,
       "width = %.3f (X %.3f..%.3f)" % (hi[0] - lo[0], lo[0], hi[0]))
    ok("модель по центру X", abs(hi[0] + lo[0]) < 1e-9, "центр X = %.4f" % ((hi[0] + lo[0]) / 2))

    # суставы на своих местах
    exp = {
        "Character_ROOT": (0, 0, 0.00),
        "Hips": (0, 0, 0.92), "Torso": (0, 0, 0.92),
        "Head": (0, 0, 1.42), "Head_Top": (0, 0, 1.70),
        "Arm_L_Upper": (-0.23, 0, 1.34), "Arm_L_Lower": (-0.23, 0, 1.08),
        "Hand_L": (-0.23, 0, 0.84),
        "Arm_R_Upper": (0.23, 0, 1.34), "Hand_R": (0.23, 0, 0.84),
        "Leg_L_Upper": (-0.12, 0, 0.92), "Leg_L_Lower": (-0.12, 0, 0.51),
        "Foot_L": (-0.12, 0, 0.10),
        "Leg_R_Upper": (0.12, 0, 0.92), "Foot_R": (0.12, 0, 0.10),
    }
    bad = []
    for name, e in exp.items():
        got = W[name][:3, 3]
        if np.abs(got - np.array(e)) .max() > 1e-9:
            bad.append("%s -> %s, ждали %s" % (name, np.round(got, 4), e))
    ok("origin'ы всех суставов в мировых точках", not bad, "; ".join(bad) or "15/15")

    # глаза реально торчат из головы
    hc = W["Head"][:3, 3] + np.array([0, 0, ns["HEAD_C_Z"] - ns["NECK_Z"]])
    d = np.linalg.norm(W["Eye_L"][:3, 3] - hc)
    ok("глаза на поверхности головы", ns["HEAD_R"] - 0.03 < d < ns["HEAD_R"],
       "расстояние до центра %.4f, радиус %.2f" % (d, ns["HEAD_R"]))

    # воротник должен выступать за силуэт головы, иначе его не видно
    cz = W["Collar"][2, 3]
    dz = abs(cz - hc[2])
    head_half = math.sqrt(max(0.0, ns["HEAD_R"] ** 2 - dz ** 2))
    collar_half = BY["Collar"]["boxes"][0][1][0] / 2
    ok("воротник виден из-за головы", collar_half > head_half + 0.02,
       "полуширина воротника %.3f против силуэта головы %.3f" % (collar_half, head_half))

    # узел галстука должен торчать перед головой и перед грудью
    ty = W["Tie"][1, 3] + BY["Tie"]["boxes"][0][1][1] / 2
    tz = W["Tie"][2, 3]
    head_y = math.sqrt(max(0.0, ns["HEAD_R"] ** 2 - (tz - hc[2]) ** 2))
    ok("узел галстука торчит наружу", ty > head_y + 0.02 and ty > 0.14 + 0.01,
       "перед узла y=%.3f, голова y=%.3f, грудь y=0.140" % (ty, head_y))

    # поворот в суставе не разрывает цепь
    pose = {"Arm_R_Upper": (math.radians(90), 0, 0),
            "Leg_L_Upper": (math.radians(-30), 0, 0),
            "Leg_L_Lower": (math.radians(40), 0, 0),
            "Head": (0, 0, math.radians(45))}
    Wp = world_matrices(pose)
    ok("плечо не смещается при повороте",
       np.abs(Wp["Arm_R_Upper"][:3, 3] - W["Arm_R_Upper"][:3, 3]).max() < 1e-12,
       "плечо %s" % np.round(Wp["Arm_R_Upper"][:3, 3], 4))
    ok("локоть уходит вперёд на длину плеча (+X = вперёд)",
       abs(Wp["Arm_R_Lower"][1, 3] - 0.26) < 1e-9 and abs(Wp["Arm_R_Lower"][2, 3] - 1.34) < 1e-9,
       "локоть %s" % np.round(Wp["Arm_R_Lower"][:3, 3], 4))
    ok("колено не смещается при повороте бедра",
       abs(np.linalg.norm(Wp["Leg_L_Lower"][:3, 3] - Wp["Leg_L_Upper"][:3, 3]) - 0.41) < 1e-9,
       "|бедро| = %.4f" % np.linalg.norm(Wp["Leg_L_Lower"][:3, 3] - Wp["Leg_L_Upper"][:3, 3]))
    ok("шея не смещается при повороте головы",
       np.abs(Wp["Head"][:3, 3] - W["Head"][:3, 3]).max() < 1e-12, "ok")
    ok("Head_Top едет вместе с головой",
       np.abs(Wp["Head_Top"][:3, 3] - W["Head_Top"][:3, 3]).max() < 1e-9,
       "точка на оси вращения — шапка не слетит")

    print("\n=== ПРОВЕРКИ ===")
    for cond, label, detail in res:
        print(" %s  %-42s %s" % ("OK  " if cond else "FAIL", label, detail))
    print("\nГабариты: X %.3f..%.3f  Y %.3f..%.3f  Z %.3f..%.3f"
          % (lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))
    print("\n=== СУСТАВЫ (мировые) ===")
    for n in RIG:
        p = W[n["name"]][:3, 3]
        print(" %-16s (%7.3f %7.3f %7.3f)  %s" % (n["name"], *p, n["role"]))
    return all(c for c, _, _ in res)


# ---------- 5. рендер ----------
def render(ax, pose, view, title):
    import matplotlib.collections as mc
    faces, _ = collect(pose)
    if view == "front":      # камера с +Y
        proj, depth, flip = (0, 2), 1, 1
    else:                    # камера с +X
        proj, depth, flip = (1, 2), 0, -1
    light = np.array([0.35, 0.75, 0.55]); light /= np.linalg.norm(light)
    polys, cols, order = [], [], []
    for pts, col in faces:
        n = np.cross(pts[1] - pts[0], pts[2] - pts[0])
        ln = np.linalg.norm(n)
        if ln < 1e-12:
            continue
        n /= ln
        if n[depth] * flip < 0:              # backface cull
            continue
        sh = 0.40 + 0.60 * max(0.0, float(n @ light))
        xy = pts[:, list(proj)].copy()
        if view != "front":
            xy[:, 0] *= -1
        polys.append(xy)
        cols.append(tuple(min(1.0, c * sh) for c in col))
        order.append(pts[:, depth].mean() * flip)
    idx = np.argsort(order)
    ax.add_collection(mc.PolyCollection([polys[i] for i in idx],
                                        facecolors=[cols[i] for i in idx],
                                        edgecolors="none"))
    ax.plot([-1, 1], [0, 0], color="#888", lw=1, zorder=-5)
    for z in (0.5, 1.0, 1.5, 1.7):
        ax.plot([-0.75, 0.75], [z, z], color="#bbb", lw=0.6, ls=":", zorder=-5)
        ax.text(0.62, z + 0.012, "%.2f" % z, fontsize=6, color="#777")
    ax.set_xlim(-0.75, 0.75); ax.set_ylim(-0.06, 1.84)
    ax.set_aspect("equal"); ax.axis("off")
    ax.set_title(title, fontsize=9)


if __name__ == "__main__":
    good = check()
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    walk = {}
    s = math.radians(32)
    walk["Leg_L_Upper"] = (s, 0, 0)
    walk["Leg_R_Upper"] = (-s, 0, 0)
    walk["Leg_R_Lower"] = (s * 0.9, 0, 0)
    walk["Arm_L_Upper"] = (-s * 0.7, 0, 0)
    walk["Arm_R_Upper"] = (s * 0.7, 0, 0)
    walk["Head"] = (0, 0, math.radians(15))

    carry = {}
    carry["Arm_L_Upper"] = (math.radians(80), 0, 0)
    carry["Arm_R_Upper"] = (math.radians(80), 0, 0)
    carry["Arm_L_Lower"] = (math.radians(15), 0, 0)
    carry["Arm_R_Lower"] = (math.radians(15), 0, 0)

    scenes = [({}, "front", "Rest — спереди (+Y)"),
              ({}, "side", "Rest — сбоку"),
              (walk, "front", "Шаг — спереди"),
              (walk, "side", "Шаг — сбоку"),
              (carry, "side", "Несёт предмет — сбоку")]
    fig, axes = plt.subplots(1, len(scenes), figsize=(3.0 * len(scenes), 6.2))
    for ax, (p, v, t) in zip(axes, scenes):
        render(ax, p, v, t)
    fig.suptitle("Character v2 — проверка позы и габаритов (рост 1.70 м)", fontsize=11)
    fig.tight_layout()
    fig.savefig(OUT, dpi=150, facecolor="white")
    print("\nPreview:", OUT)
    sys.exit(0 if good else 1)
