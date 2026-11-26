#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NOTES = (ROOT / "Sources" / "NotesWorkspace.swift").read_text(encoding="utf-8")
ME = (ROOT / "Sources" / "MeView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("notes system verification failed: " + message)


require(
    "struct NotesWorkspaceView: View" in NOTES
    and "NoteRecord.init(favorite:)" in NOTES
    and "from.isEmpty else { return nil }" in NOTES,
    "the notes workspace must be a dedicated text-note surface, separate from chat favorites",
)
require(
    "NotesCache.load" in NOTES
    and "NotesCache.save" in NOTES
    and "favoritesResult()" in NOTES,
    "the notes workspace must render a local cache first and tolerate sync failure",
)
require(
    ".searchable(" in NOTES
    and "NoteSort" in NOTES
    and "groupTitle" in NOTES
    and "togglePinned" in NOTES
    and "delete(note)" in NOTES,
    "the system notes list must support search, native date groups, sorting, pinning, and deletion",
)
require(
    "FavoriteNoteComposeSheet" in NOTES
    and "FavoriteNoteDetailSheet" in NOTES
    and "showFavorites" in NOTES,
    "notes must retain the editor, attachments, detail view, and a separate favorites entry",
)
require(
    'else if key == "favorites" {\n                    NotesWorkspaceView()' in ME,
    "the Me notes entry must open the dedicated workspace",
)

print("notes-system: passed")
