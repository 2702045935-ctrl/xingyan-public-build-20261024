#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VIEW = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("moment compose verification failed: " + message)


require(
    'Text(Tr("取消"))' in VIEW
    and 'Text(uploading ? Tr("发表中…") : Tr("发表"))' in VIEW
    and 'NavBar(title: Tr("发表")' not in VIEW,
    "Moments publishing must use the compact WeChat cancel/publish header",
)
require(
    "private var composerSurface: Color" in VIEW
    and "Color.dyn(0xFFFFFF, 0x111111)" in VIEW
    and "private var composerRule: Color" in VIEW
    and "Color.dyn(0xE7E7E7, 0x2A2A2A)" in VIEW,
    "the composer must share one flat light/dark writing surface",
)
require(
    'Text(Tr("这一刻的想法…"))' in VIEW
    and "TextEditor(text: $draft)" in VIEW
    and ".frame(minHeight: 104)" in VIEW
    and ".scrollContentBackground(.hidden)" in VIEW,
    "the caption area must be the first-class edge-to-edge writing surface",
)
require(
    "let gap: CGFloat = 6" in VIEW
    and "repeating: GridItem(.fixed(side), spacing: gap), count: 3" in VIEW
    and 'Image(systemName: "plus")' in VIEW
    and "let side = (L.width - 32 - gap * 2) / 3" in VIEW,
    "selected media must use the compact WeChat three-column grid",
)
location = VIEW.index('composerRow(icon: "location"')
visibility = VIEW.index('composerRow(icon: "eye"', location)
remind = VIEW.index('composerRow(icon: "at"', visibility)
row_surfaces = VIEW[location:VIEW.index("private var visibilityName", visibility)]
require(
    location < visibility < remind
    and ".frame(height: 50)" in row_surfaces,
    "the existing composer row layout and order must stay unchanged",
)
require(
    "ProgressView(value: publishProgress)" in VIEW
    and ".progressViewStyle(.linear)" in VIEW
    and 'Text("\\(Int(min(1, max(0, publishProgress)) * 100))%")' in VIEW,
    "publishing progress must stay visible without becoming a card",
)
require(
    ".fullScreenCover(isPresented: $posting)" in VIEW
    and ".scrollDismissesKeyboard(.interactively)" in VIEW
    and ".background(composerSurface.ignoresSafeArea())" in VIEW,
    "the composer must use one immersive, keyboard-interactive canvas",
)
require(
    "python3 tools/verify-moment-compose-wechat.py" in WORKFLOW,
    "the WeChat Moments composer regression must run in the iOS gate",
)

print("moment-compose-wechat: passed")
