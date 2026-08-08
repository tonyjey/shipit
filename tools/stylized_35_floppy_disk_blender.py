import bpy

# ============================================================
# Stylized 3.5" Floppy Disk - Game-ready Blender generator
# Blender 4.x
#
# Creates a stylized 3.5-inch floppy disk with:
# - customizable main body color
# - recessed label
# - metal shutter
# - center hub
# - write-protect slider
# - simple optimized geometry
#
# Scale: 1 Blender unit = 1 meter
# ============================================================

FLOPPY_W = 0.090
FLOPPY_H = 0.094
FLOPPY_D = 0.0032

# Default body color: dark blue
FLOPPY_COLOR = (0.055, 0.075, 0.10, 1.0)

LABEL_COLOR = (0.70, 0.67, 0.57, 1.0)
DARK_COLOR = (0.018, 0.020, 0.022, 1.0)
METAL_COLOR = (0.42, 0.44, 0.43, 1.0)
WHITE = (0.92, 0.90, 0.84, 1.0)


# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
def make_principled(name, color, roughness=0.65, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True

    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic

    return mat


def rounded_cube(name, location, dimensions, material, bevel=0.001):
    bpy.ops.mesh.primitive_cube_add(location=location)

    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions

    bpy.ops.object.transform_apply(
        location=False,
        rotation=False,
        scale=True
    )

    if material:
        obj.data.materials.append(material)

    if bevel > 0:
        mod = obj.modifiers.new("Soft_Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"

    return obj


def cylinder(name, location, radius, depth, material, vertices=16):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location
    )

    obj = bpy.context.object
    obj.name = name

    if material:
        obj.data.materials.append(material)

    return obj


def create_collection(name):
    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    return collection


def move_to_collection(obj, collection):
    for old_collection in list(obj.users_collection):
        old_collection.objects.unlink(obj)
    collection.objects.link(obj)


# ------------------------------------------------------------
# Materials
# ------------------------------------------------------------
floppy_material = make_principled(
    "Floppy_Body_Color",
    FLOPPY_COLOR,
    roughness=0.70
)

label_material = make_principled(
    "Floppy_Label",
    LABEL_COLOR,
    roughness=0.78
)

dark_material = make_principled(
    "Floppy_Dark_Plastic",
    DARK_COLOR,
    roughness=0.65
)

metal_material = make_principled(
    "Floppy_Shutter_Metal",
    METAL_COLOR,
    roughness=0.32,
    metallic=0.75
)

white_material = make_principled(
    "Floppy_Label_Writing",
    WHITE,
    roughness=0.80
)


# ------------------------------------------------------------
# Collection and root
# ------------------------------------------------------------
floppy_collection = create_collection("FloppyDisk")

root = bpy.data.objects.new("FloppyDisk_ROOT", None)
root.empty_display_type = "PLAIN_AXES"
root.empty_display_size = 0.025
floppy_collection.objects.link(root)

root["asset_name"] = "Stylized_3.5_Floppy_Disk"
root["game_ready"] = True
root["customizable_color"] = True
root["scale"] = "1 Blender unit = 1 meter"


# ------------------------------------------------------------
# Main body
# ------------------------------------------------------------
body = rounded_cube(
    "Floppy_Body",
    (0, 0, 0),
    (FLOPPY_W, FLOPPY_H, FLOPPY_D),
    floppy_material,
    bevel=0.0022
)
move_to_collection(body, floppy_collection)
body.parent = root
body["color_control"] = "Floppy_Body_Color"


# ------------------------------------------------------------
# Front label
# ------------------------------------------------------------
front_z = FLOPPY_D / 2

label = rounded_cube(
    "Floppy_Label_Area",
    (0, 0.004, front_z + 0.00055),
    (0.064, 0.040, 0.0010),
    label_material,
    bevel=0.0012
)
move_to_collection(label, floppy_collection)
label.parent = root

label_strip = rounded_cube(
    "Floppy_Label_Strip",
    (0, -0.015, front_z + 0.0010),
    (0.052, 0.008, 0.0008),
    dark_material,
    bevel=0.0007
)
move_to_collection(label_strip, floppy_collection)
label_strip.parent = root


# ------------------------------------------------------------
# Metal shutter and slot
# ------------------------------------------------------------
shutter = rounded_cube(
    "Floppy_Metal_Shutter",
    (0, -0.033, front_z + 0.0011),
    (0.048, 0.017, 0.0012),
    metal_material,
    bevel=0.0013
)
move_to_collection(shutter, floppy_collection)
shutter.parent = root

shutter_slot = rounded_cube(
    "Floppy_Shutter_Slot",
    (0, -0.033, front_z + 0.0009),
    (0.031, 0.009, 0.0010),
    dark_material,
    bevel=0.0007
)
move_to_collection(shutter_slot, floppy_collection)
shutter_slot.parent = root


# ------------------------------------------------------------
# Center hub
# ------------------------------------------------------------
hub_outer = cylinder(
    "Floppy_Center_Hub",
    (0, 0, front_z + 0.0012),
    0.0085,
    0.0016,
    metal_material,
    vertices=16
)
move_to_collection(hub_outer, floppy_collection)
hub_outer.parent = root

hub_inner = cylinder(
    "Floppy_Center_Hub_Inner",
    (0, 0, front_z + 0.0020),
    0.0032,
    0.0010,
    dark_material,
    vertices=12
)
move_to_collection(hub_inner, floppy_collection)
hub_inner.parent = root


# ------------------------------------------------------------
# Write-protect slider
# ------------------------------------------------------------
slider = rounded_cube(
    "Floppy_WriteProtect_Slider",
    (0.032, -0.020, front_z + 0.0011),
    (0.009, 0.013, 0.0013),
    dark_material,
    bevel=0.001
)
move_to_collection(slider, floppy_collection)
slider.parent = root

slider["state"] = "unlocked"
slider["gameplay_ready"] = True


# ------------------------------------------------------------
# Simple label markings
# ------------------------------------------------------------
line_1 = rounded_cube(
    "Floppy_Label_Line_01",
    (-0.020, 0.010, front_z + 0.00105),
    (0.025, 0.0025, 0.0007),
    white_material,
    bevel=0.0004
)
move_to_collection(line_1, floppy_collection)
line_1.parent = root

line_2 = rounded_cube(
    "Floppy_Label_Line_02",
    (-0.020, 0.004, front_z + 0.00105),
    (0.017, 0.0020, 0.0007),
    white_material,
    bevel=0.0004
)
move_to_collection(line_2, floppy_collection)
line_2.parent = root


# ------------------------------------------------------------
# Color controls
# ------------------------------------------------------------
def set_floppy_color(color):
    """
    Change the main floppy body color.

    Example:
        set_floppy_color((0.8, 0.05, 0.03, 1.0))
    """
    bsdf = floppy_material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    root["body_color"] = color


COLOR_PRESETS = {
    "BLACK": (0.015, 0.018, 0.020, 1.0),
    "DARK_BLUE": (0.035, 0.065, 0.12, 1.0),
    "BLUE": (0.025, 0.16, 0.50, 1.0),
    "RED": (0.48, 0.025, 0.02, 1.0),
    "GREEN": (0.025, 0.32, 0.06, 1.0),
    "PURPLE": (0.22, 0.035, 0.32, 1.0),
    "YELLOW": (0.60, 0.42, 0.025, 1.0),
    "WHITE": (0.72, 0.70, 0.64, 1.0),
}


def set_floppy_preset(name):
    name = str(name).upper()

    if name not in COLOR_PRESETS:
        raise ValueError(
            f"Unknown preset '{name}'. "
            f"Available: {list(COLOR_PRESETS.keys())}"
        )

    set_floppy_color(COLOR_PRESETS[name])


root["body_color"] = FLOPPY_COLOR


# ------------------------------------------------------------
# Game-ready metadata
# ------------------------------------------------------------
for obj in (
    body,
    label,
    label_strip,
    shutter,
    shutter_slot,
    hub_outer,
    hub_inner,
    slider,
    line_1,
    line_2
):
    obj["game_ready"] = True
    obj["asset"] = "FloppyDisk"

bpy.context.scene["asset_name"] = "Stylized_3.5_Floppy_Disk"
bpy.context.scene["asset_type"] = "game_prop"
bpy.context.scene["engine"] = "Godot"


# ------------------------------------------------------------
# Select root
# ------------------------------------------------------------
bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
bpy.context.view_layer.objects.active = root

print("Stylized 3.5-inch floppy disk created.")
print("Color:")
print("  set_floppy_color((R, G, B, A))")
print("Presets:")
print("  set_floppy_preset('RED')")
print("  set_floppy_preset('BLUE')")
print("  set_floppy_preset('GREEN')")
