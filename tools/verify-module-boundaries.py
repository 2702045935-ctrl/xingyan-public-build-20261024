#!/usr/bin/env python3
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "module-boundaries.json"
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def fail(message: str) -> None:
    raise SystemExit("module boundary verification failed: " + message)


manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
modules = {row["name"]: row for row in manifest["modules"]}

for name, row in modules.items():
    missing = [
        dependency
        for dependency in row["dependencies"]
        if dependency not in modules
    ]
    if missing:
        fail(f"{name} depends on unknown modules: {missing}")
    package = ROOT / row["path"] / "Package.swift"
    if row["status"] == "active" and not package.is_file():
        fail(f"active module {name} has no Package.swift")

visiting: set[str] = set()
visited: set[str] = set()


def visit(name: str) -> None:
    if name in visiting:
        fail(f"dependency cycle at {name}")
    if name in visited:
        return
    visiting.add(name)
    for dependency in modules[name]["dependencies"]:
        visit(dependency)
    visiting.remove(name)
    visited.add(name)


for module_name in modules:
    visit(module_name)

if "swift test --package-path Packages/MessageDomain" not in WORKFLOW:
    fail("iOS gate must compile and test the active MessageDomain package")
if "python3 tools/verify-module-boundaries.py" not in WORKFLOW:
    fail("iOS gate must enforce module dependency direction")

print("module-boundaries: passed")
