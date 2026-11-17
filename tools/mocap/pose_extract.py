#!/usr/bin/env python3.12
"""Step 1+2: video -> frames + timestamps -> MediaPipe Pose landmarks.

Flips are hard for pose estimators: they are trained mostly on upright people
and lose track when the athlete is upside down. So each frame is also tried
rotated (by the body angle tracked in the previous frame and a few fixed
angles); the most confident detection wins and its landmarks are rotated back
into the original image.

Output JSON: {fps, width, height, frames: [{t, ok, angle, lm: [[x,y,z,vis]*33]}]}
(x, y in pixels of the original frame.)

Usage: python3.12 pose_extract.py video.mp4 out_pose.json [--debug dir]
"""
import json, math, sys
import cv2
import numpy as np
import mediapipe as mp

L_SH, R_SH, L_HIP, R_HIP = 11, 12, 23, 24


def rotate(img, deg, center):
    m = cv2.getRotationMatrix2D(center, deg, 1.0)
    h, w = img.shape[:2]
    # big enough canvas so nothing is cut off
    d = int(math.hypot(w, h))
    m[0, 2] += (d - w) / 2
    m[1, 2] += (d - h) / 2
    return cv2.warpAffine(img, m, (d, d)), m


def body_angle(lm):
    """Angle (deg, image space) of hips->shoulders, 0 = upright."""
    hip = (lm[L_HIP][:2] + lm[R_HIP][:2]) / 2
    sh = (lm[L_SH][:2] + lm[R_SH][:2]) / 2
    v = sh - hip
    return math.degrees(math.atan2(v[0], -v[1]))


def run(video, out, debug=None):
    cap = cv2.VideoCapture(video)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    pose = mp.solutions.pose.Pose(static_image_mode=True, model_complexity=1,
                                  enable_segmentation=False, min_detection_confidence=0.3)
    frames = []
    prev_angle = 0.0
    prev_vel = 0.0
    prev_center = None
    i = 0
    while True:
        ok, bgr = cap.read()
        if not ok:
            break
        h, w = bgr.shape[:2]
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        center = prev_center if prev_center is not None else (w / 2, h / 2)
        best = None
        pred = prev_angle + prev_vel
        cands = [pred, pred + 30, pred - 30, pred + 60, pred - 60, 0, 90, 180, 270]
        seen = set()
        for a in cands:
            a = round(a % 360, 1)
            if a in seen:
                continue
            seen.add(a)
            # rotate the frame by -a so a body at angle a becomes upright
            img, m = rotate(rgb, a, center) if a != 0 else (rgb, None)
            r = pose.process(img)
            if not r.pose_landmarks:
                continue
            ih, iw = img.shape[:2]
            pts = np.array([[p.x * iw, p.y * ih, p.z * iw, p.visibility] for p in r.pose_landmarks.landmark])
            conf = float(np.mean(pts[[11, 12, 23, 24, 25, 26, 27, 28], 3]))
            if m is not None:
                inv = cv2.invertAffineTransform(m)
                xy = np.c_[pts[:, :2], np.ones(len(pts))] @ inv.T
                pts[:, :2] = xy
            # temporal consistency: bodies don't jump 90 deg between frames
            jump = abs((body_angle(pts) - pred + 180) % 360 - 180) if i > 0 else 0.0
            score = conf - 0.6 * min(jump, 180) / 90.0
            if best is None or score > best[0]:
                best = (score, a, pts, conf)
        rec = {"t": i / fps, "ok": False}
        if best is not None:
            score, a, pts, conf = best
            rec.update(ok=True, score=conf, tried=a, lm=pts.round(2).tolist())
            ang = body_angle(pts)
            # continuous angle (no wrap) for the prediction
            ang = prev_angle + ((ang - prev_angle + 180) % 360 - 180)
            prev_vel = 0.6 * prev_vel + 0.4 * (ang - prev_angle) if i > 0 else 0.0
            prev_angle = ang
            hip = (pts[L_HIP][:2] + pts[R_HIP][:2]) / 2
            prev_center = (float(hip[0]), float(hip[1]))
            rec["angle"] = prev_angle
            if debug:
                dbg = bgr.copy()
                for a_, b_ in mp.solutions.pose.POSE_CONNECTIONS:
                    pa, pb = pts[a_], pts[b_]
                    cv2.line(dbg, (int(pa[0]), int(pa[1])), (int(pb[0]), int(pb[1])), (0, 255, 255), 2)
                cv2.imwrite(f"{debug}/pose_{i:04d}.png", dbg)
        frames.append(rec)
        i += 1
    json.dump({"video": video, "fps": fps, "width": w, "height": h, "frames": frames}, open(out, "w"))
    okn = sum(f["ok"] for f in frames)
    print(f"{len(frames)} frames @ {fps:.1f} fps, pose found in {okn}")


if __name__ == "__main__":
    dbg = sys.argv[sys.argv.index("--debug") + 1] if "--debug" in sys.argv else None
    run(sys.argv[1], sys.argv[2], dbg)
