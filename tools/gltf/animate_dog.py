"""Bake the Wolf Medic's Dig clip. No Blender: numpy on the glTF itself, like rig_infiltrator.py (whose rig,
pose and IK helpers it uses).

Input: the processed Meshy auto-rig of the Wolf Medic (game/assets/units/battlefield_lifesaver/
battlefield_lifesaver_rigged.glb: 1.4 m to the ear tips, origin between the paws, front +Z, Meshy's Walk
and a held Idle). Its rig is good enough for this: Hips (the body, the root), chest, head, each leg in four
(fore: frontleg the upper arm from the shoulder, frontleg0 the forearm from the elbow, frontleg1 the
pastern from the wrist, frontleg2 the paw; hind: backleg the thigh, backleg0 the shin from the stifle,
backleg1 the hind foot from the hock, backleg2 the paw; `R_` on the right) and the tail in five. The mesh,
the bones and the clips already in it stay as they are; this adds (or replaces) one clip:

  Dig   (looped, DIG_PERIOD long, the last key repeating the first, which the game drops) digging a mine
        out: the hind legs planted wide, the rump up and the front end down (the body pitched BODY_PITCH
        about the hips, the chest a further CHEST_PITCH), the head low over the hole, nodding with each
        stroke; the fore paws scrape in turn, STROKES strokes each a loop, half a stroke apart: each comes
        down at the front of the hole, drags back through the dirt under the chest, claws raking, curls
        up and swings forward again high (the wrist placed by IK, the elbow bending back). The chest rolls
        a little onto the leg that is down, and the tail is held up, wagging.

The game plays it while the dog disarms a mine (AttackerUnit, UnitTypes anim_dig) and throws the dirt from
under the chest as each paw finishes its drag: DRAG_END of the way through its stroke, the left paw's
strokes starting at 0, the right's half a stroke later: four times a loop, the first 0.025 of the way in
(UnitTypes dig_sprays, dig_spray_at).

  python3 tools/gltf/animate_dog.py \\
      --input game/assets/units/battlefield_lifesaver/battlefield_lifesaver_rigged.glb \\
      --output game/assets/units/battlefield_lifesaver/battlefield_lifesaver_rigged.glb [--preview DIR]

--preview renders frames of the clip from the side, the front and behind into DIR (rig_infiltrator's plain
numpy rasterizer).
"""
import argparse
import io
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gltf_io import add_accessor, axis_angle, compact, mat_to_quat, read_glb, rotation, translation, write_glb  # noqa: E402
from rig_infiltrator import X, Y, Z, Pose, Rig, aim_frame, place_chain, rasterize, skinned_vertices, two_bone, unit  # noqa: E402

FPS = 30
DIG_PERIOD = 1.0  # seconds a loop
STROKES = 2  # strokes of each fore paw a loop
BODY_PITCH = math.radians(14.0)  # the body tipping forward about the hips (nose down)
CHEST_PITCH = math.radians(9.0)  # the chest on top of it
HIPS_DROP = 0.02  # the hips sinking a little as the hind legs brace (m)
HEAD_PITCH = math.radians(38.0)  # the head down over the hole
NOD = math.radians(5.0)  # the head nodding with each stroke
ROLL = math.radians(3.5)  # the chest rolling onto the fore leg that is down
TAIL_LIFT = math.radians(28.0)
WAG = math.radians(16.0)
WAG_RATE = 2.0  # wags a loop
# The wrist's path through a stroke, in model space (m: y up, z ahead) beside each shoulder: it lands at
# REACH, drags back along the ground to DRAG_TO, lifts and swings forward over APEX back to REACH. Of the
# stroke: LAND (on the ground), DRAG_END (the drag done: the dirt flies), the rest the swing.
REACH = np.array([0.0, 0.15, 0.80])
DRAG_TO = np.array([0.0, 0.12, 0.22])
APEX = np.array([0.0, 0.40, 0.48])
LAND = 0.12
DRAG_END = 0.55
PAW_SPREAD = 0.02  # the wrists a little wider than at rest (m, each side)
# The pastern's direction through the stroke (model space, from the wrist down to the paw): reaching
# forward as it lands, raking back through the drag, folded back under the wrist in the swing.
PASTERN_REACH = np.array([0.0, -1.0, 0.55])
PASTERN_RAKE = np.array([0.0, -1.0, -0.45])
PASTERN_FOLD = np.array([0.0, -0.35, -1.0])

FORE = {"L": ("frontleg", "frontleg0", "frontleg1", "frontleg2"), "R": ("R_frontleg", "R_frontleg0", "R_frontleg1", "R_frontleg2")}
HIND = {"L": ("backleg", "backleg0", "backleg1", "backleg2"), "R": ("R_backleg", "R_backleg0", "R_backleg1", "R_backleg2")}
TAIL = ("tail", "tailstart", "tail1", "tail2", "tail3")


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--preview", default="")
    return p.parse_args()


def smoothstep(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def bezier(p0, p1, p2, u):
    return (1 - u) * (1 - u) * p0 + 2 * (1 - u) * u * p1 + u * u * p2


class Digger:
    def __init__(self, rig):
        self.rig = rig
        self.pose = Pose(rig)
        self.names = [n["name"] for i, n in enumerate(rig.nodes) if i in set(rig.js["skins"][0]["joints"])]
        rest = Pose(rig)
        self.rest = {n: rest.world(n).copy() for n in self.names}
        # Each fore leg: its two IK lengths (shoulder to elbow, elbow to wrist) and where its wrist is.
        self.fore = {}
        for s, (upper, lower, pastern, _paw) in FORE.items():
            a, b, c = rest.head(upper), rest.head(lower), rest.head(pastern)
            self.fore[s] = {"l": (np.linalg.norm(b - a), np.linalg.norm(c - b)), "wrist": c}
        self.hind = {}
        for s, (thigh, shin, foot, _paw) in HIND.items():
            a, b, c = rest.head(thigh), rest.head(shin), rest.head(foot)
            # The stifle bends forward and out, as it does at rest.
            self.hind[s] = {"l": (np.linalg.norm(b - a), np.linalg.norm(c - b)), "hock": c,
                            "pole": unit(b - (a + c) * 0.5)}

    def frame(self, t):
        """The pose `t` seconds into the loop: every bone's local matrix."""
        pose = self.pose
        pose.reset()
        # The body: tipped forward about the hips, sunk a little, the chest further down.
        pose.place("Hips", translation([0.0, -HIPS_DROP, 0.0]) @ self._turned("Hips", X, BODY_PITCH))
        stroke = (t / DIG_PERIOD * STROKES) % 1.0
        # The leg that is down carries the chest: it rolls over onto it.
        down = 1.0 if self._on_ground(stroke) else -1.0 if self._on_ground((stroke + 0.5) % 1.0) else 0.0
        pose.turn("chest", X, CHEST_PITCH)
        pose.turn("chest", Z, -ROLL * down * 0.5)
        # The head low over the hole, nodding with each stroke (both paws: twice a stroke).
        pose.turn("head", X, HEAD_PITCH + NOD * math.sin(2 * math.pi * stroke * 2))
        for s, phase in (("L", 0.0), ("R", 0.5)):
            self._fore_leg(s, (stroke + phase) % 1.0)
            self._hind_leg(s)
        # The tail up and wagging.
        wag = math.sin(2 * math.pi * t / DIG_PERIOD * WAG_RATE)
        pose.turn("tailstart", X, TAIL_LIFT)
        for k, bone in enumerate(TAIL[1:]):
            pose.turn(bone, Y, WAG * wag * (0.45 + 0.2 * k))
        return {n: pose.local(n) for n in self.names}

    def _turned(self, name, axis, angle):
        """The bone's rest matrix in model space turned about a model axis at its head."""
        m = self.rig.rest(name).copy()
        r = np.eye(4)
        r[:3, :3] = axis_angle(axis, angle)
        head = m[:3, 3].copy()
        return translation(head) @ r @ translation(-head) @ m

    @staticmethod
    def _on_ground(u):
        return LAND <= u < DRAG_END

    def _wrist_path(self, u):
        """Where the wrist is `u` of the way through a stroke (beside the shoulder: x left out)."""
        if u < LAND:
            # Coming down onto the front of the hole.
            return bezier(APEX + (REACH - APEX) * 0.6 + np.array([0.0, 0.06, 0.08]), REACH + np.array([0.0, 0.05, 0.02]), REACH, smoothstep(u / LAND))
        if u < DRAG_END:
            # The drag: back through the dirt, pressing down a little in the middle of it.
            w = smoothstep((u - LAND) / (DRAG_END - LAND))
            return REACH + (DRAG_TO - REACH) * w - np.array([0.0, 0.025 * math.sin(math.pi * w), 0.0])
        # The swing: up off the ground, curled, and forward over the apex.
        w = (u - DRAG_END) / (1.0 - DRAG_END)
        start = APEX + (REACH - APEX) * 0.6 + np.array([0.0, 0.06, 0.08])
        return bezier(DRAG_TO, APEX + np.array([0.0, 0.08, -0.12]), start, smoothstep(w))

    def _pastern_dir(self, u):
        if u < LAND:
            return unit(PASTERN_FOLD + (PASTERN_REACH - PASTERN_FOLD) * smoothstep(u / LAND))
        if u < DRAG_END:
            return unit(PASTERN_REACH + (PASTERN_RAKE - PASTERN_REACH) * smoothstep((u - LAND) / (DRAG_END - LAND)))
        w = (u - DRAG_END) / (1.0 - DRAG_END)
        return unit(PASTERN_RAKE + (PASTERN_FOLD - PASTERN_RAKE) * smoothstep(w * 2.5))

    def _fore_leg(self, side, u):
        pose = self.pose
        upper, lower, pastern, paw = FORE[side]
        info = self.fore[side]
        out = math.copysign(1.0, info["wrist"][0])
        wrist = self._wrist_path(u) + np.array([info["wrist"][0] + out * PAW_SPREAD, 0.0, 0.0])
        shoulder = pose.head(upper)
        # The elbow bends back (and a little out), as a dog's does.
        pole = unit(np.array([out * 0.15, 0.25, -1.0]))
        elbow, end = two_bone(shoulder, info["l"][0], info["l"][1], wrist, pole)
        place_chain(pose, upper, lower, shoulder, elbow, end, pole)
        d = self._pastern_dir(u)
        self._aim(pastern, d, pole)
        # The paw carries on the pastern's line, curling further in the swing.
        curl = 0.0 if self._on_ground(u) else 0.55
        self._aim(paw, unit(d + np.array([0.0, 0.0, 0.55]) - np.array([0.0, curl, curl * 1.6])), pole)

    def _hind_leg(self, side):
        """The hind paw stays planted where it stands at rest: the hock back on its rest spot (IK on the
        thigh and shin), the foot and paw as they lie at rest."""
        pose = self.pose
        thigh, shin, foot, paw = HIND[side]
        info = self.hind[side]
        hip = pose.head(thigh)
        stifle, end = two_bone(hip, info["l"][0], info["l"][1], info["hock"], info["pole"])
        place_chain(pose, thigh, shin, hip, stifle, end, info["pole"])
        pose.place(foot, self.rest[foot])
        pose.place(paw, self.rest[paw])

    def _aim(self, name, direction, pole):
        """Points the bone (its Y axis) along a model-space direction, twisted toward pole as at rest."""
        pose = self.pose
        r = self.rig.rest(name)[:3, :3]
        head = pose.head(name)
        q = aim_frame(direction, pole) @ aim_frame(unit(r @ Y), pole).T
        pose.place(name, translation(head) @ rotation(q @ r))


def write_clip(js, binary, name, keys, names, root):
    """Every bone's rotation and the root's translation, one key a frame; replaces a clip of that name."""
    js["animations"] = [a for a in js.get("animations", []) if a.get("name") != name]
    idx = {n["name"]: i for i, n in enumerate(js["nodes"]) if "name" in n}
    times = np.arange(len(keys), dtype=np.float32) / FPS
    tin = add_accessor(js, binary, times, "SCALAR", with_bounds=True)
    anim = {"name": name, "channels": [], "samplers": []}
    for bone in names:
        quats = []
        prev = None
        for k in keys:
            m = k[bone][:3, :3]
            q = mat_to_quat(m / np.linalg.norm(m, axis=0))
            if prev is not None and np.dot(q, prev) < 0:
                q = -q  # the short way round
            quats.append(q)
            prev = q
        out = add_accessor(js, binary, np.array(quats), "VEC4")
        anim["samplers"].append({"input": tin, "output": out, "interpolation": "LINEAR"})
        anim["channels"].append({"sampler": len(anim["samplers"]) - 1, "target": {"node": idx[bone], "path": "rotation"}})
        if bone == root:
            out = add_accessor(js, binary, np.array([k[bone][:3, 3] for k in keys]), "VEC3")
            anim["samplers"].append({"input": tin, "output": out, "interpolation": "LINEAR"})
            anim["channels"].append({"sampler": len(anim["samplers"]) - 1, "target": {"node": idx[bone], "path": "translation"}})
    js["animations"].append(anim)


def main():
    args = parse_args()
    js, binary = read_glb(args.input)
    rig = Rig(js)
    digger = Digger(rig)
    for s, i in sorted(digger.fore.items()):
        print(f"fore leg {s}: {i['l'][0]:.3f} + {i['l'][1]:.3f} m")
    frames = int(round(DIG_PERIOD * FPS))
    keys = [digger.frame(f / FPS) for f in range(frames)]
    keys.append(keys[0])  # the loop's last key repeats its first (the game drops it)
    write_clip(js, binary, "Dig", keys, digger.names, "Hips")
    binary = compact(js, binary)
    write_glb(args.output, js, binary)
    print(f"wrote {args.output}: clips {[a['name'] for a in js['animations']]}")
    if args.preview:
        render_preview(args.output, args.preview)


def render_preview(path, out_dir):
    from PIL import Image, ImageDraw
    os.makedirs(out_dir, exist_ok=True)
    js, binary = read_glb(path)
    mat = js["materials"][0]
    im = js["images"][js["textures"][mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]]["source"]]
    view = js["bufferViews"][im["bufferView"]]
    data = bytes(binary[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]])
    tex = np.asarray(Image.open(io.BytesIO(data)).convert("RGB").resize((512, 512)), dtype=np.float32) / 255.0
    views = {"side": (np.array([3.6, 0.8, 0.2]), np.array([0.0, 0.5, 0.15])),
             "front": (np.array([1.4, 0.9, 3.2]), np.array([0.0, 0.4, 0.3])),
             "back": (np.array([-1.3, 1.6, -2.8]), np.array([0.0, 0.5, 0.2]))}
    for clip, frames in ((None, [0]), ("Dig", [0, 4, 8, 12])):
        row = []
        for f in frames:
            pts, idx, uv, _markers, _bow = skinned_vertices(js, binary, clip, f)
            for vname, (eye, target) in views.items():
                img = np.ones((260, 300, 3), np.float32) * np.array([0.55, 0.65, 0.75], np.float32)
                zb = np.full((260, 300), np.inf, np.float32)
                rasterize(img, zb, pts, idx, uv, tex, eye, target)
                pil = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
                ImageDraw.Draw(pil).text((4, 4), f"{clip or 'rest'} {f} {vname}", fill=(0, 0, 0))
                row.append(pil)
        sheet = Image.new("RGB", (300 * 3, 260 * len(frames)))
        for k, p in enumerate(row):
            sheet.paste(p, (300 * (k % 3), 260 * (k // 3)))
        sheet.save(os.path.join(out_dir, f"{clip or 'rest'}.png"))
    print(f"preview in {out_dir}")


if __name__ == "__main__":
    main()
