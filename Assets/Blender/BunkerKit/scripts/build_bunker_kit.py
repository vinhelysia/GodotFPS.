"""
Phase 1 — Modular Bunker Structural Kit builder.
Run inside Blender (interactive MCP or --python).
"""
import sys
import os
from math import radians
from mathutils import Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import bunker_kit_helpers as H
import bpy

# Constants (meters)
WALL_H = 3.0
WALL_T = 0.3
WALL_W4 = 4.0
WALL_W2 = 2.0
FLOOR = 4.0
CEIL_T = 0.25
FLOOR_T = 0.2


def setup():
    H.ensure_collections()
    created = H.make_materials()
    return created


# ---------- WALLS ----------
def build_wall(name, width, damaged=False, doorway=False, window=False):
    """Wall origin: lower-left rear (outer) corner. X=width, Y=thickness inward, Z=height."""
    parts = []
    p = 0

    def P(suffix):
        nonlocal p
        p += 1
        return f"_tmp_{name}_{p}_{suffix}"

    # Main slab
    parts.append(H.box_from_corners(P("body"), 0, 0, 0, width, WALL_T, WALL_H, "MAT_Concrete_Dry").name)

    # Outer base skirting (step)
    parts.append(
        H.box_from_corners(P("skirt"), 0.05, -0.02, 0, width - 0.05, 0.04, 0.12, "MAT_Concrete_Dark").name
    )

    # Top cap band
    parts.append(
        H.box_from_corners(P("cap"), 0.05, -0.015, WALL_H - 0.12, width - 0.05, 0.03, WALL_H, "MAT_Concrete_Dark").name
    )

    # Vertical panel seams (thin inset strips on outer face)
    seam_x = [width * 0.33, width * 0.66] if width >= 3.5 else ([width * 0.5] if width > 1.5 else [])
    for i, sx in enumerate(seam_x):
        parts.append(
            H.box_from_corners(
                P(f"seam{i}"), sx - 0.015, -0.01, 0.15, sx + 0.015, 0.02, WALL_H - 0.15, "MAT_Concrete_Dark"
            ).name
        )

    # Horizontal mid panel groove
    parts.append(
        H.box_from_corners(P("hseam"), 0.1, -0.008, 1.45, width - 0.1, 0.015, 1.52, "MAT_Concrete_Dark").name
    )

    # Inner recessed panel field (slightly inset on inner face)
    inset = 0.04
    if not doorway and not window:
        parts.append(
            H.box_from_corners(
                P("recess"),
                0.2,
                WALL_T - 0.02,
                0.35,
                width - 0.2,
                WALL_T + inset,
                WALL_H - 0.35,
                "MAT_Concrete_Dark",
            ).name
        )
        # Metal reinforcement plate bottom-center
        parts.append(
            H.box_from_corners(
                P("plate"),
                width * 0.5 - 0.35,
                WALL_T + inset - 0.005,
                0.4,
                width * 0.5 + 0.35,
                WALL_T + inset + 0.025,
                0.75,
                "MAT_Metal_Dark",
            ).name
        )
        # bolts on plate
        for bx in (-0.28, 0.28):
            for bz in (0.48, 0.68):
                parts.append(
                    H.bolt(
                        P(f"bolt{bx}{bz}"),
                        width * 0.5 + bx,
                        WALL_T + inset + 0.03,
                        bz,
                        r=0.02,
                        h=0.025,
                    ).name
                )

    # Maintenance panel (metal doorette) left side
    if not doorway:
        mx0, mx1 = 0.25, 0.85
        mz0, mz1 = 1.0, 1.8
        parts.append(
            H.box_from_corners(
                P("maint"),
                mx0,
                -0.025,
                mz0,
                mx1,
                0.02,
                mz1,
                "MAT_Metal_Painted",
            ).name
        )
        parts.append(
            H.box_from_corners(
                P("maint_frame"),
                mx0 - 0.03,
                -0.015,
                mz0 - 0.03,
                mx1 + 0.03,
                0.01,
                mz1 + 0.03,
                "MAT_Metal_Dark",
            ).name
        )
        parts.append(H.bolt(P("mb1"), mx0 + 0.08, -0.03, mz1 - 0.08, r=0.018, h=0.02).name)
        parts.append(H.bolt(P("mb2"), mx1 - 0.08, -0.03, mz1 - 0.08, r=0.018, h=0.02).name)
        parts.append(H.bolt(P("mb3"), mx0 + 0.08, -0.03, mz0 + 0.08, r=0.018, h=0.02).name)
        parts.append(H.bolt(P("mb4"), mx1 - 0.08, -0.03, mz0 + 0.08, r=0.018, h=0.02).name)

    # Corner metal angle brackets outer bottom
    for side, x0, x1 in (("L", 0.0, 0.12), ("R", width - 0.12, width)):
        parts.append(
            H.box_from_corners(P(f"br{side}"), x0, -0.03, 0.0, x1, 0.05, 0.35, "MAT_Metal_Rusted").name
        )

    # Drain channel along base inner
    parts.append(
        H.box_from_corners(
            P("drain"), 0.1, WALL_T - 0.08, 0.0, width - 0.1, WALL_T - 0.02, 0.04, "MAT_Concrete_Wet"
        ).name
    )

    # Doorway cutout: leave opening by not filling center — build sides + lintel instead of solid body for doorway
    if doorway:
        # Remove body-only approach: rebuild as side posts + header + threshold
        # Delete already created body parts conceptually by not using full body —
        # For doorway we replace: delete tmp body and rebuild frame wall
        # Simpler: solid wall with opening built from pieces only
        for n in list(parts):
            H.remove_if_exists(n)
        parts = []
        door_w, door_h = 1.2, 2.2
        door_x0 = (width - door_w) * 0.5
        door_x1 = door_x0 + door_w
        # left wall
        parts.append(H.box_from_corners(P("L"), 0, 0, 0, door_x0, WALL_T, WALL_H, "MAT_Concrete_Dry").name)
        # right wall
        parts.append(H.box_from_corners(P("R"), door_x1, 0, 0, width, WALL_T, WALL_H, "MAT_Concrete_Dry").name)
        # lintel
        parts.append(
            H.box_from_corners(P("lintel"), door_x0, 0, door_h, door_x1, WALL_T, WALL_H, "MAT_Concrete_Dry").name
        )
        # threshold
        parts.append(
            H.box_from_corners(
                P("thresh"), door_x0, -0.02, 0, door_x1, WALL_T + 0.05, 0.08, "MAT_Concrete_Dark"
            ).name
        )
        # door recess surround (inner step)
        rec = 0.06
        parts.append(
            H.box_from_corners(
                P("recL"), door_x0, WALL_T, 0.08, door_x0 + rec, WALL_T + 0.05, door_h, "MAT_Concrete_Dark"
            ).name
        )
        parts.append(
            H.box_from_corners(
                P("recR"), door_x1 - rec, WALL_T, 0.08, door_x1, WALL_T + 0.05, door_h, "MAT_Concrete_Dark"
            ).name
        )
        parts.append(
            H.box_from_corners(
                P("recT"), door_x0, WALL_T, door_h - rec, door_x1, WALL_T + 0.05, door_h, "MAT_Concrete_Dark"
            ).name
        )
        # metal frame plate around opening
        parts.append(
            H.box_from_corners(
                P("mframeL"),
                door_x0 - 0.05,
                -0.02,
                0.08,
                door_x0 + 0.02,
                WALL_T + 0.02,
                door_h + 0.05,
                "MAT_Metal_Dark",
            ).name
        )
        parts.append(
            H.box_from_corners(
                P("mframeR"),
                door_x1 - 0.02,
                -0.02,
                0.08,
                door_x1 + 0.05,
                WALL_T + 0.02,
                door_h + 0.05,
                "MAT_Metal_Dark",
            ).name
        )
        parts.append(
            H.box_from_corners(
                P("mframeT"),
                door_x0 - 0.05,
                -0.02,
                door_h,
                door_x1 + 0.05,
                WALL_T + 0.02,
                door_h + 0.08,
                "MAT_Metal_Dark",
            ).name
        )
        # outer seams
        parts.append(H.box_from_corners(P("skirt"), 0.05, -0.02, 0, width - 0.05, 0.04, 0.1, "MAT_Concrete_Dark").name)
        for bx in (door_x0 - 0.02, door_x1 + 0.02):
            for bz in (0.4, 1.1, 1.9):
                parts.append(H.bolt(P(f"db{bx}{bz}"), bx, -0.03, bz, r=0.02, h=0.03).name)

    if window:
        for n in list(parts):
            H.remove_if_exists(n)
        parts = []
        win_w, win_h = 1.4, 0.9
        win_x0 = (width - win_w) * 0.5
        win_x1 = win_x0 + win_w
        win_z0, win_z1 = 1.2, 1.2 + win_h
        # wall body around opening
        parts.append(H.box_from_corners(P("bot"), 0, 0, 0, width, WALL_T, win_z0, "MAT_Concrete_Dry").name)
        parts.append(H.box_from_corners(P("top"), 0, 0, win_z1, width, WALL_T, WALL_H, "MAT_Concrete_Dry").name)
        parts.append(H.box_from_corners(P("L"), 0, 0, win_z0, win_x0, WALL_T, win_z1, "MAT_Concrete_Dry").name)
        parts.append(H.box_from_corners(P("R"), win_x1, 0, win_z0, width, WALL_T, win_z1, "MAT_Concrete_Dry").name)
        # metal sill / lintel / side reveals — bars seat on these surfaces
        sill_z0, sill_z1 = win_z0 - 0.06, win_z0 + 0.03
        lint_z0, lint_z1 = win_z1 - 0.03, win_z1 + 0.06
        reveal = 0.04
        parts.append(
            H.box_from_corners(
                P("sill"), win_x0 - 0.06, -0.04, sill_z0, win_x1 + 0.06, WALL_T + 0.04, sill_z1, "MAT_Metal_Dark"
            ).name
        )
        parts.append(
            H.box_from_corners(
                P("wlintel"), win_x0 - 0.06, -0.03, lint_z0, win_x1 + 0.06, WALL_T + 0.03, lint_z1, "MAT_Metal_Dark"
            ).name
        )
        parts.append(
            H.box_from_corners(
                P("revL"), win_x0 - 0.04, -0.02, sill_z1, win_x0 + reveal, WALL_T + 0.02, lint_z0, "MAT_Metal_Dark"
            ).name
        )
        parts.append(
            H.box_from_corners(
                P("revR"), win_x1 - reveal, -0.02, sill_z1, win_x1 + 0.04, WALL_T + 0.02, lint_z0, "MAT_Metal_Dark"
            ).name
        )
        # bars: full span sill top → lintel bottom, and side reveal → side reveal
        bar_r = 0.025
        bar_y0, bar_y1 = 0.06, WALL_T - 0.06
        for i in range(3):
            t = (i + 1) / 4.0
            x = win_x0 + reveal + t * (win_w - 2 * reveal)
            parts.append(
                H.box_from_corners(
                    P(f"vbar{i}"),
                    x - bar_r,
                    bar_y0,
                    sill_z1,
                    x + bar_r,
                    bar_y1,
                    lint_z0,
                    "MAT_Metal_Rusted",
                ).name
            )
        for j in range(2):
            t = (j + 1) / 3.0
            z = sill_z1 + t * (lint_z0 - sill_z1)
            parts.append(
                H.box_from_corners(
                    P(f"hbar{j}"),
                    win_x0 + reveal,
                    bar_y0,
                    z - bar_r,
                    win_x1 - reveal,
                    bar_y1,
                    z + bar_r,
                    "MAT_Metal_Rusted",
                ).name
            )
        parts.append(H.box_from_corners(P("skirt"), 0.05, -0.02, 0, width - 0.05, 0.04, 0.1, "MAT_Concrete_Dark").name)
        parts.append(
            H.box_from_corners(P("panel"), 0.2, -0.015, 0.3, width - 0.2, 0.02, 0.9, "MAT_Concrete_Dark").name
        )

    if damaged and not doorway and not window:
        # Angular broken chunk missing upper-right outer, exposed inner concrete + rebar
        # subtract by not removing — add jagged silhouette pieces and gap
        # Remove upper-right portion of body visually: rebuild body as left + bottom right
        for n in list(parts):
            if "body" in n:
                H.remove_if_exists(n)
                parts.remove(n)
        # left solid
        parts.append(H.box_from_corners(P("bodyL"), 0, 0, 0, width * 0.55, WALL_T, WALL_H, "MAT_Concrete_Dry").name)
        # lower right
        parts.append(
            H.box_from_corners(P("bodyBR"), width * 0.55, 0, 0, width, WALL_T, 1.6, "MAT_Concrete_Dry").name
        )
        # stepped broken mid
        parts.append(
            H.box_from_corners(P("bodyM"), width * 0.55, 0, 1.6, width * 0.78, WALL_T, 2.25, "MAT_Concrete_Dry").name
        )
        parts.append(
            H.box_from_corners(P("bodyM2"), width * 0.55, 0, 2.25, width * 0.65, WALL_T, 2.7, "MAT_Concrete_Dry").name
        )
        # jagged teeth
        parts.append(
            H.box_from_corners(P("jag1"), width * 0.78, 0, 1.6, width * 0.9, WALL_T * 0.7, 1.95, "MAT_Concrete_Inner").name
        )
        parts.append(
            H.box_from_corners(P("jag2"), width * 0.65, 0, 2.25, width * 0.72, WALL_T * 0.6, 2.5, "MAT_Concrete_Inner").name
        )
        # exposed rebar (metal rods)
        for i, (rx, rz) in enumerate(
            [
                (width * 0.82, 1.85),
                (width * 0.88, 2.05),
                (width * 0.7, 2.4),
                (width * 0.75, 2.55),
            ]
        ):
            parts.append(
                H.cylinder_n(
                    P(f"rebar{i}"),
                    0.012,
                    0.35,
                    6,
                    (rx, WALL_T * 0.4, rz),
                    (radians(20 + i * 12), 0, radians(15 * i)),
                    "MAT_Metal_Rusted",
                ).name
            )
        # rubble block on floor in front of damage
        parts.append(
            H.box_from_corners(
                P("rubble"),
                width * 0.7,
                -0.15,
                0,
                width * 0.95,
                0.1,
                0.18,
                "MAT_Concrete_Inner",
            ).name
        )
        parts.append(
            H.box_from_corners(
                P("rubble2"),
                width * 0.75,
                -0.22,
                0,
                width * 0.88,
                -0.05,
                0.12,
                "MAT_Concrete_Dark",
            ).name
        )

    obj = H.join_parts(name, parts, origin_world=(0, 0, 0), col_name="COL_Structures", bevel=True, bevel_w=0.01)
    return obj


def build_floor(name, damaged=False):
    """4x4 floor, origin lower corner (0,0,0) at top surface corner? Spec: one lower corner.
    Place slab from z=-FLOOR_T to z=0 so walk surface at z=0. Origin at (0,0,0) corner of top."""
    parts = []
    p = 0

    def P(s):
        nonlocal p
        p += 1
        return f"_tmp_{name}_{p}_{s}"

    w = FLOOR
    t = FLOOR_T
    if not damaged:
        parts.append(H.box_from_corners(P("slab"), 0, 0, -t, w, w, 0, "MAT_Concrete_Dry").name)
    else:
        # missing corner chunk
        parts.append(H.box_from_corners(P("slabA"), 0, 0, -t, w * 0.65, w, 0, "MAT_Concrete_Dry").name)
        parts.append(H.box_from_corners(P("slabB"), w * 0.65, 0, -t, w, w * 0.55, 0, "MAT_Concrete_Dry").name)
        parts.append(
            H.box_from_corners(P("slabC"), w * 0.65, w * 0.55, -t, w * 0.85, w * 0.8, 0, "MAT_Concrete_Dry").name
        )
        # broken edge inner
        parts.append(
            H.box_from_corners(
                P("inner"), w * 0.65, w * 0.55, -t * 0.9, w * 0.9, w * 0.75, -0.02, "MAT_Concrete_Inner"
            ).name
        )
        for i, (rx, ry) in enumerate([(w * 0.88, w * 0.7), (w * 0.78, w * 0.85), (w * 0.92, w * 0.6)]):
            parts.append(
                H.cylinder_n(
                    P(f"rebar{i}"),
                    0.012,
                    0.4,
                    6,
                    (rx, ry, -0.05),
                    (radians(90), 0, radians(30 * i)),
                    "MAT_Metal_Rusted",
                ).name
            )
        parts.append(
            H.box_from_corners(P("rubble"), w * 0.8, w * 0.8, 0, w * 0.98, w * 0.98, 0.12, "MAT_Concrete_Inner").name
        )

    # panel seams (grid 2x2)
    for i in (1, 2, 3):
        x = w * i / 4 if damaged else w * i / 2  # for clean floor use mid seams
    for sx in (w * 0.5,):
        parts.append(
            H.box_from_corners(P(f"vseam{sx}"), sx - 0.02, 0.05, -0.01, sx + 0.02, w - 0.05, 0.015, "MAT_Concrete_Dark").name
        )
    for sy in (w * 0.5,):
        parts.append(
            H.box_from_corners(P(f"hseam{sy}"), 0.05, sy - 0.02, -0.01, w - 0.05, sy + 0.02, 0.015, "MAT_Concrete_Dark").name
        )

    # drain channel
    parts.append(
        H.box_from_corners(P("drain"), 0.15, 0.15, -0.02, w - 0.15, 0.28, 0.01, "MAT_Concrete_Wet").name
    )
    # metal grate plate
    parts.append(
        H.box_from_corners(P("grate"), w * 0.5 - 0.4, 0.12, 0.0, w * 0.5 + 0.4, 0.32, 0.03, "MAT_Metal_Dark").name
    )
    # grate slots
    for i in range(4):
        gx = w * 0.5 - 0.3 + i * 0.2
        parts.append(
            H.box_from_corners(P(f"slot{i}"), gx - 0.03, 0.14, 0.025, gx + 0.03, 0.3, 0.04, "MAT_Concrete_Inner").name
        )

    # edge bevel lip
    parts.append(H.box_from_corners(P("edgeX0"), 0, 0, -0.03, 0.06, w, 0.02, "MAT_Concrete_Dark").name)
    parts.append(H.box_from_corners(P("edgeX1"), w - 0.06, 0, -0.03, w, w, 0.02, "MAT_Concrete_Dark").name)

    obj = H.join_parts(name, parts, origin_world=(0, 0, 0), col_name="COL_Structures", bevel=True, bevel_w=0.008)
    return obj


def build_ceiling(name, damaged=False):
    """4x4 ceiling, origin lower corner of bottom face at z=0 (underside), thickness upward.
    For modular: ceiling sits at z=3 with underside at room height. Master origin at corner of underside."""
    parts = []
    p = 0

    def P(s):
        nonlocal p
        p += 1
        return f"_tmp_{name}_{p}_{s}"

    w = FLOOR
    t = CEIL_T
    if not damaged:
        parts.append(H.box_from_corners(P("slab"), 0, 0, 0, w, w, t, "MAT_Concrete_Dry").name)
    else:
        parts.append(H.box_from_corners(P("slabA"), 0, 0, 0, w, w * 0.6, t, "MAT_Concrete_Dry").name)
        parts.append(H.box_from_corners(P("slabB"), 0, w * 0.6, 0, w * 0.55, w, t, "MAT_Concrete_Dry").name)
        parts.append(
            H.box_from_corners(P("slabC"), w * 0.55, w * 0.6, 0.05, w * 0.8, w * 0.85, t, "MAT_Concrete_Inner").name
        )
        for i, (rx, ry) in enumerate([(w * 0.7, w * 0.75), (w * 0.85, w * 0.7)]):
            parts.append(
                H.cylinder_n(
                    P(f"rebar{i}"),
                    0.012,
                    0.45,
                    6,
                    (rx, ry, 0.1),
                    (radians(70), radians(10 * i), 0),
                    "MAT_Metal_Rusted",
                ).name
            )

    # recessed light tray (dark metal)
    parts.append(
        H.box_from_corners(
            P("tray"), w * 0.5 - 0.8, w * 0.5 - 0.15, -0.04, w * 0.5 + 0.8, w * 0.5 + 0.15, 0.02, "MAT_Metal_Dark"
        ).name
    )
    # conduit
    parts.append(
        H.box_from_corners(P("conduit"), 0.2, w * 0.5 - 0.04, -0.03, w - 0.2, w * 0.5 + 0.04, 0.02, "MAT_Metal_Painted").name
    )
    # panel seams
    parts.append(
        H.box_from_corners(P("seam"), w * 0.5 - 0.015, 0.1, -0.01, w * 0.5 + 0.015, w - 0.1, 0.02, "MAT_Concrete_Dark").name
    )
    # hangers / brackets
    for i, x in enumerate([0.5, w - 0.5]):
        parts.append(
            H.box_from_corners(P(f"hang{i}"), x - 0.08, w * 0.5 - 0.08, -0.08, x + 0.08, w * 0.5 + 0.08, 0.0, "MAT_Metal_Dark").name
        )

    obj = H.join_parts(name, parts, origin_world=(0, 0, 0), col_name="COL_Structures", bevel=True, bevel_w=0.008)
    return obj


def build_corridor_straight(name):
    """4m corridor module: floor + two walls + ceiling strip, width 4m interior, length 4m.
    Outer footprint: length X=4, interior width ~3.4 between walls, walls on Y sides.
    Origin: lower-left rear corner of module footprint (0,0,0)."""
    parts = []
    p = 0

    def P(s):
        nonlocal p
        p += 1
        return f"_tmp_{name}_{p}_{s}"

    length = 4.0
    outer_w = 4.0
    # floor
    parts.append(H.box_from_corners(P("floor"), 0, WALL_T, -FLOOR_T, length, outer_w - WALL_T, 0, "MAT_Concrete_Dry").name)
    # walls left (y small) and right (y large)
    parts.append(H.box_from_corners(P("wallL"), 0, 0, 0, length, WALL_T, WALL_H, "MAT_Concrete_Dry").name)
    parts.append(
        H.box_from_corners(P("wallR"), 0, outer_w - WALL_T, 0, length, outer_w, WALL_H, "MAT_Concrete_Dry").name
    )
    # ceiling
    parts.append(
        H.box_from_corners(P("ceil"), 0, WALL_T, WALL_H, length, outer_w - WALL_T, WALL_H + CEIL_T, "MAT_Concrete_Dark").name
    )
    # wall panel details
    for wall_y0, wall_y1, sign in ((0, WALL_T, -1), (outer_w - WALL_T, outer_w, 1)):
        y_out = wall_y0 - 0.02 if sign < 0 else wall_y1 + 0.02
        y_in = wall_y0 - 0.01 if sign < 0 else wall_y1 + 0.01
        parts.append(
            H.box_from_corners(P(f"skirt{sign}"), 0.1, min(y_out, y_in), 0, length - 0.1, max(y_out, y_in), 0.1, "MAT_Concrete_Dark").name
        )
        for sx in (length * 0.33, length * 0.66):
            parts.append(
                H.box_from_corners(
                    P(f"seam{sign}{sx}"),
                    sx - 0.015,
                    min(y_out, wall_y0 if sign < 0 else wall_y1),
                    0.2,
                    sx + 0.015,
                    max(y_out, wall_y0 if sign < 0 else wall_y1),
                    WALL_H - 0.2,
                    "MAT_Concrete_Dark",
                ).name
            )
    # floor drain
    parts.append(
        H.box_from_corners(P("drain"), 0.2, outer_w * 0.5 - 0.08, -0.02, length - 0.2, outer_w * 0.5 + 0.08, 0.015, "MAT_Concrete_Wet").name
    )
    # ceiling light tray
    parts.append(
        H.box_from_corners(
            P("light"),
            length * 0.5 - 0.6,
            outer_w * 0.5 - 0.12,
            WALL_H - 0.05,
            length * 0.5 + 0.6,
            outer_w * 0.5 + 0.12,
            WALL_H + 0.02,
            "MAT_Metal_Dark",
        ).name
    )
    # conduit
    parts.append(
        H.box_from_corners(
            P("conduit"),
            0.15,
            outer_w - WALL_T - 0.12,
            WALL_H - 0.15,
            length - 0.15,
            outer_w - WALL_T - 0.04,
            WALL_H - 0.08,
            "MAT_Metal_Painted",
        ).name
    )
    # metal base plates
    for y0, y1 in ((WALL_T, WALL_T + 0.04), (outer_w - WALL_T - 0.04, outer_w - WALL_T)):
        parts.append(
            H.box_from_corners(P(f"base{y0}"), 0.05, y0, 0, length - 0.05, y1, 0.06, "MAT_Metal_Rusted").name
        )

    obj = H.join_parts(name, parts, origin_world=(0, 0, 0), col_name="COL_Structures", bevel=True, bevel_w=0.01)
    return obj


def build_corridor_corner(name):
    """L-shaped corridor corner, 4m legs, outer footprint 4x4, origin lower-left outer corner."""
    parts = []
    p = 0

    def P(s):
        nonlocal p
        p += 1
        return f"_tmp_{name}_{p}_{s}"

    L = 4.0
    # floor L shape
    parts.append(H.box_from_corners(P("f1"), 0, WALL_T, -FLOOR_T, L, L - WALL_T, 0, "MAT_Concrete_Dry").name)
    # walls: outer south (y=0) full length, outer west (x=0) full, inner L
    parts.append(H.box_from_corners(P("wallS"), 0, 0, 0, L, WALL_T, WALL_H, "MAT_Concrete_Dry").name)
    parts.append(H.box_from_corners(P("wallW"), 0, WALL_T, 0, WALL_T, L, WALL_H, "MAT_Concrete_Dry").name)
    # inner walls forming corridor path along +X then +Y
    # corridor opens: from x=WALL_T..L at y near 0 side, then turns
    # Inner wall parallel to south, starts after corridor width
    corridor_inner = L - WALL_T  # outer edge of floor already
    # wall along north of east-west run (partial)
    parts.append(
        H.box_from_corners(P("wallN"), WALL_T, L - WALL_T, 0, L, L, WALL_H, "MAT_Concrete_Dry").name
    )
    # wall along east of north-south run
    parts.append(
        H.box_from_corners(P("wallE"), L - WALL_T, WALL_T, 0, L, L - WALL_T, WALL_H, "MAT_Concrete_Dry").name
    )
    # ceiling L
    parts.append(
        H.box_from_corners(P("c1"), 0, WALL_T, WALL_H, L, L - WALL_T, WALL_H + CEIL_T, "MAT_Concrete_Dark").name
    )
    # corner column reinforcement
    parts.append(
        H.box_from_corners(P("col"), WALL_T, WALL_T, 0, WALL_T + 0.25, WALL_T + 0.25, WALL_H, "MAT_Concrete_Dark").name
    )
    parts.append(
        H.box_from_corners(P("colM"), WALL_T, WALL_T, 0, WALL_T + 0.28, WALL_T + 0.05, 0.4, "MAT_Metal_Dark").name
    )
    # floor drain curve approximation
    parts.append(
        H.box_from_corners(P("drain"), 0.4, 0.5, -0.02, L - 0.4, 0.65, 0.015, "MAT_Concrete_Wet").name
    )
    parts.append(
        H.box_from_corners(P("drain2"), 0.5, 0.5, -0.02, 0.65, L - 0.4, 0.015, "MAT_Concrete_Wet").name
    )
    # wall seams
    for sx in (1.3, 2.6):
        parts.append(
            H.box_from_corners(P(f"seamS{sx}"), sx - 0.015, -0.015, 0.2, sx + 0.015, 0.02, WALL_H - 0.2, "MAT_Concrete_Dark").name
        )

    obj = H.join_parts(name, parts, origin_world=(0, 0, 0), col_name="COL_Structures", bevel=True, bevel_w=0.01)
    return obj


def build_corridor_t(name):
    """T-junction: main run along X, branch +Y center. Footprint 4x4."""
    parts = []
    p = 0

    def P(s):
        nonlocal p
        p += 1
        return f"_tmp_{name}_{p}_{s}"

    L = 4.0
    # full floor
    parts.append(H.box_from_corners(P("floor"), 0, WALL_T, -FLOOR_T, L, L - WALL_T, 0, "MAT_Concrete_Dry").name)
    # south outer wall full
    parts.append(H.box_from_corners(P("wallS"), 0, 0, 0, L, WALL_T, WALL_H, "MAT_Concrete_Dry").name)
    # north wall with center opening for T branch
    open_w = 3.4  # interior width of branch
    # actually outer is 4, walls 0.3 each side interior 3.4
    gap0 = (L - (L - 2 * WALL_T)) * 0.5  # simplify: opening from WALL_T to L-WALL_T on north? 
    # T branch opens north: north wall only on left and right thirds
    gap_x0 = WALL_T
    gap_x1 = L - WALL_T
    # For T: main corridor E-W, branch north. North wall only partial at ends? 
    # Actually walls on north left of branch and right of branch - if branch is full width no north wall.
    # Standard T: walls form continuous tube. 
    # West wall full, East wall full, South wall full, North wall with gap in middle for branch — 
    # if footprint is just the junction volume, north has two stubs.
    mid0, mid1 = 1.0, 3.0  # opening for north branch
    parts.append(H.box_from_corners(P("wallNL"), 0, L - WALL_T, 0, mid0, L, WALL_H, "MAT_Concrete_Dry").name)
    parts.append(H.box_from_corners(P("wallNR"), mid1, L - WALL_T, 0, L, L, WALL_H, "MAT_Concrete_Dry").name)
    parts.append(H.box_from_corners(P("wallW"), 0, WALL_T, 0, WALL_T, L - WALL_T, WALL_H, "MAT_Concrete_Dry").name)
    parts.append(H.box_from_corners(P("wallE"), L - WALL_T, WALL_T, 0, L, L - WALL_T, WALL_H, "MAT_Concrete_Dry").name)
    # ceiling
    parts.append(
        H.box_from_corners(P("ceil"), 0, WALL_T, WALL_H, L, L - WALL_T, WALL_H + CEIL_T, "MAT_Concrete_Dark").name
    )
    # reinforcement around T opening
    for x in (mid0 - 0.08, mid1):
        parts.append(
            H.box_from_corners(P(f"post{x}"), x, L - WALL_T - 0.05, 0, x + 0.08, L - WALL_T + 0.05, WALL_H, "MAT_Metal_Dark").name
        )
    parts.append(
        H.box_from_corners(P("drain"), 0.3, L * 0.5 - 0.08, -0.02, L - 0.3, L * 0.5 + 0.08, 0.015, "MAT_Concrete_Wet").name
    )
    parts.append(
        H.box_from_corners(P("light"), L * 0.5 - 0.5, L * 0.5 - 0.1, WALL_H - 0.04, L * 0.5 + 0.5, L * 0.5 + 0.1, WALL_H + 0.02, "MAT_Metal_Dark").name
    )

    obj = H.join_parts(name, parts, origin_world=(0, 0, 0), col_name="COL_Structures", bevel=True, bevel_w=0.01)
    return obj


def build_corridor_cross(name):
    """Cross junction 4x4."""
    parts = []
    p = 0

    def P(s):
        nonlocal p
        p += 1
        return f"_tmp_{name}_{p}_{s}"

    L = 4.0
    mid0, mid1 = 1.0, 3.0
    parts.append(H.box_from_corners(P("floor"), WALL_T, WALL_T, -FLOOR_T, L - WALL_T, L - WALL_T, 0, "MAT_Concrete_Dry").name)
    # four outer walls with center openings
    # South
    parts.append(H.box_from_corners(P("sL"), 0, 0, 0, mid0, WALL_T, WALL_H, "MAT_Concrete_Dry").name)
    parts.append(H.box_from_corners(P("sR"), mid1, 0, 0, L, WALL_T, WALL_H, "MAT_Concrete_Dry").name)
    # North
    parts.append(H.box_from_corners(P("nL"), 0, L - WALL_T, 0, mid0, L, WALL_H, "MAT_Concrete_Dry").name)
    parts.append(H.box_from_corners(P("nR"), mid1, L - WALL_T, 0, L, L, WALL_H, "MAT_Concrete_Dry").name)
    # West
    parts.append(H.box_from_corners(P("wB"), 0, 0, 0, WALL_T, mid0, WALL_H, "MAT_Concrete_Dry").name)
    parts.append(H.box_from_corners(P("wT"), 0, mid1, 0, WALL_T, L, WALL_H, "MAT_Concrete_Dry").name)
    # East
    parts.append(H.box_from_corners(P("eB"), L - WALL_T, 0, 0, L, mid0, WALL_H, "MAT_Concrete_Dry").name)
    parts.append(H.box_from_corners(P("eT"), L - WALL_T, mid1, 0, L, L, WALL_H, "MAT_Concrete_Dry").name)
    # floor fill to edges in corridor arms
    parts.append(H.box_from_corners(P("fS"), mid0, 0, -FLOOR_T, mid1, WALL_T, 0, "MAT_Concrete_Dry").name)
    parts.append(H.box_from_corners(P("fN"), mid0, L - WALL_T, -FLOOR_T, mid1, L, 0, "MAT_Concrete_Dry").name)
    parts.append(H.box_from_corners(P("fW"), 0, mid0, -FLOOR_T, WALL_T, mid1, 0, "MAT_Concrete_Dry").name)
    parts.append(H.box_from_corners(P("fE"), L - WALL_T, mid0, -FLOOR_T, L, mid1, 0, "MAT_Concrete_Dry").name)
    # ceiling cross
    parts.append(
        H.box_from_corners(P("ceil"), WALL_T, WALL_T, WALL_H, L - WALL_T, L - WALL_T, WALL_H + CEIL_T, "MAT_Concrete_Dark").name
    )
    parts.append(
        H.box_from_corners(P("ceilS"), mid0, 0, WALL_H, mid1, WALL_T, WALL_H + CEIL_T, "MAT_Concrete_Dark").name
    )
    parts.append(
        H.box_from_corners(P("ceilN"), mid0, L - WALL_T, WALL_H, mid1, L, WALL_H + CEIL_T, "MAT_Concrete_Dark").name
    )
    parts.append(
        H.box_from_corners(P("ceilW"), 0, mid0, WALL_H, WALL_T, mid1, WALL_H + CEIL_T, "MAT_Concrete_Dark").name
    )
    parts.append(
        H.box_from_corners(P("ceilE"), L - WALL_T, mid0, WALL_H, L, mid1, WALL_H + CEIL_T, "MAT_Concrete_Dark").name
    )
    # center ring metal
    parts.append(
        H.box_from_corners(
            P("ring"), L * 0.5 - 0.4, L * 0.5 - 0.4, -0.01, L * 0.5 + 0.4, L * 0.5 + 0.4, 0.04, "MAT_Metal_Dark"
        ).name
    )
    parts.append(
        H.box_from_corners(
            P("ringIn"), L * 0.5 - 0.25, L * 0.5 - 0.25, 0.03, L * 0.5 + 0.25, L * 0.5 + 0.25, 0.05, "MAT_Concrete_Inner"
        ).name
    )

    obj = H.join_parts(name, parts, origin_world=(0, 0, 0), col_name="COL_Structures", bevel=True, bevel_w=0.01)
    return obj


def build_pillar(name):
    """Pillar origin: center of footprint at ground."""
    parts = []
    p = 0

    def P(s):
        nonlocal p
        p += 1
        return f"_tmp_{name}_{p}_{s}"

    s = 0.45  # half-width ~0.225? full width 0.45
    half = s * 0.5
    # main shaft octagonal-ish via box + chamfer plates
    parts.append(H.box_from_corners(P("shaft"), -half, -half, 0.08, half, half, WALL_H - 0.08, "MAT_Concrete_Dry").name)
    # base plinth
    b = half + 0.08
    parts.append(H.box_from_corners(P("base"), -b, -b, 0, b, b, 0.12, "MAT_Concrete_Dark").name)
    parts.append(H.box_from_corners(P("base2"), -half - 0.04, -half - 0.04, 0.12, half + 0.04, half + 0.04, 0.22, "MAT_Concrete_Dark").name)
    # capital
    parts.append(H.box_from_corners(P("cap"), -b, -b, WALL_H - 0.12, b, b, WALL_H, "MAT_Concrete_Dark").name)
    # metal bands
    for z in (0.5, 1.5, 2.5):
        parts.append(
            H.box_from_corners(P(f"band{z}"), -half - 0.02, -half - 0.02, z, half + 0.02, half + 0.02, z + 0.06, "MAT_Metal_Dark").name
        )
    # corner bolts on base
    for x, y in ((-b + 0.05, -b + 0.05), (b - 0.05, -b + 0.05), (-b + 0.05, b - 0.05), (b - 0.05, b - 0.05)):
        parts.append(H.bolt(P(f"bolt{x}{y}"), x, y, 0.13, r=0.02, h=0.03).name)
    # recessed panel on one face
    parts.append(
        H.box_from_corners(P("panel"), half - 0.01, -0.12, 0.8, half + 0.03, 0.12, 1.4, "MAT_Metal_Painted").name
    )

    obj = H.join_parts(name, parts, origin_world=(0, 0, 0), col_name="COL_Structures", bevel=True, bevel_w=0.01)
    return obj


def build_stairs(name):
    """Stairs: rise 3m over run ~3.36m, width 1.4m. Origin bottom-center snap.

    Open sides with thin lips (no solid side walls). Stepped metal handrails
    use thin horizontal/vertical segments — never diagonal AABB-filled boxes.
    """
    parts = []
    p = 0

    def P(s):
        nonlocal p
        p += 1
        return f"_tmp_{name}_{p}_{s}"

    steps = 12
    rise = WALL_H / steps
    run = 0.28
    width = 1.4
    half_w = width * 0.5
    rail_h = 0.9
    post_r = 0.018
    stringer_t = 0.07

    for i in range(steps):
        z0 = i * rise
        y0 = i * run
        parts.append(
            H.box_from_corners(
                P(f"step{i}"),
                -half_w,
                y0,
                z0,
                half_w,
                y0 + run + 0.012,
                z0 + rise,
                "MAT_Concrete_Dry" if i % 2 == 0 else "MAT_Concrete_Dark",
            ).name
        )

    # thin side lips only (not solid full-height walls)
    for side, x0, x1 in (("L", -half_w - stringer_t, -half_w), ("R", half_w, half_w + stringer_t)):
        for i in range(steps):
            z0 = i * rise
            y0 = i * run
            parts.append(
                H.box_from_corners(
                    P(f"lip{side}{i}"),
                    x0,
                    y0,
                    z0,
                    x1,
                    y0 + run + 0.012,
                    z0 + rise + 0.015,
                    "MAT_Concrete_Dark",
                ).name
            )

    for i in range(0, steps - 1, 2):
        y0 = i * run
        z1 = max(i * rise + rise * 0.4, 0.1)
        parts.append(
            H.box_from_corners(
                P(f"sup{i}"), -0.1, y0, 0, 0.1, y0 + run * 2, z1, "MAT_Concrete_Inner"
            ).name
        )

    post_indices = sorted(set(list(range(0, steps, 2)) + [steps - 1]))
    for side, x in (("L", -half_w - stringer_t * 0.5), ("R", half_w + stringer_t * 0.5)):
        for i in post_indices:
            y = i * run + run * 0.35
            z_tread = i * rise + rise
            z_rail = z_tread + rail_h
            parts.append(
                H.box_from_corners(
                    P(f"post{side}{i}"),
                    x - post_r,
                    y - post_r,
                    z_tread,
                    x + post_r,
                    y + post_r,
                    z_rail,
                    "MAT_Metal_Dark",
                ).name
            )
        # stepped thin rails (horizontal + short vertical risers)
        for i in range(steps):
            z_rail = i * rise + rise + rail_h
            y0 = i * run + 0.02
            y1 = (i + 1) * run + 0.02 if i < steps - 1 else i * run + run * 0.7
            parts.append(
                H.box_from_corners(
                    P(f"hrail{side}{i}"),
                    x - 0.02,
                    y0,
                    z_rail - 0.02,
                    x + 0.02,
                    y1,
                    z_rail + 0.02,
                    "MAT_Metal_Dark",
                ).name
            )
            if i < steps - 1:
                z_next = (i + 1) * rise + rise + rail_h
                parts.append(
                    H.box_from_corners(
                        P(f"vrail{side}{i}"),
                        x - 0.018,
                        y1 - 0.025,
                        z_rail - 0.02,
                        x + 0.018,
                        y1 + 0.01,
                        z_next + 0.02,
                        "MAT_Metal_Dark",
                    ).name
                )

    parts.append(
        H.box_from_corners(
            P("land"), -half_w - 0.08, -0.1, -0.04, half_w + 0.08, 0.03, 0.015, "MAT_Metal_Rusted"
        ).name
    )

    obj = H.join_parts(name, parts, origin_world=(0, 0, 0), col_name="COL_Structures", bevel=True, bevel_w=0.005)
    return obj


def build_door_frame(name):
    """Door frame standalone, origin center ground."""
    parts = []
    p = 0

    def P(s):
        nonlocal p
        p += 1
        return f"_tmp_{name}_{p}_{s}"

    door_w, door_h = 1.2, 2.2
    t = 0.12
    half = door_w * 0.5
    # left/right/top jambs
    parts.append(H.box_from_corners(P("L"), -half - t, -0.08, 0, -half, 0.08, door_h + t, "MAT_Metal_Dark").name)
    parts.append(H.box_from_corners(P("R"), half, -0.08, 0, half + t, 0.08, door_h + t, "MAT_Metal_Dark").name)
    parts.append(H.box_from_corners(P("T"), -half - t, -0.08, door_h, half + t, 0.08, door_h + t, "MAT_Metal_Dark").name)
    # threshold
    parts.append(H.box_from_corners(P("th"), -half - t, -0.12, 0, half + t, 0.12, 0.06, "MAT_Metal_Rusted").name)
    # stop lip
    parts.append(H.box_from_corners(P("stopL"), -half, 0.05, 0.06, -half + 0.03, 0.09, door_h, "MAT_Metal_Painted").name)
    parts.append(H.box_from_corners(P("stopR"), half - 0.03, 0.05, 0.06, half, 0.09, door_h, "MAT_Metal_Painted").name)
    parts.append(H.box_from_corners(P("stopT"), -half, 0.05, door_h - 0.03, half, 0.09, door_h, "MAT_Metal_Painted").name)
    for z in (0.3, 1.1, 1.9):
        parts.append(H.bolt(P(f"bL{z}"), -half - t * 0.5, -0.09, z, r=0.018, h=0.025).name)
        parts.append(H.bolt(P(f"bR{z}"), half + t * 0.5, -0.09, z, r=0.018, h=0.025).name)

    obj = H.join_parts(name, parts, origin_world=(0, 0, 0), col_name="COL_Structures", bevel=True, bevel_w=0.008)
    return obj


def build_bulkhead_door():
    """Interactive multi-object bulkhead door. Parent empty at ground center."""
    base = "INT_Bunker_BulkheadDoor_A"
    # clean old
    for n in list(bpy.data.objects.keys()):
        if n.startswith(base) or n.startswith(f"_tmp_{base}"):
            H.remove_if_exists(n)

    door_w, door_h, door_t = 1.3, 2.3, 0.12
    half = door_w * 0.5
    frame_t = 0.15

    # --- Frame (static) ---
    fparts = []
    p = 0

    def FP(s):
        nonlocal p
        p += 1
        return f"_tmp_{base}_F_{p}_{s}"

    fparts.append(H.box_from_corners(FP("L"), -half - frame_t, -0.1, 0, -half, 0.15, door_h + frame_t, "MAT_Metal_Dark").name)
    fparts.append(H.box_from_corners(FP("R"), half, -0.1, 0, half + frame_t, 0.15, door_h + frame_t, "MAT_Metal_Dark").name)
    fparts.append(H.box_from_corners(FP("T"), -half - frame_t, -0.1, door_h, half + frame_t, 0.15, door_h + frame_t, "MAT_Metal_Dark").name)
    fparts.append(H.box_from_corners(FP("th"), -half - frame_t, -0.15, 0, half + frame_t, 0.15, 0.08, "MAT_Metal_Rusted").name)
    # thick chamfered outer frame plates
    fparts.append(H.box_from_corners(FP("outerL"), -half - frame_t - 0.05, -0.14, 0, -half - frame_t + 0.02, 0.18, door_h + frame_t + 0.05, "MAT_Metal_Painted").name)
    fparts.append(H.box_from_corners(FP("outerR"), half + frame_t - 0.02, -0.14, 0, half + frame_t + 0.05, 0.18, door_h + frame_t + 0.05, "MAT_Metal_Painted").name)
    fparts.append(H.box_from_corners(FP("outerT"), -half - frame_t - 0.05, -0.14, door_h + frame_t - 0.02, half + frame_t + 0.05, 0.18, door_h + frame_t + 0.08, "MAT_Metal_Painted").name)
    for z in (0.35, 1.15, 2.0):
        fparts.append(H.bolt(FP(f"fb{z}"), -half - frame_t * 0.5, -0.15, z).name)
        fparts.append(H.bolt(FP(f"fbR{z}"), half + frame_t * 0.5, -0.15, z).name)
    frame = H.join_parts(f"{base}_Frame", fparts, origin_world=(0, 0, 0), col_name="COL_Interactive", bevel=True, bevel_w=0.008)

    # --- Door slab (hinge on left, origin at hinge axis ground) ---
    # Geometry in local space with hinge at x=0 (left edge of door), door extends +X
    dparts = []
    p = 0

    def DP(s):
        nonlocal p
        p += 1
        return f"_tmp_{base}_D_{p}_{s}"

    # place door with left edge at x=0 for hinge origin; world will shift
    # We'll build door from x=0 to door_w, then set origin to hinge
    dparts.append(H.box_from_corners(DP("body"), 0, -door_t * 0.5, 0.08, door_w, door_t * 0.5, door_h, "MAT_Metal_Painted").name)
    # recessed central panel
    dparts.append(
        H.box_from_corners(
            DP("recess"),
            0.15,
            -door_t * 0.5 - 0.02,
            0.35,
            door_w - 0.15,
            -door_t * 0.5 + 0.01,
            door_h - 0.35,
            "MAT_Metal_Dark",
        ).name
    )
    # outer step border on front
    dparts.append(
        H.box_from_corners(DP("border"), 0.08, door_t * 0.5 - 0.01, 0.15, door_w - 0.08, door_t * 0.5 + 0.03, door_h - 0.1, "MAT_Metal_Dark").name
    )
    # structural step transition mid
    dparts.append(
        H.box_from_corners(DP("midband"), 0.1, -door_t * 0.5 - 0.01, door_h * 0.5 - 0.06, door_w - 0.1, door_t * 0.5 + 0.02, door_h * 0.5 + 0.06, "MAT_Metal_Rusted").name
    )
    # locking bars (visual on door)
    for z in (0.6, 1.15, 1.7):
        dparts.append(
            H.box_from_corners(DP(f"bar{z}"), 0.2, door_t * 0.5, z - 0.03, door_w - 0.05, door_t * 0.5 + 0.04, z + 0.03, "MAT_Metal_Dark").name
        )
    for bx in (0.25, door_w * 0.5, door_w - 0.25):
        for bz in (0.5, 1.8):
            dparts.append(H.bolt(DP(f"db{bx}{bz}"), bx, -door_t * 0.5 - 0.02, bz, r=0.02, h=0.03).name)

    door = H.join_parts(f"{base}_Door", dparts, origin_world=(0, 0, 0), col_name="COL_Interactive", bevel=True, bevel_w=0.008)
    # move door so hinge is at left of opening (-half)
    if door:
        door.location = (-half, 0, 0)
        H.select_only(door)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        # set origin to hinge axis (left edge of door in world after apply = -half? wait applied so verts shifted)
        # After apply with location (-half,0,0), mesh is at final place, origin still 0.
        # Re-set origin to hinge: world point (-half, 0, 0) — but after apply origin is at previous origin world 0.
        # Actually after apply location, geometry moved by -half and location zeroed... transform_apply(location=True) bakes location into mesh and zeros location.
        # So if door was built 0..door_w and we set location=(-half,0,0) then apply, mesh spans -half..-half+door_w, origin at 0.
        # We want origin at hinge (-half). Set cursor and origin.
        H.set_origin_zero(door, (-half, 0, 0))
        # After set_origin_zero, location is 0 and geometry relative to hinge at 0. But then door sits with hinge at world 0.
        # We need hinge at -half for assembly. Set location back.
        door.location = (-half, 0, 0)

    # --- Hinges (static, parented to frame conceptually separate object) ---
    hparts = []
    p = 0

    def HP(s):
        nonlocal p
        p += 1
        return f"_tmp_{base}_H_{p}_{s}"

    for i, z in enumerate((0.35, 1.15, 1.95)):
        hparts.append(
            H.box_from_corners(HP(f"leaf{i}"), -half - 0.04, -0.06, z - 0.08, -half + 0.08, 0.06, z + 0.08, "MAT_Metal_Dark").name
        )
        hparts.append(
            H.cylinder_n(HP(f"pin{i}"), 0.02, 0.18, 8, (-half, 0, z), (0, 0, 0), "MAT_Metal_Rusted").name
        )
    hinges = H.join_parts(f"{base}_Hinges", hparts, origin_world=(0, 0, 0), col_name="COL_Interactive", bevel=True, bevel_w=0.005)

    # --- Lock wheel (origin = rotation axis center of wheel) ---
    wparts = []
    p = 0

    def WP(s):
        nonlocal p
        p += 1
        return f"_tmp_{base}_W_{p}_{s}"

    # wheel at door center front, built around origin then moved
    wparts.append(H.cylinder_n(WP("rim"), 0.18, 0.04, 10, (0, 0, 0), (radians(90), 0, 0), "MAT_Metal_Dark").name)
    wparts.append(H.cylinder_n(WP("hub"), 0.05, 0.06, 8, (0, 0, 0), (radians(90), 0, 0), "MAT_Metal_Rusted").name)
    for i in range(6):
        ang = i * radians(60)
        # spoke as box along local X then rotate - approximate with thin boxes
        wparts.append(
            H.box_from_corners(WP(f"spoke{i}"), -0.02, -0.02, 0.04, 0.02, 0.02, 0.16, "MAT_Metal_Dark").name
        )
        # rotate spoke around Y via object rotation before join
        sp = bpy.data.objects.get(WP(f"spoke{i}"))
        if sp:
            sp.rotation_euler = (0, ang, 0)
            H.select_only(sp)
            bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    # handle nubs
    wparts.append(H.box_from_corners(WP("grip"), -0.03, -0.03, 0.14, 0.03, 0.03, 0.2, "MAT_Rubber_Dark").name)
    wheel = H.join_parts(f"{base}_Wheel", wparts, origin_world=(0, 0, 0), col_name="COL_Interactive", bevel=True, bevel_w=0.004)
    if wheel:
        # place on door front center; parent later
        wheel.location = (0, door_t * 0.5 + 0.05, door_h * 0.5)
        # origin already at wheel center for rotation

    # --- Lock mechanism ---
    lparts = []
    p = 0

    def LP(s):
        nonlocal p
        p += 1
        return f"_tmp_{base}_L_{p}_{s}"

    lparts.append(H.box_from_corners(LP("body"), -0.12, -0.06, -0.1, 0.12, 0.06, 0.1, "MAT_Metal_Dark").name)
    lparts.append(H.box_from_corners(LP("slot"), -0.04, 0.05, -0.04, 0.04, 0.08, 0.04, "MAT_Metal_Rusted").name)
    lock = H.join_parts(f"{base}_Lock", lparts, origin_world=(0, 0, 0), col_name="COL_Interactive", bevel=True, bevel_w=0.004)
    if lock:
        lock.location = (half - 0.15, door_t * 0.5 + 0.02, door_h * 0.5)

    # --- Handle ---
    hnd = []
    p = 0

    def GP(s):
        nonlocal p
        p += 1
        return f"_tmp_{base}_G_{p}_{s}"

    hnd.append(H.box_from_corners(GP("plate"), -0.08, -0.02, -0.12, 0.08, 0.02, 0.12, "MAT_Metal_Dark").name)
    hnd.append(H.box_from_corners(GP("bar"), -0.03, 0.02, -0.04, 0.03, 0.1, 0.04, "MAT_Metal_Painted").name)
    hnd.append(H.cylinder_n(GP("grip"), 0.03, 0.16, 8, (0, 0.12, 0), (0, radians(90), 0), "MAT_Rubber_Dark").name)
    handle = H.join_parts(f"{base}_Handle", hnd, origin_world=(0, 0, 0), col_name="COL_Interactive", bevel=True, bevel_w=0.004)
    if handle:
        handle.location = (half - 0.2, -door_t * 0.5 - 0.05, 1.0)

    # Parent empty
    H.remove_if_exists(base)
    empty = bpy.data.objects.new(base, None)
    empty.empty_display_type = "PLAIN_AXES"
    empty.empty_display_size = 0.5
    H.link_obj(empty, "COL_Interactive")
    empty.location = (0, 0, 0)

    for child in (frame, door, hinges, wheel, lock, handle):
        if child:
            child.parent = empty
            # keep world transform
            child.matrix_parent_inverse = empty.matrix_world.inverted()

    # Parent wheel/lock/handle to door so they move with door if door rotates
    if door and wheel:
        mw = wheel.matrix_world.copy()
        wheel.parent = door
        wheel.matrix_world = mw
    if door and lock:
        mw = lock.matrix_world.copy()
        lock.parent = door
        lock.matrix_world = mw
    if door and handle:
        mw = handle.matrix_world.copy()
        handle.parent = door
        handle.matrix_world = mw

    return empty


def build_collisions():
    created = []
    # walls
    created.append(H.make_collision_from_bounds("COL_SM_Bunker_Wall_4m_A", 0, 0, 0, WALL_W4, WALL_T, WALL_H).name)
    created.append(H.make_collision_from_bounds("COL_SM_Bunker_Wall_2m_A", 0, 0, 0, WALL_W2, WALL_T, WALL_H).name)
    created.append(H.make_collision_from_bounds("COL_SM_Bunker_Wall_Damaged_4m_A", 0, 0, 0, WALL_W4, WALL_T, WALL_H).name)
    created.append(H.make_collision_from_bounds("COL_SM_Bunker_Wall_Doorway_4m_A", 0, 0, 0, WALL_W4, WALL_T, WALL_H).name)
    created.append(H.make_collision_from_bounds("COL_SM_Bunker_Wall_Window_4m_A", 0, 0, 0, WALL_W4, WALL_T, WALL_H).name)
    # floors / ceilings
    created.append(H.make_collision_from_bounds("COL_SM_Bunker_Floor_4x4_A", 0, 0, -FLOOR_T, FLOOR, FLOOR, 0).name)
    created.append(H.make_collision_from_bounds("COL_SM_Bunker_Floor_Damaged_4x4_A", 0, 0, -FLOOR_T, FLOOR, FLOOR, 0).name)
    created.append(H.make_collision_from_bounds("COL_SM_Bunker_Ceiling_4x4_A", 0, 0, 0, FLOOR, FLOOR, CEIL_T).name)
    created.append(H.make_collision_from_bounds("COL_SM_Bunker_Ceiling_Damaged_4x4_A", 0, 0, 0, FLOOR, FLOOR, CEIL_T).name)
    # corridors simple outer boxes
    created.append(H.make_collision_from_bounds("COL_SM_Bunker_Corridor_Straight_4m_A", 0, 0, -FLOOR_T, 4, 4, WALL_H + CEIL_T).name)
    created.append(H.make_collision_from_bounds("COL_SM_Bunker_Corridor_Corner_A", 0, 0, -FLOOR_T, 4, 4, WALL_H + CEIL_T).name)
    created.append(H.make_collision_from_bounds("COL_SM_Bunker_Corridor_TJunction_A", 0, 0, -FLOOR_T, 4, 4, WALL_H + CEIL_T).name)
    created.append(H.make_collision_from_bounds("COL_SM_Bunker_Corridor_Cross_A", 0, 0, -FLOOR_T, 4, 4, WALL_H + CEIL_T).name)
    # pillar
    s = 0.45
    created.append(H.make_collision_from_bounds("COL_SM_Bunker_Pillar_A", -s / 2, -s / 2, 0, s / 2, s / 2, WALL_H, origin=(0, 0, 0)).name)
    # stairs rough box
    created.append(H.make_collision_from_bounds("COL_SM_Bunker_Stairs_A", -0.75, 0, 0, 0.75, 3.4, WALL_H, origin=(0, 0, 0)).name)
    # door frame
    created.append(H.make_collision_from_bounds("COL_SM_Bunker_DoorFrame_A", -0.75, -0.1, 0, 0.75, 0.1, 2.4, origin=(0, 0, 0)).name)
    # door slab
    created.append(H.make_collision_from_bounds("COL_INT_Bunker_BulkheadDoor_A_Door", 0, -0.06, 0.08, 1.3, 0.06, 2.3, origin=(0, 0, 0)).name)
    return created


def build_preview():
    """Duplicate masters into preview collection at assembly positions."""
    # clear previous preview objects
    col = bpy.data.collections.get("COL_Previews")
    if col:
        for obj in list(col.objects):
            if obj.name.startswith("PRV_"):
                H.remove_if_exists(obj.name)

    def dup(src_name, prv_name, loc, rot_z=0.0):
        src = bpy.data.objects.get(src_name)
        if not src:
            return None
        obj = src.copy()
        if src.data:
            obj.data = src.data.copy()
        obj.name = prv_name
        H.link_obj(obj, "COL_Previews")
        obj.location = loc
        obj.rotation_euler = (0, 0, radians(rot_z))
        return obj

    # Straight corridor at origin of preview block
    base = Vector((12, 0, 0))  # offset from masters at 0
    # Place masters left (x negative / around 0), preview at +X
    # Hide masters? keep masters visible at library grid
    dup("SM_Bunker_Corridor_Straight_4m_A", "PRV_Corridor_Straight", (12, 0, 0))
    dup("SM_Bunker_Corridor_Corner_A", "PRV_Corridor_Corner", (16, 0, 0))
    dup("SM_Bunker_Wall_Doorway_4m_A", "PRV_Doorway", (12, 4.0, 0), 0)
    # bulkhead: duplicate hierarchy
    src = bpy.data.objects.get("INT_Bunker_BulkheadDoor_A")
    if src:
        # deep copy empty hierarchy
        def copy_hierarchy(obj, name_prefix, loc):
            new = obj.copy()
            if obj.data:
                new.data = obj.data.copy()
            new.name = name_prefix + obj.name.replace("INT_Bunker_BulkheadDoor_A", "")
            if new.name == name_prefix:
                new.name = "PRV_Bulkhead"
            H.link_obj(new, "COL_Previews")
            for child in obj.children:
                ch = copy_hierarchy(child, "PRV_Bulkhead", loc)
                if ch:
                    ch.parent = new
                    ch.matrix_parent_inverse = new.matrix_world.inverted()
            if obj.parent is None:
                new.location = loc
            return new

        copy_hierarchy(src, "PRV_Bulkhead", (14.0, 4.15, 0))

    dup("SM_Bunker_Wall_Damaged_4m_A", "PRV_Wall_Damaged", (12, -0.3, 0), 0)
    # actually place damaged as side wall of corridor: y=0 wall
    prv = bpy.data.objects.get("PRV_Wall_Damaged")
    if prv:
        prv.location = (12, 0, 0)
        # wall module origin rear-left; corridor wall already has walls — place opposite as free-standing
        prv.location = (20, 0, 0)

    dup("SM_Bunker_Floor_Damaged_4x4_A", "PRV_Floor_Damaged", (20, 4, 0))
    dup("SM_Bunker_Pillar_A", "PRV_Pillar", (14, 2, 0))
    dup("SM_Bunker_Stairs_A", "PRV_Stairs", (20, 8, 0))
    dup("SM_Bunker_DoorFrame_A", "PRV_DoorFrame", (14, 4.0, 0))

    # Lighting
    H.remove_if_exists("PRV_KeyLight")
    light_data = bpy.data.lights.new(name="PRV_KeyLight", type="AREA")
    light_data.energy = 800
    light_data.size = 4
    light_obj = bpy.data.objects.new("PRV_KeyLight", light_data)
    H.link_obj(light_obj, "COL_Previews")
    light_obj.location = (16, 4, 6)
    light_obj.rotation_euler = (radians(50), 0, radians(20))

    H.remove_if_exists("PRV_FillLight")
    ld2 = bpy.data.lights.new(name="PRV_FillLight", type="AREA")
    ld2.energy = 250
    ld2.size = 5
    lo2 = bpy.data.objects.new("PRV_FillLight", ld2)
    H.link_obj(lo2, "COL_Previews")
    lo2.location = (10, -2, 4)

    H.remove_if_exists("PRV_Camera")
    cam_data = bpy.data.cameras.new("PRV_Camera")
    cam_data.lens = 35
    cam = bpy.data.objects.new("PRV_Camera", cam_data)
    H.link_obj(cam, "COL_Previews")
    cam.location = (8, -8, 5)
    cam.rotation_euler = (radians(65), 0, radians(-35))
    bpy.context.scene.camera = cam

    return True


def layout_masters():
    """Park master assets on a library grid at negative X so preview is clear."""
    layout = {
        "SM_Bunker_Wall_4m_A": (-20, 0, 0),
        "SM_Bunker_Wall_2m_A": (-20, 5, 0),
        "SM_Bunker_Wall_Damaged_4m_A": (-20, 10, 0),
        "SM_Bunker_Wall_Doorway_4m_A": (-20, 15, 0),
        "SM_Bunker_Wall_Window_4m_A": (-20, 20, 0),
        "SM_Bunker_Floor_4x4_A": (-28, 0, 0),
        "SM_Bunker_Floor_Damaged_4x4_A": (-28, 5, 0),
        "SM_Bunker_Ceiling_4x4_A": (-28, 10, 0),
        "SM_Bunker_Ceiling_Damaged_4x4_A": (-28, 15, 0),
        "SM_Bunker_Corridor_Straight_4m_A": (-36, 0, 0),
        "SM_Bunker_Corridor_Corner_A": (-36, 6, 0),
        "SM_Bunker_Corridor_TJunction_A": (-36, 12, 0),
        "SM_Bunker_Corridor_Cross_A": (-36, 18, 0),
        "SM_Bunker_Pillar_A": (-14, 0, 0),
        "SM_Bunker_Stairs_A": (-14, 4, 0),
        "SM_Bunker_DoorFrame_A": (-14, 10, 0),
        "INT_Bunker_BulkheadDoor_A": (-14, 14, 0),
    }
    for name, loc in layout.items():
        obj = bpy.data.objects.get(name)
        if obj:
            obj.location = loc


def validate():
    report = {"assets": {}, "smooth_issues": [], "missing": []}
    names = [
        "SM_Bunker_Wall_4m_A",
        "SM_Bunker_Wall_2m_A",
        "SM_Bunker_Wall_Damaged_4m_A",
        "SM_Bunker_Wall_Doorway_4m_A",
        "SM_Bunker_Wall_Window_4m_A",
        "SM_Bunker_Floor_4x4_A",
        "SM_Bunker_Floor_Damaged_4x4_A",
        "SM_Bunker_Ceiling_4x4_A",
        "SM_Bunker_Ceiling_Damaged_4x4_A",
        "SM_Bunker_Corridor_Straight_4m_A",
        "SM_Bunker_Corridor_Corner_A",
        "SM_Bunker_Corridor_TJunction_A",
        "SM_Bunker_Corridor_Cross_A",
        "SM_Bunker_Pillar_A",
        "SM_Bunker_Stairs_A",
        "SM_Bunker_DoorFrame_A",
        "INT_Bunker_BulkheadDoor_A",
        "INT_Bunker_BulkheadDoor_A_Frame",
        "INT_Bunker_BulkheadDoor_A_Door",
        "INT_Bunker_BulkheadDoor_A_Hinges",
        "INT_Bunker_BulkheadDoor_A_Wheel",
        "INT_Bunker_BulkheadDoor_A_Lock",
        "INT_Bunker_BulkheadDoor_A_Handle",
    ]
    for n in names:
        obj = bpy.data.objects.get(n)
        if not obj:
            report["missing"].append(n)
            continue
        tris = H.tri_count(obj) if obj.type == "MESH" else 0
        if obj.type == "MESH":
            smooth = sum(1 for p in obj.data.polygons if p.use_smooth)
            if smooth:
                report["smooth_issues"].append(n)
            # ensure flat
            H.flat_shade(obj)
        report["assets"][n] = {
            "tris": tris,
            "dims": H.dims(obj) if obj.type == "MESH" else None,
            "loc": [round(c, 3) for c in obj.location],
            "type": obj.type,
        }
    return report


def save_blend(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=path)
    return path


def main(phase="all"):
    out = {"phase": phase}
    if phase in ("all", "setup"):
        out["materials_created"] = setup()
    if phase in ("all", "walls"):
        out["walls"] = []
        for fn, args in [
            (build_wall, ("SM_Bunker_Wall_4m_A", WALL_W4)),
            (build_wall, ("SM_Bunker_Wall_2m_A", WALL_W2)),
            (build_wall, ("SM_Bunker_Wall_Damaged_4m_A", WALL_W4, True)),
            (build_wall, ("SM_Bunker_Wall_Doorway_4m_A", WALL_W4, False, True)),
            (build_wall, ("SM_Bunker_Wall_Window_4m_A", WALL_W4, False, False, True)),
        ]:
            # fix call signatures
            pass
        build_wall("SM_Bunker_Wall_4m_A", WALL_W4)
        build_wall("SM_Bunker_Wall_2m_A", WALL_W2)
        build_wall("SM_Bunker_Wall_Damaged_4m_A", WALL_W4, damaged=True)
        build_wall("SM_Bunker_Wall_Doorway_4m_A", WALL_W4, doorway=True)
        build_wall("SM_Bunker_Wall_Window_4m_A", WALL_W4, window=True)
        out["walls"] = "ok"
    if phase in ("all", "floors"):
        build_floor("SM_Bunker_Floor_4x4_A")
        build_floor("SM_Bunker_Floor_Damaged_4x4_A", damaged=True)
        build_ceiling("SM_Bunker_Ceiling_4x4_A")
        build_ceiling("SM_Bunker_Ceiling_Damaged_4x4_A", damaged=True)
        out["floors"] = "ok"
    if phase in ("all", "corridors"):
        build_corridor_straight("SM_Bunker_Corridor_Straight_4m_A")
        build_corridor_corner("SM_Bunker_Corridor_Corner_A")
        build_corridor_t("SM_Bunker_Corridor_TJunction_A")
        build_corridor_cross("SM_Bunker_Corridor_Cross_A")
        out["corridors"] = "ok"
    if phase in ("all", "props"):
        build_pillar("SM_Bunker_Pillar_A")
        build_stairs("SM_Bunker_Stairs_A")
        build_door_frame("SM_Bunker_DoorFrame_A")
        build_bulkhead_door()
        out["props"] = "ok"
    if phase in ("all", "collision"):
        out["collision"] = build_collisions()
    if phase in ("all", "preview"):
        layout_masters()
        build_preview()
        out["preview"] = "ok"
    if phase in ("all", "validate"):
        out["validate"] = validate()
    return out


if __name__ == "__main__":
    print(main("all"))
