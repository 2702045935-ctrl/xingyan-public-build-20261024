#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTACTS = (ROOT / "Sources" / "ContactsView.swift").read_text(encoding="utf-8")
CORE = (ROOT / "Sources" / "Core.swift").read_text(encoding="utf-8")
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("contacts derived-cache verification failed: " + message)


require(
    "private struct ContactDirectorySnapshot" in CONTACTS
    and "static func build(contacts: [User], keyword: String)" in CONTACTS
    and "usersByID: contactByID" in CONTACTS
    and "letters: Set(order)" in CONTACTS,
    "contacts must compile sorting, grouping, index and lookup once",
)
require(
    "@State private var directory = ContactDirectorySnapshot()" in CONTACTS
    and "private var sections: [ContactSection] {\n        directory.sections\n    }" in CONTACTS
    and "directory.usersByID[id]" in CONTACTS
    and "available: directory.letters" in CONTACTS,
    "rendering must consume the cached snapshot instead of rebuilding it",
)
require(
    ".onChange(of: app.contacts) { _ in\n            rebuildDirectory()" in CONTACTS
    and ".onChange(of: keyword) { _ in\n            rebuildDirectory()" in CONTACTS
    and "await app.loadContacts()\n            rebuildDirectory()" in CONTACTS,
    "the snapshot must refresh only when source data or search changes",
)
require(
    "func prefetchAvatars(_ paths: [String]" in CORE
    and "ImageStore.shared.diskRead(key)" in CORE
    and "ImageStore.shared.putAvatar(key, image)" in CORE
    and "private func prefetchContactAvatars(_ rows: [User])" in APP
    and "prefetchContactAvatars(cachedContacts)" in APP
    and "prefetchContactAvatars(friends)" in APP,
    "cached contact avatars must be warmed from disk before first paint",
)

print("contacts-derived-cache: passed")
