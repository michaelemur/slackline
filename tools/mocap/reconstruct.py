#!/usr/bin/env python3.12
"""Step 3: landmarks -> motion reference (joint angles, body rotation, phases).

Works in the sagittal plane (side-on video): the camera may pan/handhold, so
nothing depends on absolute image position. Phases are found from the body
itself:
  takeoff  = legs fully extended just before the rotation starts
  landing  = rotation complete and stopped (feet back under the body)

Manual correction: an optional JSON with overrides, e.g.
  {"takeoff": 31, "landing": 55, "drop": [[40, 42]], "facing": -1}
("drop" ranges are re-interpolated from their neighbours.)

Output: motion reference JSON for the game (+ a validation report when a
ground-truth file is given).
Usage: python3.12 reconstruct.py pose.json motion.json [--fix fix.json] [--truth truth.json]
"""
import json, math, sys
import numpy as np

NOSE, L_EAR, R_EAR = 0, 7, 8
L_SH, R_SH, L_EL, R_EL, L_WR, R_WR = 11, 12, 13, 14, 15, 16
L_HIP, R_HIP, L_KN, R_KN, L_AN, R_AN = 23, 24, 25, 26, 27, 28


def angle3(a, b, c):
    v1, v2 = a - b, c - b
    cs = np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-9)
    return math.degrees(math.acos(np.clip(cs, -1, 1)))


def savgol(y, win=7, order=2):
    """Savitzky-Golay smoothing (no SciPy needed)."""
    half = win // 2
    x = np.arange(-half, half + 1)
    A = np.vander(x, order + 1, increasing=True)
    coef = np.linalg.pinv(A)[0]
    yp = np.pad(y, half, mode="edge")
    return np.convolve(yp, coef[::-1], mode="valid")


def interp_gaps(y, bad):
    y = y.copy()
    idx = np.arange(len(y))
    good = ~bad
    if good.sum() >= 2:
        y[bad] = np.interp(idx[bad], idx[good], y[good])
    return y


def run(pose_path, out_path, fix=None, truth=None):
    P = json.load(open(pose_path))
    if fix and "range" in fix:
        a, b = fix["range"]
        P["frames"] = P["frames"][a:b]
    fps = P["fps"]
    fr = P["frames"]
    n = len(fr)
    fix = fix or {}
    lm = np.zeros((n, 33, 4))
    bad = np.zeros(n, bool)
    for i, f in enumerate(fr):
        if f["ok"]:
            lm[i] = np.array(f["lm"])
        else:
            bad[i] = True
    for a, b in fix.get("drop", []):
        bad[a:b + 1] = True

    def mid(i, a, b):
        return (lm[i, a, :2] + lm[i, b, :2]) / 2

    # facing: nose ahead of the ears, in the first upright frames
    if "facing" in fix:
        facing = fix["facing"]
    else:
        d = [lm[i, NOSE, 0] - (lm[i, L_EAR, 0] + lm[i, R_EAR, 0]) / 2 for i in range(min(8, n)) if not bad[i]]
        facing = 1.0 if np.median(d) > 0 else -1.0

    raw = {k: np.zeros(n) for k in ("pitch", "hip", "knee", "shoulder", "elbow", "vis")}
    for i in range(n):
        if bad[i]:
            continue
        hip, sh = mid(i, L_HIP, R_HIP), mid(i, L_SH, R_SH)
        v = sh - hip
        # image y is down; + = top of the body moving the way the athlete faces
        raw["pitch"][i] = math.atan2(v[0], -v[1]) * facing
        acc = {k: [] for k in ("hip", "knee", "shoulder", "elbow")}
        for S, E, W, H, K, A in ((L_SH, L_EL, L_WR, L_HIP, L_KN, L_AN), (R_SH, R_EL, R_WR, R_HIP, R_KN, R_AN)):
            p = lm[i, :, :2]
            w = min(lm[i, H, 3], lm[i, K, 3])
            acc["hip"].append((180 - angle3(p[S], p[H], p[K]), w))
            acc["knee"].append((180 - angle3(p[H], p[K], p[A]), min(w, lm[i, A, 3])))
            # shoulder: arm vs trunk, + = arm forward/up in front of the body
            down = p[H] - p[S]
            arm = p[E] - p[S]
            ang = math.degrees(math.atan2(down[0] * arm[1] - down[1] * arm[0], np.dot(down, arm)))
            acc["shoulder"].append((-ang * facing, lm[i, E, 3]))
            acc["elbow"].append((180 - angle3(p[S], p[E], p[W]), lm[i, W, 3]))
        for k, lst in acc.items():
            ws = np.array([w for _, w in lst]) + 1e-3
            raw[k][i] = float(np.dot([x for x, _ in lst], ws) / ws.sum())
        raw["vis"][i] = float(np.mean(lm[i, [L_SH, R_SH, L_HIP, R_HIP, L_KN, R_KN], 3]))
    # unwrap rotation, fill gaps, smooth
    pitch = np.unwrap(interp_gaps(raw["pitch"], bad))
    pitch -= np.median(pitch[:3])
    cur = {"pitch": savgol(pitch, 5, 2)}
    win = int(fix.get("smooth", 7))
    for k in ("hip", "knee", "shoulder", "elbow"):
        y = interp_gaps(raw[k], bad)
        if win > 7:
            # median first: left/right swaps upside down give single-frame spikes
            yp = np.pad(y, 2, mode="edge")
            y = np.array([np.median(yp[i:i + 5]) for i in range(len(y))])
        cur[k] = savgol(y, win, 2)
    t = np.arange(n) / fps
    omega = np.gradient(cur["pitch"], 1 / fps)
    peak = cur["pitch"][int(np.argmax(np.abs(cur["pitch"])))]
    turns = max(1, int(round(abs(peak) / (2 * math.pi))))
    direction = "back" if peak < 0 else "front"
    if "direction" in fix:     # manual correction (checked by eye)
        direction = fix["direction"]
        turns = int(fix.get("turns", turns))

    # phases
    rel = np.abs(cur["pitch"])
    i_rot = int(np.argmax(rel > 0.35))
    lo = max(0, i_rot - int(0.4 * fps))
    ext = cur["hip"][lo:i_rot + 1] + cur["knee"][lo:i_rot + 1]
    takeoff = fix.get("takeoff", lo + int(np.argmin(ext)))
    done = np.nonzero(rel > turns * 2 * math.pi - 0.6)[0]
    landing = fix.get("landing", None)
    if landing is None:
        landing = n - 1
        if len(done):
            after = np.nonzero((np.arange(n) >= done[0]) & (np.abs(omega) < 2.5))[0]
            if len(after):
                landing = int(after[0])
    flight = (landing - takeoff) / fps
    total = cur["pitch"][landing] - cur["pitch"][takeoff]
    if "rotation_deg" in fix:  # manual correction
        total = math.radians(fix["rotation_deg"])
    tuck = np.clip(((cur["hip"] + cur["knee"]) / 2 - 25) / 85.0, 0, 1)
    # normalised flight curves (u = 0 takeoff .. 1 landing), 41 samples
    u = np.linspace(0, 1, 41)
    fi = takeoff + u * (landing - takeoff)

    def samp(y):
        return np.interp(fi, np.arange(n), y).round(4).tolist()

    peak_omega = float(np.max(np.abs(omega[takeoff:landing + 1]))) if landing > takeoff else 0.0
    i_tuck = takeoff + int(np.argmax(tuck[takeoff:landing + 1])) if landing > takeoff else takeoff
    open_i = next((i for i in range(i_tuck, landing + 1) if tuck[i] < 0.5 * tuck[i_tuck]), landing)
    motion = {
        "name": fix.get("name", "backflip"),
        "source": P["video"],
        "fps": fps,
        "frames": n,
        "facing": facing,
        "direction": direction,
        "turns": turns,
        "total_rotation_rad": round(float(total), 3),
        "phases": {"takeoff": int(takeoff), "landing": int(landing), "flight_s": round(flight, 3),
                   "max_tuck_frame": int(i_tuck), "open_frame": int(open_i)},
        "timing": {
            "tuck_at_u": round((i_tuck - takeoff) / max(1, landing - takeoff), 3),
            "open_at_u": round((open_i - takeoff) / max(1, landing - takeoff), 3),
            "peak_omega": round(peak_omega, 2),
            "max_tuck": round(float(tuck[i_tuck]), 3),
        },
        "frames_data": {k: np.round(v, 4).tolist() for k, v in cur.items()} | {"t": t.round(4).tolist(),
                                                                                "tuck": tuck.round(4).tolist()},
        "flight": {"u": u.round(4).tolist(), "pitch": samp(cur["pitch"] - cur["pitch"][takeoff]),
                   "tuck": samp(tuck), "hip": samp(cur["hip"]), "knee": samp(cur["knee"]),
                   "shoulder": samp(cur["shoulder"]), "elbow": samp(cur["elbow"])},
        "quality": {"pose_found": int((~bad).sum()), "mean_visibility": round(float(raw["vis"][~bad].mean()), 3)},
    }
    if truth:
        motion["validation"] = validate(motion, cur, truth, fps)
    json.dump(motion, open(out_path, "w"), indent=1)
    print(json.dumps({k: motion[k] for k in ("direction", "turns", "total_rotation_rad", "phases", "timing", "quality")
                      + (("validation",) if truth else ())}, indent=1))


def validate(motion, cur, truth_path, fps):
    """Compare with the game's own ground truth (synthetic test clip).
    The renderer shows a frame a little after the physics step that logged
    it, so the best frame alignment (searched) is reported too."""
    T = json.load(open(truth_path))
    tp = np.array([x["pitch"] for x in T])
    air = np.array([x["state"] == 1 for x in T])
    p = np.array(cur["pitch"])
    best = None
    for off in range(-4, 5):
        idx = [i for i in range(len(p)) if 0 <= i + off < len(T) and air[i + off] and abs(tp[i + off]) > 0]
        if len(idx) < 5:
            continue
        e = np.array([p[i] - tp[i + off] for i in idx])
        rms = math.sqrt(np.mean(e ** 2))
        if best is None or rms < best[0]:
            best = (rms, off, float(np.max(np.abs(e))), idx)
    rms, off, mx, idx = best
    ai = np.nonzero(air)[0]
    # the flight that contains the flip
    flip = [i for i in ai if abs(tp[i]) > 0.5]
    k0 = flip[0]
    while k0 - 1 in ai:
        k0 -= 1
    k1 = flip[-1]
    while k1 + 1 in ai:
        k1 += 1
    take_t, land_t = k0 - off, k1 + 1 - off
    full = tp[k1]
    return {
        "frame_offset": off,
        "flight_pitch_rms_deg": round(math.degrees(rms), 1),
        "flight_pitch_max_err_deg": round(math.degrees(mx), 1),
        "captured_rotation_rad": motion["total_rotation_rad"],
        "truth_rotation_rad": round(float(math.copysign(round(abs(full) / (2 * math.pi)) * 2 * math.pi, full)), 3),
        "truth_takeoff": int(take_t), "truth_landing": int(land_t),
        "takeoff_err_frames": motion["phases"]["takeoff"] - int(take_t),
        "landing_err_frames": motion["phases"]["landing"] - int(land_t),
    }


if __name__ == "__main__":
    a = sys.argv
    fix = json.load(open(a[a.index("--fix") + 1])) if "--fix" in a else None
    tr = a[a.index("--truth") + 1] if "--truth" in a else None
    run(a[1], a[2], fix, tr)
