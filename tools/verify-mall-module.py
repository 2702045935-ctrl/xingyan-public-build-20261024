#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE = (ROOT / "Modules" / "MallModule" / "MallModule.swift").read_text(
    encoding="utf-8"
)
MALL = (ROOT / "Sources" / "MallNative.swift").read_text(encoding="utf-8")
CATEGORY = (ROOT / "Sources" / "MallCategory.swift").read_text(encoding="utf-8")
NATIVE_GRID = (ROOT / "Sources" / "NativeMallProductGrid.swift").read_text(
    encoding="utf-8"
)
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)
MAC_BUILD = (ROOT / "mac-build.sh").read_text(encoding="utf-8")
IOS_CHECK = (ROOT / ".github" / "workflows" / "ios-check.yml").read_text(
    encoding="utf-8"
)
MALL_UI_FILES = [
    "MallNative.swift",
    "MallDeep.swift",
    "MallAddress.swift",
    "MallService.swift",
    "MallVip.swift",
    "MallExtras.swift",
    "MallManage.swift",
    "MallOpsPanels.swift",
]
MALL_UI = "\n".join(
    (ROOT / "Sources" / name).read_text(encoding="utf-8")
    for name in MALL_UI_FILES
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
    and "NativeMallProductGrid(products: list" in CATEGORY
    and "NativeMallProductGrid(products: store.live" in MALL
    and "NativeMallProductGrid(products: result)" in MALL
    and "Array(list.prefix(gridLimit))" in MALL
    and "gridLimit = min(list.count, gridLimit + 120)" in MALL,
    "catalog lists must use cached queries, native reuse and bounded incremental windows",
)
require(
    "UICollectionViewCompositionalLayout" in NATIVE_GRID
    and "UICollectionViewDataSourcePrefetching" in NATIVE_GRID
    and "NativeMallImageLoader.shared.prefetch(paths, side: 360)" in NATIVE_GRID
    and "view.prefetchDataSource = context.coordinator" in NATIVE_GRID
    and "prefetchItemsAt indexPaths: [IndexPath]) {" in NATIVE_GRID
    and "collectionView.setContentOffset(.zero, animated: false)" in NATIVE_GRID
    and "UIColor.dyn(0xF5F5F7, 0x000000)" in NATIVE_GRID,
    "the product grid must use native cell reuse, image prefetching and light/dark surfaces",
)
require(
    "static let supportedCounts = [0, 5_000, 9_000]" in MALL
    and "func setStressProductCount(_ count: Int)" in MALL
    and "store.setStressProductCount(count)" in MALL
    and '"5,000"' in MALL
    and '"9,000"' in MALL
    and "unstressedProducts = r.products" in MALL,
    "mall stress fixtures must exercise 5,000 and 9,000 real products without replacing the base catalog",
)
require(
    "static let page     = Color.dyn(0xF5F5F7, 0x000000)" in MALL
    and "static let card     = Color.dyn(0xFFFFFF, 0x1C1C1E)" in MALL
    and "static let ink      = Color.dyn(0x1D1D1F, 0xF5F5F7)" in MALL
    and ".ddLight()" not in MALL_UI
    and ".preferredColorScheme(.light)" not in MALL_UI,
    "the complete mall UI must follow the app appearance with real light and dark tokens",
)
detail_body = MALL[
    MALL.index("struct DDDetailView: View"):
    MALL.index("private struct DDProductVideoSurface")
]
detail_order = [
    detail_body.index("mediaHero"),
    detail_body.index("priceCard"),
    detail_body.index('configurationCard.id("dd-config")'),
    detail_body.index("detailSectionNav(proxy)"),
    detail_body.index('benefitCard.id("dd-benefit")'),
    detail_body.index("highlightsCard"),
]
require(
    detail_order == sorted(detail_order)
    and "private func configPill(" in detail_body
    and 'ForEach(Array(product.specList.prefix(6)))' in detail_body
    and "DDColor.hero" in detail_body
    and "DDColor.fill" in detail_body
    and "background(DDColor.card)" in detail_body,
    "product detail must follow the Apple-style hero, product copy, configuration, navigation and service hierarchy in both themes",
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
