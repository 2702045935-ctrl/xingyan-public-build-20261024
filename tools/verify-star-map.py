#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAP = (ROOT / "Sources" / "StarMapView.swift").read_text(encoding="utf-8")
DISCOVER = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("star map verification failed: " + message)


require(
    "import MapKit" in MAP
    and "MKMapCamera(" in MAP
    and "map.showsBuildings = true" in MAP
    and "map.showsTraffic = true" in MAP
    and "model.use3D ? 58 : 36" in MAP,
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
