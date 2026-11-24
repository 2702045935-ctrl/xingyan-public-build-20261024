#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTACTS = (ROOT / "Sources" / "ContactsView.swift").read_text(encoding="utf-8")
STRESS = (ROOT / "Sources" / "StressTestConfiguration.swift").read_text(
    encoding="utf-8"
)
FIXTURE = (ROOT / "Sources" / "ContactStressFixture.swift").read_text(
    encoding="utf-8"
)
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("contacts 5000 verification failed: " + message)


require(
    'value("XINGYAN_CONTACT_STRESS")' in STRESS
    and 'profileValue("contacts-")' in STRESS
    and "static let count = StressTestConfiguration.contactCount" in FIXTURE
    and "(0..<count).map" in FIXTURE,
    "the app must expose a local 5000-contact stress fixture",
)
require(
    "contacts = ContactStressFixture.contacts" in APP
    and "guard !ContactStressFixture.isActive else { return }" in APP,
    "stress contacts must not be replaced by a server refresh",
)
require(
    "private var sections: [ContactSection] {\n        directory.sections\n    }"
    in CONTACTS
    and "directory.usersByID[id]" in CONTACTS
    and "ContactDirectorySnapshot.build(" in CONTACTS
    and CONTACTS.count("pinyinInitial(") == 1,
    "5000-contact rendering must reuse one compiled directory snapshot",
)

print("contacts-5000: passed")
