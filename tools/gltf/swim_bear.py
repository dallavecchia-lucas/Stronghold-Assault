"""The Bear Rifleman's swimming clips: Swim (at the surface) and Dive (under it), baked into its armed model
(the output of tools/gltf/arm_rifle.py) beside Idle and Running. No Blender: numpy on the glTF itself, like
arm_rifle.py, whose rig and pose helpers it uses.

A bear swims like a dog: body low and leaning well forward, the head held up out of the water, the fore paws
paddling by turns (each reaching forward near the surface, pulling down and back under the chest, coming
round and forward again close in), the hind legs kicking by turns behind it. Swimming, the LMG is slung across
the backpack (the `rifle` marker bone keyed there, in the chest's frame, so the gun rides the back).

  Swim  the surface stroke: the torso SWIM_PITCH from upright, the neck and head craned back up so the snout
        is level, out of the water at the game's swim depth (UnitTypes swim_sink, SWIM_WATER here).
  Dive  under water: the body near level (DIVE_PITCH), the head in line with it, longer, stronger strokes.

Both loop (the last frame a copy of the first, as the game expects of baked loops).

  python3 tools/gltf/swim_bear.py --input game/assets/units/cyber_bear_commando/cyber_bear_commando_armed.glb \\
      --gun game/assets/weapons/prototype_c_lmg/prototype_c_lmg.glb \\
      --output game/assets/units/cyber_bear_commando/cyber_bear_commando_armed.glb [--preview out.png]

Run again on its own output it replaces the clips it baked before.
"""
import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gltf_io import accessor, add_accessor, compact, mat_to_quat, read_glb, rotation, translation, write_glb  # noqa: E402
from rig_infiltrator import Pose, Rig, X, Y, Z, frame_from, place_chain, two_bone, unit  # noqa: E402
import rig_infiltrator  # noqa: E402

FPS = 30.0
P = "mixamorig:"
CHEST = P + "Spine2"
SIDES = {"L": "Left", "R": "Right"}

# The water line in the clips' frame (m over the unit's origin): the game's swim_sink for the bear.
SWIM_WATER = 0.72
# Clip by clip: its length (s), the torso's lean from upright (deg), where the hips are (m over the origin),
# the neck's and the head's turn back up (deg), the paw circle's centre (m from the shoulder: out, up, ahead)
# and radii (ahead and down), the hips' kick (deg: mean and swing), the knees' bend (deg: least and most),
# and the roll with the strokes (deg).
CLIPS = {
    "Swim": {"length": 1.1, "pitch": 55.0, "hips": 0.42, "neck": -44.0, "head": -22.0,
             "paw": (0.1, -0.3, 0.22), "paw_r": (0.26, 0.17), "kick": (-12.0, 22.0), "knee": (15.0, 70.0), "roll": 6.0},
    "Dive": {"length": 1.4, "pitch": 84.0, "hips": 0.32, "neck": -20.0, "head": -10.0,
             "paw": (0.12, -0.3, 0.16), "paw_r": (0.3, 0.2), "kick": (-8.0, 26.0), "knee": (12.0, 65.0), "roll": 4.0},
}
# Elbows (model space) out to the side, back and a little up as the paws paddle.
POLE = {"L": unit(X * 0.85 - Z * 0.45 + Y * 0.25), "R": unit(-X * 0.85 - Z * 0.45 + Y * 0.25)}
# The slung gun: its middle this far out behind the backpack's back face, its muzzle up over the left shoulder
# (SLING_TILT from straight up), its top facing out away from the back.
SLING_OUT = 0.05
SLING_TILT = math.radians(38.0)


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--gun", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--preview", default="")
    return p.parse_args()


def bone(side, part):
    return P + SIDES[side] + part


def gun_markers(path):
    from gltf_io import trs
    js, _ = read_glb(path)
    return {n["name"]: trs(n)[:3, 3].copy() for n in js["nodes"] if n.get("name") in ("muzzle", "butt")}


class Swimmer:
    def __init__(self, rig, pts, marks):
        self.rig = rig
        self.marks = marks
        self.len = {}
        for s in "LR":
            up, lo, ha = bone(s, "Arm"), bone(s, "ForeArm"), bone(s, "Hand")
            self.len[s] = (np.linalg.norm(rig.rest(lo)[:3, 3] - rig.rest(up)[:3, 3]),
                           np.linalg.norm(rig.rest(ha)[:3, 3] - rig.rest(lo)[:3, 3]))
        # The backpack's back face (rest pose, model space z) at the chest's height.
        chest_y = rig.rest(CHEST)[1, 3]
        band = pts[(np.abs(pts[:, 1] - chest_y) < 0.15) & (np.abs(pts[:, 0]) < 0.15)]
        self.back_z = float(band[:, 2].min())

    def pose(self, pose, c, u):
        """The pose at phase u (0..1) of clip settings c."""
        rig = self.rig
        pose.reset()
        w = 2 * math.pi * u
        # Body: lean forward, roll with the strokes (toward the paw pulling), bob with each.
        rest = rig.rest(P + "Hips")
        lean = rig_infiltrator.axis_angle(Z, math.radians(c["roll"]) * math.sin(w)) \
            @ rig_infiltrator.axis_angle(X, math.radians(c["pitch"] + 2.0 * math.sin(2 * w)))
        hips = rest.copy()
        hips[:3, :3] = lean @ rest[:3, :3]
        hips[1, 3] = c["hips"] + 0.025 * math.sin(2 * w + 0.6)
        pose.place(P + "Hips", hips)
        # The back undulates a little; the neck and the head crane up, steady against the roll and bob.
        for k, b in enumerate(("Spine", "Spine1", "Spine2")):
            pose.turn(P + b, X, math.radians(-3.0 + 2.0 * math.sin(2 * w - 0.5 * k)))
        pose.turn(P + "Neck", X, math.radians(c["neck"] - 2.0 * math.sin(2 * w)))
        pose.turn(P + "Neck", Z, -math.radians(c["roll"]) * 0.6 * math.sin(w))
        pose.turn(P + "Head", X, math.radians(c["head"]))
        pose.turn(P + "Head", Z, -math.radians(c["roll"]) * 0.4 * math.sin(w))
        # Fore paws: round by turns, forward at the top, down at the front, back at the bottom (the pull),
        # up at the back (model space, from the shoulder).
        for s, phase in (("L", 0.0), ("R", math.pi)):
            side = 1.0 if s == "L" else -1.0
            a = w + phase
            up, lo = bone(s, "Arm"), bone(s, "ForeArm")
            sh = pose.head(up)
            cx, cy, cz = c["paw"]
            rz, ry = c["paw_r"]
            # In close under the chest on the pull, out a little on the reach.
            out = cx + 0.05 * math.cos(a)
            target = sh + np.array([side * out, cy - ry * math.sin(a), cz + rz * math.cos(a)])
            l1, l2 = self.len[s]
            elbow, end = two_bone(sh, l1, l2, target, POLE[s])
            place_chain(pose, up, lo, sh, elbow, end, POLE[s])
            # The paw cupped against the water on the pull, turning edge-on to come round.
            pose.turn(bone(s, "Hand"), X, math.radians(20.0 + 25.0 * math.sin(a)))
        # Hind legs: kicking by turns, the knees bending as the thighs come forward, the feet pointed.
        for s, phase in (("L", math.pi * 0.5), ("R", math.pi * 1.5)):
            a = w + phase
            mean, swing = c["kick"]
            pose.turn(bone(s, "UpLeg"), X, math.radians(mean + swing * math.sin(a)))
            lo_k, hi_k = c["knee"]
            pose.turn(bone(s, "Leg"), X, math.radians(lo_k + (hi_k - lo_k) * 0.5 * (1 + math.sin(a + 1.2))))
            pose.turn(bone(s, "Foot"), X, math.radians(45.0))

    def sling(self, pose):
        """The gun slung across the backpack, in the chest's frame (the rifle bone's local matrix)."""
        chest = pose.world(CHEST)
        s = np.linalg.norm(chest[:3, :3], axis=0).mean()
        rc = chest[:3, :3] / s
        rest_chest = self.rig.rest(CHEST)
        # The back face's middle, in the chest's frame, then out from it.
        back_local = np.linalg.inv(rest_chest) @ np.array([0.02, rest_chest[1, 3] - 0.02, self.back_z - SLING_OUT, 1.0])
        back = (chest @ back_local)[:3]
        muzzle_dir = rc @ unit(X * math.sin(SLING_TILT) + Y * math.cos(SLING_TILT))
        top = rc @ -Z
        rot = frame_from(Z, Y, muzzle_dir, top)
        mid = (self.marks["muzzle"] + self.marks["butt"]) * 0.5
        gun = translation(back - rot @ mid * s) @ rotation(rot * s)
        local = np.linalg.inv(chest) @ gun
        local[:3, :3] /= np.linalg.norm(local[:3, :3], axis=0)
        return local


def bake(js, binary, rig, swimmer, name, c):
    """Keys every joint of the skin (rotation, translation and scale: the clip leaves nothing to the one it
    blends from) and the gun's bone."""
    n = int(round(c["length"] * FPS)) + 1
    pose = Pose(rig)
    joints = [rig.nodes[j]["name"] for j in js["skins"][0]["joints"]]
    keys = {b: [] for b in joints if b != "rifle"}
    gun = []
    for f in range(n):
        u = (f % (n - 1)) / (n - 1)
        swimmer.pose(pose, c, u)
        for b in keys:
            keys[b].append(pose.local(b))
        gun.append(swimmer.sling(pose))
    times = np.arange(n, dtype=np.float32) / FPS
    tin = add_accessor(js, binary, times, "SCALAR", with_bounds=True)
    anim = {"name": name, "channels": [], "samplers": []}

    def channel(node, path, data, kind):
        anim["samplers"].append({"input": tin, "output": add_accessor(js, binary, np.array(data, dtype=np.float32), kind),
                                 "interpolation": "LINEAR"})
        anim["channels"].append({"sampler": len(anim["samplers"]) - 1, "target": {"node": node, "path": path}})

    for b, mats in list(keys.items()) + [("rifle", gun)]:
        quats = []
        prev = None
        for m in mats:
            q = mat_to_quat(m[:3, :3] / np.linalg.norm(m[:3, :3], axis=0))
            if prev is not None and np.dot(q, prev) < 0:
                q = -q
            quats.append(q)
            prev = q
        node = rig.index[b]
        channel(node, "rotation", quats, "VEC4")
        channel(node, "translation", [m[:3, 3] for m in mats], "VEC3")
        channel(node, "scale", [np.linalg.norm(m[:3, :3], axis=0) for m in mats], "VEC3")
    js["animations"].append(anim)
    return n


def main():
    args = parse_args()
    js, binary = read_glb(args.input)
    js["animations"] = [a for a in js["animations"] if a["name"] not in CLIPS]
    rig = Rig(js)
    pts = rig_infiltrator.skinned_vertices(js, binary)
    pts = pts[0] if isinstance(pts, tuple) else pts
    swimmer = Swimmer(rig, pts, gun_markers(args.gun))
    for name, c in CLIPS.items():
        n = bake(js, binary, rig, swimmer, name, c)
        print(f"{name}: {n} frames ({c['length']} s)")
        pose = Pose(rig)
        swimmer.pose(pose, c, 0.0)
        hy = {k: round(float(pose.head(P + k)[1]), 2) for k in ("Hips", "Spine2", "LeftArm", "Neck", "Head", "HeadTop_End")}
        face = pose.world("headfront")[:3, 1]
        print("   heights", hy, "snout", round(float(pose.head("headfront")[1]), 2), "z", round(float(pose.head("headfront")[2]), 2),
              "face", np.round(face / np.linalg.norm(face), 2))
    binary = compact(js, binary)
    js.setdefault("asset", {})["generator"] = "tools/gltf/arm_rifle.py, tools/gltf/swim_bear.py"
    write_glb(args.output, js, binary)
    print(f"wrote {args.output}")
    if args.preview:
        render_preview(args.output, args.gun, args.preview)


# ---------------------------------------------------------------- preview

def render_preview(path, gun_path, out):
    """Side, front, three-quarter and from-above views of frames of each swimming clip, the water drawn at
    SWIM_WATER (Swim) and well over the Dive's head, the gun on its bone."""
    from PIL import Image, ImageDraw
    from arm_rifle import posed, sample_clip
    from rig_infiltrator import rasterize
    from rig_sniper import load_textured, rifle_mesh
    js, binary = read_glb(path)
    rig = Rig(js)
    node = next(n for n in js["nodes"] if "skin" in n)
    tex = load_textured(js, binary, js["meshes"][node["mesh"]]["primitives"][0])
    gpts, gidx, guv, gtex = rifle_mesh(gun_path)
    anims = {a["name"]: a for a in js["animations"]}
    shots = [("Swim", 0), ("Swim", 8), ("Swim", 16), ("Swim", 24), ("Dive", 0), ("Dive", 21)]
    # From its left side, from in front, from its front left and above, from behind and its right, from above.
    views = [np.array([4.2, 0.35, 0.0]), np.array([0.4, 0.55, 4.0]), np.array([2.6, 1.8, 2.6]), np.array([-2.4, 1.4, -2.6]),
             np.array([0.01, 4.2, 0.4])]
    W, H = 320, 260
    sheet = Image.new("RGB", (W * len(views), H * len(shots)))
    water_tex = np.ones((2, 2, 3), np.float32) * np.array([0.22, 0.36, 0.42], np.float32)
    # A 3 m square of water in 0.25 m cells (the rasterizer drops triangles that reach behind the eye).
    g = np.linspace(-1.5, 1.5, 13)
    gx, gz = np.meshgrid(g, g)
    grid = np.stack([gx.ravel(), np.zeros(gx.size), gz.ravel() + 0.3], 1)
    qidx = []
    for i in range(12):
        for j in range(12):
            a = i * 13 + j
            qidx += [[a, a + 1, a + 14], [a, a + 14, a + 13]]
    qidx = np.array(qidx)
    quv = np.zeros((len(grid), 2))
    sampled = {}
    for r, (clip, f) in enumerate(shots):
        if clip not in sampled:
            sampled[clip] = sample_clip(js, binary, anims[clip])[0]
        bpts, idx, uv, gm = posed(js, binary, rig, sampled[clip], f)
        gp = gpts @ gm[:3, :3].T + gm[:3, 3]
        quad = grid + np.array([0.0, SWIM_WATER, 0.0])
        for cidx, e in enumerate(views):
            img = np.ones((H, W, 3), np.float32) * np.array([0.6, 0.7, 0.8], np.float32)
            zb = np.full((H, W), np.inf, np.float32)
            target = np.array([0.0, 0.62, 0.3])
            eye = target + e
            rasterize(img, zb, bpts, idx, uv, tex, eye, target)
            rasterize(img, zb, gp, gidx, guv, gtex, eye, target)
            if clip == "Swim" and cidx < 4:
                rasterize(img, zb, quad, qidx, quv, water_tex, eye, target)
            pil = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
            ImageDraw.Draw(pil).text((4, 4), f"{clip} {f}", fill=(0, 0, 0))
            sheet.paste(pil, (cidx * W, r * H))
    sheet.save(out)
    print(f"preview {out}")


if __name__ == "__main__":
    main()
