#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE = (ROOT / "Modules" / "MallModule" / "MallModule.swift").read_text(
    encoding="utf-8"
)
MALL = (ROOT / "Sources" / "MallNative.swift").read_text(encoding="utf-8")
CATEGORY = (ROOT / "Sources" / "MallCategory.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)
MAC_BUILD = (ROOT / "mac-build.sh").read_text(encoding="utf-8")
IOS_CHECK = (ROOT / ".github" / "workflows" / "ios-check.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("mall module verification failed: " + message)


require(
    'identifier = "xingyan.mall"' in MODULE
    and "public enum MallModule" in MODULE
    and "import Foundation" in MODULE
    and "import SwiftUI" not in MODULE
    and "import UIKit" not in MODULE
    and "AppState" not in MODULE,
    "the mall kernel must stay independent from UI and the application host",
)
require(
    "protocol MallCatalogItem" in MODULE
    and "struct MallCatalogKernel<Item: MallCatalogItem>" in MODULE
    and "private var byID: [String: Item]" in MODULE
    and "mutating func rows(category:" in MODULE
    and "mutating func search(_ query:" in MODULE
    and "mutating func related(to item:" in MODULE,
    "catalog indexing, filtering, search and related products belong to the mall kernel",
)
require(
    "private var catalogKernel = MallCatalogKernel<DDProduct>()" in MALL
    and "catalogKernel.rebuild(products)" in MALL
    and "func product(_ id: String) -> DDProduct? { catalogKernel.item(id: id) }" in MALL
    and "catalogKernel.rows(" in MALL
    and "catalogKernel.search(query)" in MALL,
    "the store must use the independent catalog kernel instead of linear scans",
)
require(
    'LocalStore.privateFile("mall-catalog.json")' in MALL
    and "let b = Box(products: nil, orders: orders, cart: cart," in MALL
    and "Task.detached(priority: .utility)" in MALL
    and "try? data.write(to: url, options: .atomic)" in MALL,
    "catalog persistence must be separated from user-state writes",
)
require(
    "func refreshIfNeeded(maxAge: TimeInterval = 45)" in MALL
    and "let badgeTask = Task { await store.refreshMallBadges() }" in MALL,
    "mall entry must reuse fresh catalog data and overlap badge loading",
)
require(
    "store.gridProducts(category:" in CATEGORY
    and "store.categoryTags(" in CATEGORY
    and "store.relatedProducts(to: product, limit: 6)" in MALL
    and "LazyVStack(spacing: 10)" in MALL,
    "category, related-product and large result lists must use cached/lazy paths",
)
require(
    "python3 tools/verify-mall-module.py" in WORKFLOW
    and "-module-name XingyanMallCore" in WORKFLOW
    and "Modules/MallModule/MallModule.swift" in WORKFLOW
    and "-lXingyanMallCore" in WORKFLOW
    and "-module-name XingyanMallCore" in MAC_BUILD
    and "Modules/MallModule/MallModule.swift" in MAC_BUILD
    and "-lXingyanMallCore" in MAC_BUILD
    and "-module-name XingyanMallCore" in IOS_CHECK
    and "Modules/MallModule/MallModule.swift" in IOS_CHECK
    and "-I /tmp/XingyanMallCore" in IOS_CHECK,
    "mall module independence and performance regression must run in the iOS gate",
)

print("mall-module: passed")
