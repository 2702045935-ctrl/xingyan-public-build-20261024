#!/usr/bin/env python3
"""List the foreground iPhone accessibility elements over a USB connection."""

from __future__ import annotations

import argparse
import asyncio

from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.accessibilityaudit import AccessibilityAudit


async def list_elements(udid: str) -> None:
    lockdown = await create_using_usbmux(serial=udid)
    async with AccessibilityAudit(lockdown) as service:
        async for element in service.iter_elements():
            caption = element.caption or ""
            print(f"{caption}\t{element.platform_identifier}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", required=True)
    args = parser.parse_args()
    asyncio.run(list_elements(args.udid))


if __name__ == "__main__":
    main()
