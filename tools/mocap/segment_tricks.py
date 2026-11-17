#!/usr/bin/env python3.12
"""Split a multi-trick slackline clip into contacts and flights, and label
every trick as  <takeoff position> -> <rotation> -> <landing position>
(feet / butt / chest / back), using MediaPipe landmarks from pose_extract.py.

Contacts: the athlete's lowest points (hips near the line) with the body
still; flights: in between. Positions at contact:
  feet  - trunk upright, hips extended (standing)
  butt  - trunk upright-ish, hips flexed ~90 (sitting on the line)
  chest - trunk horizontal, front of the body facing the ground
  back  - trunk horizontal, front of the body facing the sky
Rotation = change of trunk angle over the flight (unwrapped), in turns.

Usage: python3.12 segment_tricks.py pose.json out.json
"""
import json, math, sys
import numpy as np

NOSE = 0
L_SH, R_SH, L_HIP, R_HIP, L_KN, R_KN, L_AN, R_AN = 11, 12, 23, 24, 25, 26, 27, 28


def ang3(a, b, c):
    v1, v2 = a - b, c - b
    return math.degrees(math.acos(np.clip(np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-9), -1, 1)))


def smooth(y, k=5):
    yp = np.pad(y, k // 2, mode="edge")
    return np.convolve(yp, np.ones(k) / k, mode="valid")


def run(pose_path, out_path):
    P = json.load(open(pose_path))
    fps = P["fps"]
    L = np.array([f["lm"] for f in P["frames"]])  # n,33,4
    n = len(L)
    hip = (L[:, L_HIP, :2] + L[:, R_HIP, :2]) / 2
    sh = (L[:, L_SH, :2] + L[:, R_SH, :2]) / 2
    trunk = sh - hip
    raw = np.degrees(np.arctan2(trunk[:, 0], -trunk[:, 1]))
    angle = np.degrees(np.unwrap(np.radians(raw)))
    # front of the body: nose offset perpendicular to the trunk
    t_unit = trunk / (np.linalg.norm(trunk, axis=1, keepdims=True) + 1e-9)
    nose_off = L[:, NOSE, :2] - sh
    perp = nose_off - t_unit * np.sum(nose_off * t_unit, axis=1, keepdims=True)
    hipflex = np.array([180 - (ang3(L[i, L_SH, :2], L[i, L_HIP, :2], L[i, L_KN, :2]) +
                               ang3(L[i, R_SH, :2], L[i, R_HIP, :2], L[i, R_KN, :2])) / 2 for i in range(n)])
    knee = np.array([180 - (ang3(L[i, L_HIP, :2], L[i, L_KN, :2], L[i, L_AN, :2]) +
                            ang3(L[i, R_HIP, :2], L[i, R_KN, :2], L[i, R_AN, :2])) / 2 for i in range(n)])
    body_len = np.median(np.linalg.norm(trunk, axis=1)) * 3.0     # ~ standing height in px
    hy = smooth(hip[:, 1], 5)                                      # image y, down = larger
    vy = np.gradient(hy) * fps / body_len                          # body lengths / s
    omega = np.gradient(smooth(angle, 3)) * fps                    # deg/s
    # contacts: local maxima of hip y (lowest points) in the bottom part of the motion
    lowest = np.percentile(hy, 92)
    span = np.percentile(hy, 98) - np.percentile(hy, 5)
    cand = [i for i in range(2, n - 2) if hy[i] >= hy[i - 2:i + 3].max() and hy[i] > lowest - 0.35 * span]
    contacts = []
    for i in cand:
        if not contacts or i - contacts[-1] > int(0.35 * fps):
            contacts.append(i)
        elif hy[i] > hy[contacts[-1]]:
            contacts[-1] = i

    def position(i):
        a = ((raw[i] + 180) % 360) - 180
        # orientation of the trunk relative to vertical
        tilt = abs(a)
        if tilt < 50 or tilt > 130 and False:
            return "butt" if hipflex[i] > 55 else "feet"
        if 50 <= tilt <= 130:
            # front facing down (image +y) = chest
            return "chest" if perp[i, 1] > 0 else "back"
        return "inverted"

    def win_pos(i):
        # majority over +-2 frames
        votes = [position(j) for j in range(max(0, i - 2), min(n, i + 3))]
        return max(set(votes), key=votes.count)

    tricks = []
    for k in range(len(contacts) - 1):
        a, b = contacts[k], contacts[k + 1]
        rot = angle[b] - angle[a]
        turns = rot / 360.0
        peak = a + int(np.argmin(hy[a:b + 1]))
        height = (hy[a] - hy[peak]) / body_len * 1.75          # metres (assumes 1.75 m athlete)
        mx = float(np.max(np.abs(omega[a:b + 1])))
        tuck = float(np.max((hipflex[a:b + 1] + knee[a:b + 1]) / 2))
        frm, to = win_pos(a), win_pos(b)
        if abs(turns) < 0.3:
            rname = "no flip"
        else:
            whole = round(abs(turns) * 2) / 2
            rname = ("%g " % whole) + ("frontflip" if turns > 0 else "backflip") + " (rotation sign from camera side)"
        tricks.append({
            "start_s": round(a / fps, 2), "end_s": round(b / fps, 2),
            "from": frm, "to": to, "rotation_deg": round(float(rot)), "turns": round(float(turns), 2),
            "rotation": rname, "air_time_s": round((b - a) / fps, 2), "apex_m": round(float(height), 2),
            "peak_spin_deg_s": round(mx), "max_tuck_deg": round(tuck),
        })
    out = {"video": P["video"], "fps": fps, "frames": n, "contacts_s": [round(c / fps, 2) for c in contacts],
           "tricks": tricks,
           "series": {"t": (np.arange(n) / fps).round(3).tolist(), "angle": angle.round(1).tolist(),
                      "hip_y": hy.round(1).tolist(), "hipflex": hipflex.round(1).tolist(),
                      "knee": knee.round(1).tolist(), "front_down": (perp[:, 1] > 0).tolist()}}
    json.dump(out, open(out_path, "w"), indent=1)
    for t in tricks:
        print(f"{t['start_s']:5.2f}-{t['end_s']:5.2f}s  {t['from']:>8} -> {t['to']:<8} rot {t['rotation_deg']:5d} deg "
              f"({t['turns']:+.2f} turns)  air {t['air_time_s']:.2f}s  apex {t['apex_m']:.2f} m  "
              f"spin {t['peak_spin_deg_s']} deg/s  tuck {t['max_tuck_deg']} deg")


if __name__ == "__main__":
    run(sys.argv[1], sys.argv[2])
