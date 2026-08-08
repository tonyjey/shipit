import bpy
import math
from mathutils import Vector

# ============================================================
# Retro 90s Desktop Computer - Game-ready Blender generator
# Blender 4.x
#
# Creates:
#   - horizontal desktop PC
#   - CRT monitor
#   - stylized keyboard
#   - OFF / ACTIVE / ERROR / CRASHED state materials
#   - screen Area Light
#   - weak power-button light
#
# Scale:
#   1 Blender unit = 1 meter
# ============================================================

# -----------------------------
# Configuration
# -----------------------------
PC_W, PC_D, PC_H = 0.45, 0.38, 0.15
MON_W, MON_D, MON_H = 0.46, 0.40, 0.40
KEY_W, KEY_D = 0.45, 0.17

BEIGE = (0.62, 0.58, 0.50, 1.0)
DARK_BEIGE = (0.32, 0.30, 0.27, 1.0)
BLACK = (0.025, 0.025, 0.022, 1.0)
GREY = (0.22, 0.22, 0.20, 1.0)
BLUE = (0.025, 0.22, 1.0, 1.0)
RED = (1.0, 0.025, 0.015, 1.0)
GREEN = (0.02, 1.0, 0.08, 1.0)

# State names:
# OFF = 0
# ACTIVE = 1
# ERROR = 2
# CRASHED = 3

# -----------------------------
# Scene cleanup
# -----------------------------
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

for datablocks in (
    bpy.data.materials,
    bpy.data.curves,
    bpy.data.meshes,
    bpy.data.cameras,
    bpy.data.lights,
):
    # Leave Blender's default world/etc. alone.
    pass


# -----------------------------
# Helpers
# -----------------------------
def mat_principled(name, color, roughness=0.65, metallic=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return m


def mat_emission(name, color, strength=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emission = nt.nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = color
    emission.inputs["Strength"].default_value = strength
    nt.links.new(emission.outputs["Emission"], out.inputs["Surface"])
    return m


def rounded_cube(name, location, scale, material, bevel=0.01):
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    if material:
        obj.data.materials.append(material)

    if bevel > 0:
        mod = obj.modifiers.new("Soft bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = 'ANGLE'

    return obj


def cylinder(name, location, radius, depth, material, vertices=16, rotation=None):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation or (0, 0, 0),
    )
    obj = bpy.context.object
    obj.name = name
    if material:
        obj.data.materials.append(material)
    return obj


def add_collection(name):
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    return col


def move_to_collection(obj, collection):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    collection.objects.link(obj)


# -----------------------------
# Materials
# -----------------------------
plastic = mat_principled("Plastic_Beige", BEIGE, 0.72)
plastic_dark = mat_principled("Plastic_Dark", DARK_BEIGE, 0.75)
key_material = mat_principled("Keyboard_Keys", (0.54, 0.51, 0.45, 1), 0.70)
black_material = mat_principled("Screen_Frame", BLACK, 0.45)
glass_material = mat_principled("CRT_Glass", (0.035, 0.04, 0.045, 1), 0.18)

power_off = mat_principled("Power_OFF_Grey", GREY, 0.45)
power_green = mat_emission("Power_ACTIVE_Green", GREEN, 1.8)
power_red = mat_emission("Power_CRASHED_Red", RED, 2.5)

screen_off = mat_principled("Screen_OFF_Grey", (0.035, 0.038, 0.035, 1), 0.40)
screen_blue = mat_emission("Screen_ACTIVE_Blue", BLUE, 2.8)
screen_red = mat_emission("Screen_ERROR_Red", RED, 3.0)

# -----------------------------
# Collections
# -----------------------------
root_col = add_collection("RetroComputer")
pc_col = add_collection("PC")
monitor_col = add_collection("Monitor")
keyboard_col = add_collection("Keyboard")
lights_col = add_collection("Lights")

# -----------------------------
# Root object
# -----------------------------
root = bpy.data.objects.new("RetroComputer_ROOT", None)
root.empty_display_type = 'PLAIN_AXES'
root.empty_display_size = 0.1
root_col.objects.link(root)

root["state"] = 0
root["state_names"] = "OFF,ACTIVE,ERROR,CRASHED"

# -----------------------------
# SYSTEM UNIT
# -----------------------------
pc = rounded_cube(
    "PC_Case",
    (0, 0, PC_H / 2),
    (PC_W, PC_D, PC_H),
    plastic,
    bevel=0.018,
)
move_to_collection(pc, pc_col)
pc.parent = root

# Front face is +Y.
front_y = PC_D / 2 + 0.002

# Simple CD-like drive slot.
drive = rounded_cube(
    "CD_Drive",
    (-0.06, front_y, 0.087),
    (0.18, 0.012, 0.035),
    plastic_dark,
    bevel=0.005,
)
move_to_collection(drive, pc_col)
drive.parent = root

drive_slot = rounded_cube(
    "CD_Drive_Slot",
    (-0.06, front_y - 0.007, 0.087),
    (0.13, 0.004, 0.006),
    BLACK if False else black_material,
    bevel=0.002,
)
move_to_collection(drive_slot, pc_col)
drive_slot.parent = root

# Power button.
power_button = cylinder(
    "PowerButton",
    (0.135, front_y + 0.002, 0.075),
    0.022,
    0.012,
    power_off,
    vertices=20,
    rotation=(math.radians(90), 0, 0),
)
move_to_collection(power_button, pc_col)
power_button.parent = root

power_button["state"] = 0
power_button["states"] = "OFF=Grey, ACTIVE=Green, ERROR=Green, CRASHED=Red"

# Tiny decorative seam.
seam = rounded_cube(
    "PC_Front_Seam",
    (0, front_y + 0.001, 0.035),
    (PC_W * 0.92, 0.006, 0.004),
    plastic_dark,
    bevel=0.001,
)
move_to_collection(seam, pc_col)
seam.parent = root

# -----------------------------
# MONITOR
# -----------------------------
# Monitor sits on top of the desktop case.
monitor_bottom = PC_H
monitor_z = monitor_bottom + MON_H / 2 + 0.015

monitor = rounded_cube(
    "Monitor_Body",
    (0, 0, monitor_z),
    (MON_W, MON_D, MON_H),
    plastic,
    bevel=0.025,
)
move_to_collection(monitor, monitor_col)
monitor.parent = root

# Dark inner bezel.
bezel_w = MON_W * 0.83
bezel_h = MON_H * 0.68

bezel = rounded_cube(
    "CRT_Bezel",
    (0, MON_D / 2 + 0.003, monitor_z + 0.015),
    (bezel_w, 0.018, bezel_h),
    black_material,
    bevel=0.016,
)
move_to_collection(bezel, monitor_col)
bezel.parent = root

# CRT glass surface. Slightly rounded and curved-looking.
glass = rounded_cube(
    "CRT_Glass",
    (0, MON_D / 2 + 0.015, monitor_z + 0.015),
    (bezel_w * 0.92, 0.012, bezel_h * 0.91),
    glass_material,
    bevel=0.025,
)
move_to_collection(glass, monitor_col)
glass.parent = root

# Actual screen surface used for the game's viewport/UI.
screen = rounded_cube(
    "Screen_Surface",
    (0, MON_D / 2 + 0.022, monitor_z + 0.015),
    (bezel_w * 0.86, 0.004, bezel_h * 0.84),
    screen_off,
    bevel=0.018,
)
move_to_collection(screen, monitor_col)
screen.parent = root

screen["state"] = 0
screen["states"] = "OFF=Grey, ACTIVE=Blue, ERROR=Red, CRASHED=Grey"
screen["godot_surface"] = True

# Bottom monitor branding / decorative plate.
label = rounded_cube(
    "Monitor_Label_Plate",
    (0.0, MON_D / 2 + 0.004, monitor_z - MON_H * 0.38),
    (0.10, 0.006, 0.018),
    plastic_dark,
    bevel=0.004,
)
move_to_collection(label, monitor_col)
label.parent = root

# Monitor stand.
stand_neck = rounded_cube(
    "Monitor_Stand_Neck",
    (0, -0.01, PC_H + 0.005),
    (0.09, 0.10, 0.08),
    plastic_dark,
    bevel=0.012,
)
move_to_collection(stand_neck, monitor_col)
stand_neck.parent = root

stand_base = rounded_cube(
    "Monitor_Stand_Base",
    (0, -0.015, PC_H + 0.002),
    (0.25, 0.18, 0.035),
    plastic,
    bevel=0.018,
)
move_to_collection(stand_base, monitor_col)
stand_base.parent = root

# -----------------------------
# KEYBOARD
# -----------------------------
keyboard_y = -0.30
keyboard_z = 0.025

kb_body = rounded_cube(
    "Keyboard_Body",
    (0, keyboard_y, keyboard_z),
    (KEY_W, KEY_D, 0.045),
    plastic,
    bevel=0.015,
)
move_to_collection(kb_body, keyboard_col)
kb_body.parent = root

# Keys are generated into one mesh object later.
key_objects = []

# Approximate 90s layout. Each row is represented by compact keycaps.
rows = [
    # (number of keys, key width, row y offset)
    (13, 0.026, 0.055),
    (13, 0.026, 0.027),
    (12, 0.027, 0.000),
    (11, 0.028, -0.029),
    (10, 0.030, -0.058),
]

for row_index, (count, kw, yoff) in enumerate(rows):
    total = count * kw + (count - 1) * 0.004
    start_x = -total / 2 + kw / 2

    for i in range(count):
        x = start_x + i * (kw + 0.004)
        key = rounded_cube(
            f"Key_{row_index:02d}_{i:02d}",
            (x, keyboard_y + yoff, 0.056),
            (kw, 0.020, 0.014),
            key_material,
            bevel=0.003,
        )
        key.parent = root
        key_objects.append(key)

# Space bar.
space = rounded_cube(
    "Key_Space",
    (0, keyboard_y - 0.087, 0.056),
    (0.16, 0.024, 0.014),
    key_material,
    bevel=0.003,
)
space.parent = root
key_objects.append(space)

# Modifier / enter-like larger keys.
for name, x, y, w in [
    ("Key_Shift_L", -0.18, keyboard_y - 0.058, 0.055),
    ("Key_Shift_R",  0.18, keyboard_y - 0.058, 0.055),
    ("Key_Enter",     0.18, keyboard_y - 0.029, 0.045),
]:
    key = rounded_cube(
        name, (x, y, 0.056), (w, 0.020, 0.014),
        key_material, bevel=0.003
    )
    key.parent = root
    key_objects.append(key)

# Join all keycaps into a single mesh for easier export/management.
bpy.ops.object.select_all(action='DESELECT')
for obj in key_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = key_objects[0]
bpy.ops.object.join()
keys = bpy.context.object
keys.name = "Keyboard_Keys_Optimized"
move_to_collection(keys, keyboard_col)

# -----------------------------
# LIGHTS
# -----------------------------
# Screen light: hidden by default, controlled later in Godot.
bpy.ops.object.light_add(
    type='AREA',
    location=(0, MON_D / 2 + 0.10, monitor_z + 0.01),
)
screen_light = bpy.context.object
screen_light.name = "ScreenLight"
screen_light.data.name = "ScreenLight_Data"
screen_light.data.energy = 0.0
screen_light.data.shape = 'RECTANGLE'
screen_light.data.size = 0.30
screen_light.data.size_y = 0.22
screen_light.data.color = BLUE
screen_light.rotation_euler = (math.radians(-90), 0, 0)
move_to_collection(screen_light, lights_col)
screen_light.parent = root

screen_light["godot_state_light"] = True
screen_light["active_color"] = "BLUE"
screen_light["error_color"] = "RED"

# Weak power button light.
bpy.ops.object.light_add(
    type='POINT',
    location=(0.135, front_y + 0.035, 0.075),
)
power_light = bpy.context.object
power_light.name = "PowerLight"
power_light.data.name = "PowerLight_Data"
power_light.data.energy = 0.0
power_light.data.shadow_soft_size = 0.05
power_light.data.color = GREEN
move_to_collection(power_light, lights_col)
power_light.parent = root

power_light["godot_state_light"] = True
power_light["active_color"] = "GREEN"
power_light["crashed_color"] = "RED"

# -----------------------------
# State preview helper
# -----------------------------
def set_state(state):
    """
    Blender preview helper.

    0 = OFF
    1 = ACTIVE
    2 = ERROR
    3 = CRASHED
    """
    state = int(state)
    root["state"] = state

    if state == 0:
        power_button.data.materials[0] = power_off
        screen.data.materials[0] = screen_off
        screen_light.data.energy = 0.0
        power_light.data.energy = 0.0

    elif state == 1:
        power_button.data.materials[0] = power_green
        screen.data.materials[0] = screen_blue
        screen_light.data.energy = 15.0
        screen_light.data.color = BLUE
        power_light.data.energy = 0.35
        power_light.data.color = GREEN

    elif state == 2:
        power_button.data.materials[0] = power_green
        screen.data.materials[0] = screen_red
        screen_light.data.energy = 15.0
        screen_light.data.color = RED
        power_light.data.energy = 0.35
        power_light.data.color = GREEN

    elif state == 3:
        power_button.data.materials[0] = power_red
        screen.data.materials[0] = screen_off
        screen_light.data.energy = 0.0
        power_light.data.energy = 1.2
        power_light.data.color = RED


# -----------------------------
# Custom properties / export hints
# -----------------------------
for obj in (pc, monitor, kb_body, screen, power_button, keys):
    obj["game_ready"] = True
    obj["asset"] = "RetroComputer"

# Screen is intentionally named for easy Godot material/surface replacement.
screen["purpose"] = "Replace or override material in Godot to display UI/game content."

# Set initial preview state.
set_state(0)

# -----------------------------
# Scene organization
# -----------------------------
# Put root at origin; keyboard is in front of PC.
bpy.context.scene["asset_name"] = "Retro_90s_Desktop_Computer"
bpy.context.scene["recommended_engine"] = "Godot"
bpy.context.scene["states"] = "OFF,ACTIVE,ERROR,CRASHED"

# Select root for convenience.
bpy.ops.object.select_all(action='DESELECT')
root.select_set(True)
bpy.context.view_layer.objects.active = root

print("Retro computer created successfully.")
print("State preview function:")
print("  set_state(0) = OFF")
print("  set_state(1) = ACTIVE")
print("  set_state(2) = ERROR")
print("  set_state(3) = CRASHED")
