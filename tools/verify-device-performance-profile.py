#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROFILE = (ROOT / "Sources" / "DevicePerformanceProfile.swift").read_text(
    encoding="utf-8"
)
NAV = (ROOT / "Sources" / "NavGlass.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
CORE = (ROOT / "Sources" / "Core.swift").read_text(encoding="utf-8")
MOMENT = (ROOT / "Sources" / "NativeMomentRowCell.swift").read_text(
    encoding="utf-8"
)
MALL = (ROOT / "Sources" / "NativeMallProductGrid.swift").read_text(
    encoding="utf-8"
)
VIDEO = (ROOT / "Sources" / "VideoPlaybackKernel.swift").read_text(
    encoding="utf-8"
)
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("device performance verification failed: " + message)


require(
    "enum DevicePerformanceTier" in PROFILE
    and "case legacy" in PROFILE
    and "case balanced" in PROFILE
    and "case high" in PROFILE
    and "ProcessInfo.processInfo.physicalMemory" in PROFILE
    and "isLowPowerModeEnabled" in PROFILE
    and "thermalStateDidChangeNotification" in PROFILE
    and "didReceiveMemoryWarningNotification" in PROFILE
    and "result = result.degraded" in PROFILE,
    "hardware, thermal, low-power and memory pressure must share one tier policy",
)
require(
    "allowsLiquidGlass" in PROFILE
    and "allowsBackdropBlur" in PROFILE
    and "videoPlayerLimit" in PROFILE
    and "imageMaxSide" in PROFILE
    and "limitedImageSide" in PROFILE,
    "the profile must expose concrete rendering and media budgets",
)
require(
    "@ObservedObject private var performance = DevicePerformanceProfile.shared" in NAV
    and "guard !reduceTransparency, performance.allowsBackdropBlur" in NAV
    and "guard performance.allowsLiquidGlass else" in NAV
    and "reduceTransparency || !performance.allowsBackdropBlur" in NAV,
    "system glass must automatically fall back to blur or opaque control surfaces",
)
require(
    "@ObservedObject private var performance = DevicePerformanceProfile.shared" in CHAT
    and "reduceTransparency || !performance.allowsBackdropBlur" in CHAT,
    "chat edge masks must respect the active device budget",
)
require(
    "DevicePerformanceProfile.shared.limitedImageSide(maxSide)" in CORE
    and "memoryCap = 56 * 1024 * 1024" in CORE
    and "avatarMemoryCap = 28 * 1024 * 1024" in CORE
    and "let effectiveLimit = min(limit, tierLimit)" in CORE,
    "image decode size, cache and avatar prefetch must scale with the device",
)
require(
    "DevicePerformanceProfile.shared.limitedImageSide(maxSide)" in MOMENT
    and "tier == .high ? 14" in MOMENT
    and "DevicePerformanceProfile.shared.tier" in MALL
    and "case .legacy: stride = 3" in MALL,
    "moments and mall prefetch must reduce decorative decode work on lower tiers",
)
require(
    "hardwarePlayerLimit" in VIDEO
    and "hardwareLookAhead" in VIDEO
    and "hardware.videoPlayerLimit" in VIDEO,
    "video pools must obey the hardware player and look-ahead budget",
)
require(
    "python3 tools/verify-device-performance-profile.py" in WORKFLOW,
    "device performance regression must run in the iOS gate",
)

print("device-performance-profile: passed")
