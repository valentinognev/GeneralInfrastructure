#!/usr/bin/env python3
"""Republish Gazebo VIO camera images as SVOF grayscale TCP frames. No rospy at import."""
from __future__ import annotations

import argparse
import socket
import struct
import threading

CAMERA_TCP_BASE = 5600
_SVOF_HDR = struct.Struct("<4sHHQI")


def camera_tcp_port(drone_id: int) -> int:
    return CAMERA_TCP_BASE + (int(drone_id) - 1)


def rgb_to_gray(rgb: bytes, width: int, height: int) -> bytes:
    n = int(width) * int(height)
    out = bytearray(n)
    for i in range(n):
        o = i * 3
        r, g, b = rgb[o], rgb[o + 1], rgb[o + 2]
        out[i] = int(0.299 * r + 0.587 * g + 0.114 * b)
    return bytes(out)


def pack_svof(w, h, t_ns, gray: bytes) -> bytes:
    return _SVOF_HDR.pack(b"SVOF", int(w), int(h), int(t_ns), len(gray)) + gray


def _close_quiet(obj) -> None:
    closer = getattr(obj, "close", None)
    if closer is not None:
        try:
            closer()
        except Exception:
            pass


def serve_frames(drone_id: int, *, bind_fn, gray_iter) -> None:
    port = camera_tcp_port(drone_id)
    srv = bind_fn(("0.0.0.0", port))
    pending = iter(gray_iter)
    current = None
    try:
        while True:
            try:
                conn, _addr = srv.accept()
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError, OSError):
                continue
            try:
                while True:
                    if current is None:
                        try:
                            current = next(pending)
                        except StopIteration:
                            return
                    w, h, t_ns, gray = current
                    conn.sendall(pack_svof(w, h, t_ns, gray))
                    current = None
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError, OSError):
                continue
            finally:
                _close_quiet(conn)
    finally:
        _close_quiet(srv)


def _default_bind(addr):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.settimeout(None)
    srv.bind(addr)
    srv.listen(1)
    return srv


def _image_to_gray(msg) -> bytes:
    encoding = getattr(msg, "encoding", "") or ""
    raw = bytes(msg.data)
    width = int(msg.width)
    height = int(msg.height)
    if encoding in ("rgb8", "bgr8", "rgba8", "bgra8"):
        bpp = 4 if "a" in encoding else 3
        row_step = int(getattr(msg, "step", 0) or width * bpp)
        rgb = bytearray()
        bgr = encoding.startswith("bgr")
        for y in range(height):
            row = raw[y * row_step : y * row_step + width * bpp]
            for i in range(0, len(row), bpp):
                if bgr:
                    rgb.extend((row[i + 2], row[i + 1], row[i]))
                else:
                    rgb.extend(row[i : i + 3])
        return rgb_to_gray(bytes(rgb), width, height)
    row_step = int(getattr(msg, "step", 0) or width)
    gray = bytearray()
    for y in range(height):
        gray.extend(raw[y * row_step : y * row_step + width])
    return bytes(gray)


if __name__ == "__main__":
    import rospy
    from sensor_msgs.msg import Image

    parser = argparse.ArgumentParser(prog="vio_cam_tcp")
    parser.add_argument("--num", type=int, required=True)
    ns = parser.parse_args()

    rospy.init_node("vio_cam_tcp", anonymous=True)

    def run_one(drone_id: int) -> None:
        latest: list = []

        def on_img(msg):
            stamp = msg.header.stamp
            t_ns = int(stamp.to_nsec()) if stamp else 0
            latest[:] = [(msg.width, msg.height, t_ns, _image_to_gray(msg))]

        rospy.Subscriber(
            f"/iris_{drone_id}/vio_cam/image_raw",
            Image,
            on_img,
            queue_size=1,
        )

        def gray_iter():
            rate = rospy.Rate(10)
            while not rospy.is_shutdown():
                if latest:
                    yield latest.pop()
                else:
                    rate.sleep()

        serve_frames(drone_id, bind_fn=_default_bind, gray_iter=gray_iter())

    threads = []
    for i in range(1, int(ns.num) + 1):
        t = threading.Thread(target=run_one, args=(i,), daemon=True)
        t.start()
        threads.append(t)
    rospy.spin()
