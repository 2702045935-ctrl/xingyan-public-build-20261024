import Foundation

/// Independent mall catalog module. It has no UI or application-state dependency.
public enum MallModule {
    public static let identifier = "xingyan.mall"
}

public protocol MallCatalogItem {
    var mallID: String { get }
    var mallCategory: String { get }
    var mallIsSelfOperated: Bool { get }
    var mallDiscountRate: Double { get }
    var mallSaving: Double { get }
    var mallSales: Int { get }
    var mallSearchText: String { get }
    var mallIsLive: Bool { get }
    var mallShopKey: String { get }
    var mallTags: [String] { get }
}

public enum MallCatalogSort: Int {
    case recommended = 0
    case discount = 1
    case sales = 2
    case newest = 3
}

public struct MallCatalogKernel<Item: MallCatalogItem> {
    public private(set) var live: [Item] = []
    public private(set) var categories: [String] = []

    private var byID: [String: Item] = [:]
    private var byCategory: [String: [Item]] = [:]
    private var selfByCategory: [String: [Item]] = [:]
    private var thirdByCategory: [String: [Item]] = [:]
    private var byShop: [String: [Item]] = [:]
    private var selfRows: [Item] = []
    private var thirdRows: [Item] = []
    private var queryCache: [String: [Item]] = [:]
    private var searchCache: [String: [Item]] = [:]
    private var seckillCache: [Item]?
    private var dealCache: [Item]?
    private var dealAverageCache: (count: Int, average: Double)?
    private var categoryTagCache: [String: [String]] = [:]
    private var relatedCache: [String: [Item]] = [:]
    private var revision = 0

    public init() {}

    public mutating func rebuild(_ products: [Item]) {
        var idIndex: [String: Item] = [:]
        var categoryRows: [String: [Item]] = [:]
        var selfCategoryRows: [String: [Item]] = [:]
        var thirdCategoryRows: [String: [Item]] = [:]
        var shopRows: [String: [Item]] = [:]
        var allSelf: [Item] = []
        var allThird: [Item] = []
        var seenCategories = Set<String>()
        var orderedCategories: [String] = []
        var active: [Item] = []

        idIndex.reserveCapacity(products.count)
        for item in products where item.mallID.isEmpty == false {
            idIndex[item.mallID] = item
        }

        // Hidden/off-shelf items remain resolvable through item(id:).
        let activeItems = products.filter(\.mallIsLive)
        active = activeItems
        for item in active {
            if seenCategories.insert(item.mallCategory).inserted {
                orderedCategories.append(item.mallCategory)
            }
            categoryRows[item.mallCategory, default: []].append(item)
            shopRows[item.mallShopKey, default: []].append(item)
            if item.mallIsSelfOperated {
                allSelf.append(item)
                selfCategoryRows[item.mallCategory, default: []].append(item)
            } else {
                allThird.append(item)
                thirdCategoryRows[item.mallCategory, default: []].append(item)
            }
        }

        byID = idIndex
        live = active
        categories = orderedCategories
        byCategory = categoryRows
        selfByCategory = selfCategoryRows
        thirdByCategory = thirdCategoryRows
        byShop = shopRows
        selfRows = allSelf
        thirdRows = allThird
        revision &+= 1
        invalidateQueryCaches()
    }

    public func item(id: String) -> Item? {
        byID[id]
    }

    public func counts(category: String?) -> (all: Int, selfOperated: Int, third: Int) {
        let all = category.map { byCategory[$0]?.count ?? 0 } ?? live.count
        let selfCount = category.map { selfByCategory[$0]?.count ?? 0 } ?? selfRows.count
        return (all, selfCount, max(0, all - selfCount))
    }

    public mutating func rows(category: String?,
                              sellerScope: String?,
                              sort: MallCatalogSort,
                              include: (Item) -> Bool) -> [Item] {
        let key = [
            String(revision),
            category ?? "*",
            sellerScope ?? "*",
            String(sort.rawValue)
        ].joined(separator: "|")
        if let cached = queryCache[key] { return cached }

        let source: [Item]
        switch sellerScope {
        case "self":
            source = category.map { selfByCategory[$0] ?? [] } ?? selfRows
        case "third":
            source = category.map { thirdByCategory[$0] ?? [] } ?? thirdRows
        default:
            source = category.map { byCategory[$0] ?? [] } ?? live
        }
        let filtered = source.filter(include)
        let sorted: [Item]
        switch sort {
        case .discount:
            sorted = filtered.sorted {
                $0.mallDiscountRate > $1.mallDiscountRate
            }
        case .sales:
            sorted = filtered.sorted { $0.mallSales > $1.mallSales }
        case .newest:
            sorted = Array(filtered.reversed())
        case .recommended:
            sorted = filtered
        }
        if queryCache.count >= 64 {
            queryCache.removeAll(keepingCapacity: true)
        }
        queryCache[key] = sorted
        return sorted
    }

    public mutating func search(_ query: String) -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return live }
        let key = trimmed.lowercased()
        if let cached = searchCache[key] { return cached }
        let needle = key
        let result = live.filter {
            $0.mallSearchText.localizedCaseInsensitiveContains(needle)
        }
        if searchCache.count >= 48 {
            searchCache.removeAll(keepingCapacity: true)
        }
        searchCache[key] = result
        return result
    }

    public mutating func seckill(limit: Int = 8) -> [Item] {
        let rows: [Item]
        if let seckillCache {
            rows = seckillCache
        } else {
            rows = live.filter { $0.mallDiscountRate > 0 }.sorted {
                if $0.mallDiscountRate != $1.mallDiscountRate {
                    return $0.mallDiscountRate > $1.mallDiscountRate
                }
                return $0.mallSales > $1.mallSales
            }
            seckillCache = rows
        }
        return Array(rows.prefix(max(0, limit)))
    }

    public mutating func deals(limit: Int) -> [Item] {
        let rows: [Item]
        if let dealCache {
            rows = dealCache
        } else {
            rows = live.filter { $0.mallDiscountRate > 0 }.sorted {
                if $0.mallDiscountRate != $1.mallDiscountRate {
                    return $0.mallDiscountRate > $1.mallDiscountRate
                }
                return $0.mallSales > $1.mallSales
            }
            dealCache = rows
        }
        return Array(rows.prefix(max(0, limit)))
    }

    public mutating func bestDeal() -> Item? {
        deals(limit: 1).first
    }

    public mutating func dealAverageSaving() -> (count: Int, average: Double) {
        if let dealAverageCache { return dealAverageCache }
        let rows = live.filter { $0.mallDiscountRate > 0 }
        guard !rows.isEmpty else { return (0, 0) }
        let total = rows.reduce(0.0) { $0 + $1.mallSaving }
        let value = (rows.count, total / Double(rows.count))
        dealAverageCache = value
        return value
    }

    public mutating func hashtags(category: String?, limit: Int = 8) -> [String] {
        let key = category ?? "*"
        let rows: [String]
        if let cached = categoryTagCache[key] {
            rows = cached
        } else {
            let source = category.map { byCategory[$0] ?? [] } ?? live
            var seen = Set<String>()
            var tags: [String] = []
            for item in source {
                for tag in item.mallTags where seen.insert(tag).inserted {
                    tags.append(tag)
                }
            }
            categoryTagCache[key] = tags
            rows = tags
        }
        return Array(rows.prefix(max(0, limit)))
    }

    public mutating func related(to item: Item, limit: Int) -> [Item] {
        if let cached = relatedCache[item.mallID] {
            return Array(cached.prefix(max(0, limit)))
        }
        var seen = Set<String>()
        seen.insert(item.mallID)
        var rows: [Item] = []
        for candidate in byCategory[item.mallCategory] ?? [] {
            if seen.insert(candidate.mallID).inserted {
                rows.append(candidate)
            }
        }
        for candidate in byShop[item.mallShopKey] ?? [] {
            if seen.insert(candidate.mallID).inserted {
                rows.append(candidate)
            }
        }
        if relatedCache.count >= 32 {
            relatedCache.removeAll(keepingCapacity: true)
        }
        relatedCache[item.mallID] = rows
        return Array(rows.prefix(max(0, limit)))
    }

    public mutating func invalidateQueryCaches() {
        queryCache.removeAll(keepingCapacity: true)
        searchCache.removeAll(keepingCapacity: true)
        categoryTagCache.removeAll(keepingCapacity: true)
        relatedCache.removeAll(keepingCapacity: true)
        seckillCache = nil
        dealCache = nil
        dealAverageCache = nil
    }
}
