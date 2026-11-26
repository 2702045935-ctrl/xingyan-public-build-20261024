# iPhone USB control

- On this Windows host, control the connected iPhone directly through `pymobiledevice3` over USB.
- Do not use i4Tools' phone mirror as the automation channel.
- Discover the UDID with `python3 -m pymobiledevice3 usbmux list`; do not hard-code it in source.
- Observe before acting with `python3 -m pymobiledevice3 developer dvt screenshot <path>` and `python3 tools/iphone-usb-ax.py --udid <udid>`.
- Tap or swipe with `python3 tools/iphone-usb-input.py --udid <udid> --x <x> --y <y>`.
- Refresh the screenshot after every navigation or state change. Never reuse stale coordinates blindly.
