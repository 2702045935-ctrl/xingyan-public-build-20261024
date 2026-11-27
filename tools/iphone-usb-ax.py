#!/usr/bin/env python3
"""List the foreground iPhone accessibility elements over a USB connection."""

from __future__ import annotations

import argparse
import asyncio
import sys

from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.accessibilityaudit import AccessibilityAudit


async def list_elements(udid: str, press: str, show_frame: bool) -> None:
    lockdown = await create_using_usbmux(serial=udid)
    async with AccessibilityAudit(lockdown) as service:
        index = 0
        async for element in service.iter_elements():
            caption = element.caption or ""
            frame = ""
            if show_frame:
                value = await service.element_attribute(
                    element.platform_identifier, "Frame"
                )
                frame = f"\t{value}"
            print(f"{index}\t{caption}{frame}\t{element.platform_identifier}", flush=True)
            if press and press in caption:
                await service.perform_press(element.platform_identifier)
                print(f"pressed\t{index}\t{caption}", flush=True)
                return
            index += 1


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", required=True)
    parser.add_argument("--press", default="", help="Press the first element containing this text.")
    parser.add_argument("--frame", action="store_true", help="Print the focusable frame.")
    args = parser.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    asyncio.run(list_elements(args.udid, args.press, args.frame))


if __name__ == "__main__":
    main()
