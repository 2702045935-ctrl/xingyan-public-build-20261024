#!/usr/bin/env python3
"""Tap or swipe an iPhone through CoreDevice HID over USB."""

from __future__ import annotations

import argparse
import asyncio

from pymobiledevice3.remote import userspace_tunnel
from pymobiledevice3.remote.core_device.hid_service import (
    DIGITIZER_SURFACE_MAIN_TOUCHSCREEN,
    TOUCH_AUTH_SETTLE_SECONDS,
    TOUCHSCREEN_STATE_CONTACT,
    TOUCHSCREEN_STATE_RELEASE,
    UniversalHIDServiceService,
)


def normalized(value: float, total: float) -> int:
    return round(min(total, max(0, value)) / total * 65535)


async def send_touch(
    touch: UniversalHIDServiceService,
    start: tuple[float, float],
    end: tuple[float, float],
    width: float,
    height: float,
    duration: float,
    steps: int,
    hold: float,
) -> None:
    x0 = normalized(start[0], width)
    y0 = normalized(start[1], height)
    x1 = normalized(end[0], width)
    y1 = normalized(end[1], height)

    await touch.send_touchscreen(
        TOUCHSCREEN_STATE_CONTACT,
        x0,
        y0,
        service_id=DIGITIZER_SURFACE_MAIN_TOUCHSCREEN,
    )
    if hold > 0:
        await asyncio.sleep(hold)
    for index in range(1, max(1, steps) + 1):
        ratio = index / max(1, steps)
        await touch.send_touchscreen(
            TOUCHSCREEN_STATE_CONTACT,
            round(x0 + (x1 - x0) * ratio),
            round(y0 + (y1 - y0) * ratio),
            service_id=DIGITIZER_SURFACE_MAIN_TOUCHSCREEN,
        )
        await asyncio.sleep(duration / max(1, steps))
    await touch.send_touchscreen(
        TOUCHSCREEN_STATE_RELEASE,
        x1,
        y1,
        service_id=DIGITIZER_SURFACE_MAIN_TOUCHSCREEN,
    )


async def run(args: argparse.Namespace) -> None:
    provider = await userspace_tunnel.establish_userspace_rsd(serial=args.udid)
    try:
        async with UniversalHIDServiceService(provider) as touch:
            await asyncio.sleep(TOUCH_AUTH_SETTLE_SECONDS)
            await send_touch(
                touch,
                (args.x, args.y),
                (args.to_x, args.to_y),
                args.width,
                args.height,
                args.duration,
                args.steps,
                args.hold,
            )
    finally:
        await provider.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", required=True)
    parser.add_argument("--x", type=float, required=True)
    parser.add_argument("--y", type=float, required=True)
    parser.add_argument("--to-x", type=float)
    parser.add_argument("--to-y", type=float)
    parser.add_argument("--width", type=float, default=1260)
    parser.add_argument("--height", type=float, default=2736)
    parser.add_argument("--duration", type=float, default=0.08)
    parser.add_argument("--steps", type=int, default=4)
    parser.add_argument("--hold", type=float, default=0.12)
    args = parser.parse_args()
    if args.to_x is None:
        args.to_x = args.x
    if args.to_y is None:
        args.to_y = args.y
    asyncio.run(run(args))


if __name__ == "__main__":
    main()
