#!/usr/bin/env python3
import plistlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAP = (ROOT / "Sources" / "StarMapView.swift").read_text(encoding="utf-8")
DISCOVER = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)
INFO = plistlib.loads((ROOT / "Info.plist").read_bytes())


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("star map verification failed: " + message)


require(
    "import MapKit" in MAP
    and "MKMapCamera(" in MAP
    and "map.showsBuildings = true" in MAP
    and "map.showsTraffic = true" in MAP
    and "let approach = max(" in MAP
    and "let basePitch = model.use3D" in MAP
    and "pitch: basePitch" in MAP,
    "star map must use native MapKit 3D camera, buildings and traffic",
)
require(
    "MKLocalSearch(request: request).start()" in MAP
    and "MKDirections.Request()" in MAP
    and "Figure" not in MAP
    and "Baidu" not in MAP
    and "baidu" not in MAP,
    "place search and routing must use the provider abstraction without Baidu SDK",
)
require(
    "struct StarRouteGeometry" in MAP
    and "crossTrack" in MAP
    and "offRouteSamples >= 3" in MAP
    and "planRoute(preserveNavigation: true)" in MAP,
    "navigation must match the route, detect drift and reroute safely",
)
require(
    "private struct StarManeuverIcon: View" in MAP
    and "private struct StarMapControlIcon: View" in MAP
    and "case straight, left, right, slightLeft, slightRight, uTurn, roundabout, arrive" in MAP
    and "Color(hex: 0x2F86FF)" in MAP
    and "maneuverKind" in MAP,
    "navigation must use map-grade custom blue maneuver and control iconography",
)
require(
    "private var navigationChrome: some View" in MAP
    and "private var navigationInstructionCard: some View" in MAP
    and "private var followingInstructionStrip: some View" in MAP
    and "private var navigationTripCard: some View" in MAP
    and "private var routeOptions: some View" in MAP
    and "model.showingRouteOverview" in MAP
    and "model.voiceGuidanceEnabled" in MAP
    and "model.navigationCenter" in MAP
    and "smoothedCourse(" in MAP
    and "AVSpeechSynthesizer()" in MAP,
    "navigation must provide native system-grade guidance, options and camera behavior",
)
require(
    "private enum StarNavigationPhase" in MAP
    and "phase = .rerouting" in MAP
    and "private struct StarSavedPlace" in MAP
    and "StarPlaceStore.activeKey" in MAP
    and "recentPlaces" in MAP
    and "favoritePlaces" in MAP
    and "StarRouteRanking" in MAP
    and "allowsBackgroundLocationUpdates = true" in MAP
    and "location" in INFO.get("UIBackgroundModes", [])
    and "星轨地图导航" in INFO.get(
        "NSLocationWhenInUseUsageDescription", ""
    ),
    "navigation must persist recoverable state and declare background location use",
)
require(
    "private struct StarNavigationHUD: View" in MAP
    and "accessibilityReduceMotion" in MAP
    and "colorSchemeContrast" in MAP
    and "dynamicTypeSize" in MAP
    and "verticalSizeClass" in MAP
    and "adaptiveStrokeWidth" in MAP
    and "accessibilityLabel(kind.accessibilityTitle)" in MAP
    and "打开 HUD 抬头显示" in MAP,
    "navigation must expose adaptive motion, contrast and HUD access",
)
require(
    'case "map": StarMapView()' in DISCOVER
    and '"星轨地图"' in DISCOVER
    and 'action: "map"' in DISCOVER,
    "the star map must be reachable from the World page",
)
require(
    "python3 tools/verify-star-map.py" in WORKFLOW,
    "star map regression must run in the iOS gate",
)

print("star-map: passed")
