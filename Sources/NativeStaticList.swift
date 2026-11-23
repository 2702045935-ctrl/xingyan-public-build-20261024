import SwiftUI
import UIKit

struct NativeStaticItem: Identifiable, Equatable {
    let id: String
    let signature: String
}

private final class NativeStaticHostCell: UICollectionViewCell {
    private var host: UIHostingController<AnyView>?
    private var hostedID = ""
    private var hostedSignature = ""

    override func prepareForReuse() {
        super.prepareForReuse()
    }

    func setRootView(_ rootView: AnyView, id: String, signature: String) {
        if host == nil {
            let next = UIHostingController(rootView: rootView)
            next.view.backgroundColor = .clear
            contentView.addSubview(next.view)
            host = next
        } else if hostedID != id || hostedSignature != signature {
            host?.rootView = rootView
        }
        hostedID = id
        hostedSignature = signature
        host?.view.frame = contentView.bounds
    }

    func adopt(_ next: UIHostingController<AnyView>, id: String, signature: String) {
        if host !== next {
            host?.view.removeFromSuperview()
            host = next
            next.view.backgroundColor = .clear
            contentView.addSubview(next.view)
        }
        hostedID = id
        hostedSignature = signature
        next.view.frame = contentView.bounds
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        host?.view.frame = contentView.bounds
    }
}

private final class NativeStaticUIKitCell: UICollectionViewCell {
    private(set) var nativeView: UIView?

    func install(_ view: UIView) {
        if nativeView !== view {
            nativeView?.removeFromSuperview()
            nativeView = view
            contentView.addSubview(view)
        }
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        clipsToBounds = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        nativeView?.frame = contentView.bounds
    }
}

private final class NativeVirtualScrollIndicator: UIView {
    private let thumb = CALayer()
    private var topProgress: CGFloat = 1
    private var scrolling = false
    private var fadeWork: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        alpha = 0
        thumb.cornerRadius = 2
        thumb.backgroundColor = UIColor.label.withAlphaComponent(0.38).cgColor
        layer.addSublayer(thumb)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutThumb()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        thumb.backgroundColor = UIColor.label.withAlphaComponent(0.38).cgColor
    }

    func update(top: Double, bottom: Double) {
        topProgress = min(1, max(0, CGFloat(top)))
        let extent = min(1, max(0, CGFloat(bottom) - topProgress))
        thumb.opacity = extent > 0 ? 1 : 0
        layoutThumb()
    }

    func setScrolling(_ active: Bool) {
        scrolling = active
        fadeWork?.cancel()
        fadeWork = nil
        if active {
            alpha = 1
            return
        }
        let fade = DispatchWorkItem { [weak self] in
            guard let self, !self.scrolling else { return }
            UIView.animate(withDuration: 0.24,
                           delay: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.alpha = 0
            }
        }
        fadeWork = fade
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: fade)
    }

    private func layoutThumb() {
        guard bounds.height > 1 else { return }
        let minimumHeight: CGFloat = 36
        let height = min(bounds.height, max(minimumHeight, bounds.height * 0.04))
        let travel = max(0, bounds.height - height)
        let width: CGFloat = 4
        thumb.frame = CGRect(
            x: (bounds.width - width) / 2,
            y: topProgress * travel,
            width: width,
            height: height
        )
    }
}

final class NativeStaticListController {
    fileprivate var scrollToIDHandler: ((String, UICollectionView.ScrollPosition, Bool) -> Bool)?
    fileprivate var scrollToBottomHandler: ((Bool) -> Bool)?
    fileprivate var frameForIDHandler: ((String) -> CGRect?)?

    @discardableResult
    func scrollToID(_ id: String,
                    at position: UICollectionView.ScrollPosition = .centeredVertically,
                    animated: Bool = true) -> Bool {
        scrollToIDHandler?(id, position, animated) ?? false
    }

    @discardableResult
    func scrollToBottom(animated: Bool = false) -> Bool {
        scrollToBottomHandler?(animated) ?? false
    }

    func frameForID(_ id: String) -> CGRect? {
        frameForIDHandler?(id)
    }

    fileprivate func clear() {
        scrollToIDHandler = nil
        scrollToBottomHandler = nil
        frameForIDHandler = nil
    }
}

struct NativeStaticList<Item: Identifiable & Equatable, Row: View>: UIViewControllerRepresentable
where Item.ID: Hashable {
    let items: [Item]
    let controller: NativeStaticListController?
    let onScrollViewReady: ((UIScrollView) -> Void)?
    let onScrollStateChange: ((Bool) -> Void)?
    let onScrollOffset: ((CGFloat) -> Void)?
    let onSizeChange: (() -> Void)?
    let initiallyPinnedToBottom: Bool
    let keepsBottomOnItemChange: Bool
    let virtualHistoryPosition: ((Item) -> Double?)?
    let signature: (Item) -> String
    let nativeEligible: ((Item) -> Bool)?
    let nativeRow: ((Item, UIView?) -> UIView?)?
    let nativeHeight: ((Item, CGFloat) -> CGFloat?)?
    @ViewBuilder let row: (Item) -> Row

    init(items: [Item],
         controller: NativeStaticListController? = nil,
         onScrollViewReady: ((UIScrollView) -> Void)? = nil,
         onScrollStateChange: ((Bool) -> Void)? = nil,
         onScrollOffset: ((CGFloat) -> Void)? = nil,
         onSizeChange: (() -> Void)? = nil,
         initiallyPinnedToBottom: Bool = false,
         keepsBottomOnItemChange: Bool = false,
         virtualHistoryPosition: ((Item) -> Double?)? = nil,
         signature: @escaping (Item) -> String,
         nativeEligible: ((Item) -> Bool)? = nil,
         nativeRow: ((Item, UIView?) -> UIView?)? = nil,
         nativeHeight: ((Item, CGFloat) -> CGFloat?)? = nil,
         @ViewBuilder row: @escaping (Item) -> Row) {
        self.items = items
        self.controller = controller
        self.onScrollViewReady = onScrollViewReady
        self.onScrollStateChange = onScrollStateChange
        self.onScrollOffset = onScrollOffset
        self.onSizeChange = onSizeChange
        self.initiallyPinnedToBottom = initiallyPinnedToBottom
        self.keepsBottomOnItemChange = keepsBottomOnItemChange
        self.virtualHistoryPosition = virtualHistoryPosition
        self.signature = signature
        self.nativeEligible = nativeEligible
        self.nativeRow = nativeRow
        self.nativeHeight = nativeHeight
        self.row = row
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller,
                    onScrollViewReady: onScrollViewReady,
                    onScrollStateChange: onScrollStateChange,
                    onScrollOffset: onScrollOffset,
                    onSizeChange: onSizeChange,
                    initiallyPinnedToBottom: initiallyPinnedToBottom,
                    keepsBottomOnItemChange: keepsBottomOnItemChange,
                    virtualHistoryPosition: virtualHistoryPosition,
                    signature: signature,
                    nativeEligible: nativeEligible,
                    nativeRow: nativeRow,
                    nativeHeight: nativeHeight,
                    row: row)
    }

    func makeUIViewController(context: Context) -> UICollectionViewController {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.estimatedItemSize = .zero

        let controller = UICollectionViewController(collectionViewLayout: layout)
        controller.view.backgroundColor = .clear
        let collection = controller.collectionView!
        collection.backgroundColor = .clear
        collection.alwaysBounceVertical = true
        collection.alwaysBounceHorizontal = false
        collection.isDirectionalLockEnabled = true
        collection.showsVerticalScrollIndicator = true
        collection.contentInsetAdjustmentBehavior = .never
        collection.keyboardDismissMode = .interactive
        collection.delaysContentTouches = false
        collection.canCancelContentTouches = true
        collection.scrollsToTop = true
        collection.panGestureRecognizer.delaysTouchesBegan = false
        collection.panGestureRecognizer.maximumNumberOfTouches = 1
        collection.isPrefetchingEnabled = true
        collection.alpha = initiallyPinnedToBottom ? 0 : 1
        collection.delegate = context.coordinator
        collection.prefetchDataSource = context.coordinator
        collection.register(
            NativeStaticUIKitCell.self,
            forCellWithReuseIdentifier: "NativeStaticUIKitCell"
        )

        let registration = UICollectionView.CellRegistration<NativeStaticHostCell, Item.ID> {
            [weak coordinator = context.coordinator] cell, _, id in
            guard let coordinator,
                  let item = coordinator.lookup[id],
                  let rootView = coordinator.rootView(for: item) else { return }
            let itemID = String(describing: id)
            let signature = coordinator.signatures[id] ?? ""
            if let warm = coordinator.takeWarmHost(id, signature: signature) {
                cell.adopt(warm, id: itemID, signature: signature)
            } else {
                cell.setRootView(rootView, id: itemID, signature: signature)
            }
            cell.backgroundConfiguration = .clear()
            cell.backgroundColor = .clear
            cell.clipsToBounds = true
        }

        let dataSource = UICollectionViewDiffableDataSource<Int, Item.ID>(
            collectionView: collection
        ) { collectionView, indexPath, id in
            if let item = context.coordinator.lookup[id],
               context.coordinator.nativeEligible?(item) == true {
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: "NativeStaticUIKitCell",
                    for: indexPath
                ) as! NativeStaticUIKitCell
                if let nativeView = context.coordinator.nativeRow?(item, cell.nativeView) {
                    cell.install(nativeView)
                    return cell
                }
                let fallback = collectionView.dequeueConfiguredReusableCell(
                    using: registration,
                    for: indexPath,
                    item: id
                )
                return fallback
            }
            return collectionView.dequeueConfiguredReusableCell(
                using: registration,
                for: indexPath,
                item: id
            )
        }
        context.coordinator.dataSource = dataSource
        context.coordinator.collection = collection
        context.coordinator.attachController()
        context.coordinator.attachScroll(collection)
        context.coordinator.apply(items, animated: false)
        context.coordinator.installVirtualIndicatorIfNeeded(
            on: controller.view,
            collection: collection
        )
        return controller
    }

    func updateUIViewController(_ controller: UICollectionViewController,
                                context: Context) {
        context.coordinator.row = row
        context.coordinator.signature = signature
        context.coordinator.nativeEligible = nativeEligible
        context.coordinator.nativeRow = nativeRow
        context.coordinator.nativeHeight = nativeHeight
        context.coordinator.virtualHistoryPosition = virtualHistoryPosition
        context.coordinator.onScrollViewReady = onScrollViewReady
        context.coordinator.onScrollStateChange = onScrollStateChange
        context.coordinator.onScrollOffset = onScrollOffset
        context.coordinator.onSizeChange = onSizeChange
        context.coordinator.attachController()
        if let collection = controller.collectionView {
            context.coordinator.attachScroll(collection)
            context.coordinator.installVirtualIndicatorIfNeeded(
                on: controller.view,
                collection: collection
            )
        }
        context.coordinator.apply(items, animated: false)
    }

    final class Coordinator: NSObject,
                             UICollectionViewDelegateFlowLayout,
                             UICollectionViewDataSourcePrefetching {
        var lookup: [Item.ID: Item] = [:]
        var row: (Item) -> Row
        var signature: (Item) -> String
        var nativeEligible: ((Item) -> Bool)?
        var nativeRow: ((Item, UIView?) -> UIView?)?
        var nativeHeight: ((Item, CGFloat) -> CGFloat?)?
        var virtualHistoryPosition: ((Item) -> Double?)?
        weak var collection: UICollectionView?
        var dataSource: UICollectionViewDiffableDataSource<Int, Item.ID>?
        let controller: NativeStaticListController?
        var onScrollViewReady: ((UIScrollView) -> Void)?
        var onScrollStateChange: ((Bool) -> Void)?
        var onScrollOffset: ((CGFloat) -> Void)?
        var onSizeChange: (() -> Void)?
        var initiallyPinnedToBottom: Bool
        var keepsBottomOnItemChange: Bool
        private var waitsForInitialBottom = false
        private var sizeObservation: NSKeyValueObservation?
        private var lastScrollState: Bool?
        private var lastReportedOffsetY = CGFloat.greatestFiniteMagnitude
        private var order: [Item.ID] = []
        fileprivate var signatures: [Item.ID: String] = [:]
        private var heights: [Item.ID: CGFloat] = [:]
        private var warmHosts: [Item.ID: (signature: String,
                                          host: UIHostingController<AnyView>)] = [:]
        private var deferredWarmIDs: [Item.ID] = []
        private var deferredMeasureIDs: [Item.ID] = []
        private var deferredMeasureQueued = false
        private var width: CGFloat = 0
        private var pending: [Item]?
        private var applyGeneration = 0
        private var sizeChangeScheduled = false
        private var foregroundObserver: NSObjectProtocol?
        private weak var virtualScrollIndicator: NativeVirtualScrollIndicator?

        init(controller: NativeStaticListController?,
             onScrollViewReady: ((UIScrollView) -> Void)?,
             onScrollStateChange: ((Bool) -> Void)?,
             onScrollOffset: ((CGFloat) -> Void)?,
             onSizeChange: (() -> Void)?,
             initiallyPinnedToBottom: Bool,
             keepsBottomOnItemChange: Bool,
             virtualHistoryPosition: ((Item) -> Double?)?,
             signature: @escaping (Item) -> String,
             nativeEligible: ((Item) -> Bool)?,
             nativeRow: ((Item, UIView?) -> UIView?)?,
             nativeHeight: ((Item, CGFloat) -> CGFloat?)?,
             row: @escaping (Item) -> Row) {
            self.controller = controller
            self.onScrollViewReady = onScrollViewReady
            self.onScrollStateChange = onScrollStateChange
            self.onScrollOffset = onScrollOffset
            self.onSizeChange = onSizeChange
            self.initiallyPinnedToBottom = initiallyPinnedToBottom
            self.keepsBottomOnItemChange = keepsBottomOnItemChange
            self.waitsForInitialBottom = initiallyPinnedToBottom
            self.virtualHistoryPosition = virtualHistoryPosition
            self.signature = signature
            self.nativeEligible = nativeEligible
            self.nativeRow = nativeRow
            self.nativeHeight = nativeHeight
            self.row = row
            super.init()
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshAfterForeground()
            }
        }

        deinit {
            sizeObservation?.invalidate()
            if let foregroundObserver {
                NotificationCenter.default.removeObserver(foregroundObserver)
            }
        }

        private func refreshAfterForeground() {
            guard let collection, let dataSource else { return }
            DispatchQueue.main.async { [weak self, weak collection] in
                guard let self, let collection, self.collection === collection else { return }
                self.flush()
                collection.layoutIfNeeded()
                let previousOffset = collection.contentOffset
                var snapshot = dataSource.snapshot()
                let visibleIDs = collection.indexPathsForVisibleItems.compactMap {
                    indexPath -> Item.ID? in
                    guard indexPath.section == 0,
                          indexPath.item >= 0,
                          indexPath.item < snapshot.numberOfItems else { return nil }
                    return dataSource.itemIdentifier(for: indexPath)
                }
                let ids = visibleIDs.isEmpty ? snapshot.itemIdentifiers : visibleIDs
                guard !ids.isEmpty else { return }
                snapshot.reloadItems(ids)
                dataSource.apply(snapshot, animatingDifferences: false) {
                    collection.layoutIfNeeded()
                    collection.setContentOffset(previousOffset, animated: false)
                }
            }
        }

        func attachScroll(_ scrollView: UIScrollView) {
            onScrollViewReady?(scrollView)
            if sizeObservation == nil {
                sizeObservation = scrollView.observe(\.contentSize, options: [.new]) {
                    [weak self] _, _ in
                    guard let self else { return }
                    guard !self.sizeChangeScheduled else { return }
                    self.sizeChangeScheduled = true
                    DispatchQueue.main.async { [weak self] in
                        guard let self, let scrollView = self.collection else { return }
                        self.sizeChangeScheduled = false
                        if self.waitsForInitialBottom {
                            self.completeInitialBottom(scrollView)
                        }
                        self.onSizeChange?()
                    }
                }
            }
            publishScrollState(
                scrollView.isDragging || scrollView.isDecelerating || scrollView.isTracking
            )
            lastReportedOffsetY = scrollView.contentOffset.y
            updateVirtualScrollIndicator()
        }

        func installVirtualIndicatorIfNeeded(
            on host: UIView,
            collection: UICollectionView
        ) {
            guard virtualHistoryPosition != nil else { return }
            collection.showsVerticalScrollIndicator = false
            if virtualScrollIndicator != nil { return }
            let indicator = NativeVirtualScrollIndicator()
            indicator.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(indicator)
            NSLayoutConstraint.activate([
                indicator.topAnchor.constraint(equalTo: host.topAnchor, constant: 6),
                indicator.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -6),
                indicator.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -2),
                indicator.widthAnchor.constraint(equalToConstant: 8)
            ])
            virtualScrollIndicator = indicator
            updateVirtualScrollIndicator()
        }

        private func updateVirtualScrollIndicator() {
            guard virtualHistoryPosition != nil,
                  let collection,
                  let dataSource,
                  let indicator = virtualScrollIndicator else {
                virtualScrollIndicator?.update(top: 1, bottom: 1)
                return
            }
            var values: [Double] = []
            values.reserveCapacity(collection.indexPathsForVisibleItems.count)
            for indexPath in collection.indexPathsForVisibleItems {
                guard let id = dataSource.itemIdentifier(for: indexPath),
                      let item = lookup[id],
                      let value = virtualHistoryPosition?(item) else { continue }
                values.append(min(1, max(0, value)))
            }
            guard let top = values.min(), let bottom = values.max() else {
                indicator.update(top: 1, bottom: 1)
                return
            }
            indicator.update(top: top, bottom: bottom)
        }

        func publishScrollState(_ active: Bool) {
            if let y = collection?.contentOffset.y {
                ChatScrollHandle.shared.noteScroll(offsetY: y, active: active)
            }
            guard lastScrollState != active else { return }
            lastScrollState = active
            virtualScrollIndicator?.setScrolling(active)
            onScrollStateChange?(active)
        }

        func attachController() {
            guard let controller else { return }
            controller.scrollToIDHandler = { [weak self] id, position, animated in
                guard let self, let collection = self.collection else { return false }
                self.flush()
                collection.layoutIfNeeded()
                guard let index = self.order.firstIndex(where: {
                    String(describing: $0) == id
                }) else { return false }
                collection.scrollToItem(
                    at: IndexPath(item: index, section: 0),
                    at: position,
                    animated: animated
                )
                return true
            }
            controller.scrollToBottomHandler = { [weak self] animated in
                guard let self, let collection = self.collection else { return false }
                self.flush()
                collection.layoutIfNeeded()
                self.setBottom(collection, animated: animated)
                return true
            }
            controller.frameForIDHandler = { [weak self] id in
                guard let self,
                      let collection = self.collection,
                      let itemIndex = self.order.firstIndex(where: {
                          String(describing: $0) == id
                      }) else { return nil }
                let indexPath = IndexPath(item: itemIndex, section: 0)
                collection.layoutIfNeeded()
                guard let attributes = collection.collectionViewLayout
                    .layoutAttributesForItem(at: indexPath) else { return nil }
                return collection.convert(attributes.frame, to: nil)
            }
        }

        private func setBottom(_ collection: UICollectionView, animated: Bool) {
            let minimumY = -collection.adjustedContentInset.top
            let maximumY = max(
                minimumY,
                collection.contentSize.height - collection.bounds.height
                    + collection.adjustedContentInset.bottom
            )
            collection.setContentOffset(CGPoint(x: 0, y: maximumY), animated: animated)
        }

        func apply(_ next: [Item], animated: Bool) {
            guard let collection, let dataSource else { return }
            let nextOrder = next.map(\.id)
            var isPureAppend = !order.isEmpty
                && next.count > order.count
                && next.prefix(order.count).enumerated().allSatisfy { index, item in
                    order[index] == item.id && lookup[item.id] == item
                }
            if !isPureAppend, !order.isEmpty {
                let nextByID = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })
                var commonTail = 0
                while commonTail < min(order.count, nextOrder.count),
                      order[order.count - 1 - commonTail]
                        == nextOrder[nextOrder.count - 1 - commonTail] {
                    commonTail += 1
                }
                let oldCore = Array(order.prefix(order.count - commonTail))
                let nextCore = Array(nextOrder.prefix(nextOrder.count - commonTail))
                if commonTail > 0, !oldCore.isEmpty, !nextCore.isEmpty {
                    var stable = 0
                    for overlap in stride(
                        from: min(oldCore.count, nextCore.count),
                        through: 1,
                        by: -1
                    ) {
                        if nextCore.prefix(overlap).elementsEqual(oldCore.suffix(overlap)) {
                            stable = overlap
                            break
                        }
                    }
                    if stable > 0,
                       nextCore.count >= stable,
                       oldCore.suffix(stable).allSatisfy({ id in
                           guard let old = lookup[id], let current = nextByID[id] else {
                               return false
                           }
                           return old == current
                       }) {
                        isPureAppend = true
                    }
                }
            }
            // The first item is often a permanent history sentinel. Detect a
            // prepend from any existing row that moved down, rather than only
            // checking item zero, otherwise the atomic offset compensation is
            // skipped and a loaded page can flash in one frame later.
            let isPrepending: Bool
            if isPureAppend {
                isPrepending = false
            } else {
                let nextPositions = Dictionary(
                    uniqueKeysWithValues: nextOrder.enumerated().map { ($1, $0) }
                )
                isPrepending = order.enumerated().contains { oldPosition, id in
                    guard let nextPosition = nextPositions[id] else { return false }
                    return nextPosition > oldPosition
                }
            }
            let nextIDs = Set(nextOrder)
            var nextSignatures = signatures.filter { nextIDs.contains($0.key) }
            if isPrepending, !order.isEmpty {
                let known = Set(order)
                let firstExisting = nextOrder.firstIndex { known.contains($0) }
                    ?? nextOrder.startIndex
                let recalcEnd = nextOrder.index(
                    firstExisting,
                    offsetBy: min(8, nextOrder.count - firstExisting),
                    limitedBy: nextOrder.endIndex
                ) ?? nextOrder.endIndex
                let recalc = Set(nextOrder[firstExisting..<recalcEnd])
                for item in next where nextSignatures[item.id] == nil
                    || recalc.contains(item.id) {
                    nextSignatures[item.id] = signature(item)
                }
            } else {
                for item in next {
                    if let old = lookup[item.id],
                       old == item,
                       let existing = signatures[item.id] {
                        nextSignatures[item.id] = existing
                    } else {
                        nextSignatures[item.id] = signature(item)
                    }
                }
            }
            if nextOrder == order && nextSignatures == signatures {
                pending = nil
                return
            }
            if !order.isEmpty,
               collection.isDragging || collection.isTracking || collection.isDecelerating {
                let known = Set(order)
                let commonOrder = nextOrder.filter { known.contains($0) }
                if !isPrepending, !isPureAppend,
                   (commonOrder != order || nextSignatures != signatures) {
                    pending = next
                    return
                }
            }
            let nextLookup = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })
            let changed = nextOrder.filter { signatures[$0] != nextSignatures[$0] }
            for id in changed {
                heights[id] = nil
                warmHosts.removeValue(forKey: id)
            }
            let widthChanged = collection.bounds.width > 1
                && abs(collection.bounds.width - width) > 0.5
            if widthChanged {
                width = collection.bounds.width
                heights.removeAll(keepingCapacity: true)
                warmHosts.removeAll(keepingCapacity: true)
            }
            let knownOld = order
            lookup = nextLookup
            signatures = nextSignatures
            order = nextOrder
            pending = nil
            let moving = collection.isDragging || collection.isTracking
                || collection.isDecelerating
            let idsToPrepare = isPrepending
                ? Array(Set(changed).union(nextOrder.filter { !knownOld.contains($0) }))
                : nextOrder
            premeasure(idsToPrepare, nativeOnly: moving)
            if moving {
                queueDeferredHeights(
                    idsToPrepare.filter { heights[$0] == nil }
                )
            }
            let warmIDs: [Item.ID]
            if isPrepending {
                warmIDs = Array(nextOrder.prefix(24))
            } else {
                warmIDs = Array(nextOrder.suffix(waitsForInitialBottom ? 40 : 24))
            }
            if moving {
                enqueueWarm(warmIDs)
            } else {
                prewarm(warmIDs, maxCount: waitsForInitialBottom ? 40 : 12)
            }
            let previousOffset = collection.contentOffset
            let minimumY = -collection.adjustedContentInset.top
            let maximumY = max(
                minimumY,
                collection.contentSize.height - collection.bounds.height
                    + collection.adjustedContentInset.bottom
            )
            let wasAtBottom = previousOffset.y >= maximumY - 16
            let visibleAnchors: [(id: Item.ID, delta: CGFloat)] =
                collection.indexPathsForVisibleItems
                    .sorted { $0.item < $1.item }
                    .compactMap { indexPath in
                        guard let id = dataSource.itemIdentifier(for: indexPath),
                              let attributes = collection.collectionViewLayout
                                  .layoutAttributesForItem(at: indexPath) else {
                            return nil
                        }
                        return (
                            id,
                            attributes.frame.minY - collection.contentOffset.y
                        )
                    }
            let prependAnchor: (id: Item.ID, delta: CGFloat)?
            if isPrepending,
               let anchor = visibleAnchors.first {
                prependAnchor = anchor
            } else {
                prependAnchor = nil
            }
            applyGeneration += 1
            let generation = applyGeneration
            if isPrepending {
                let oldSet = Set(knownOld)
                let nextSet = Set(nextOrder)
                let added = nextOrder.filter { !oldSet.contains($0) }
                let removed = knownOld.filter { !nextSet.contains($0) }
                let reloaded = changed.filter { oldSet.contains($0) && nextSet.contains($0) }
                var snapshot = dataSource.snapshot()
                if widthChanged {
                    collection.collectionViewLayout.invalidateLayout()
                }
                if !added.isEmpty {
                    if let anchor = nextOrder.first(where: { oldSet.contains($0) }) {
                        snapshot.insertItems(added, beforeItem: anchor)
                    } else {
                        snapshot.appendItems(added)
                    }
                }
                if !removed.isEmpty { snapshot.deleteItems(removed) }
                if !reloaded.isEmpty { snapshot.reloadItems(reloaded) }
                dataSource.apply(snapshot, animatingDifferences: false) {
                    guard generation == self.applyGeneration,
                          self.collection === collection else { return }
                    collection.layoutIfNeeded()
                    if let anchor = prependAnchor,
                       let indexPath = dataSource.indexPath(for: anchor.id),
                       let attributes = collection.collectionViewLayout
                           .layoutAttributesForItem(at: indexPath) {
                        collection.setContentOffset(
                            CGPoint(
                                x: previousOffset.x,
                                y: attributes.frame.minY - anchor.delta
                            ),
                            animated: false
                        )
                        ChatScrollHandle.shared.clearPendingPrepend()
                        return
                    }
                    _ = ChatScrollHandle.shared.compensatePendingPrepend()
                }
                return
            }
            if isPureAppend {
                let oldSet = Set(knownOld)
                let nextSet = Set(nextOrder)
                let added = nextOrder.filter { !oldSet.contains($0) }
                let removed = knownOld.filter { !nextSet.contains($0) }
                let reloaded = changed.filter {
                    oldSet.contains($0) && nextSet.contains($0)
                }
                var snapshot = dataSource.snapshot()
                if widthChanged {
                    collection.collectionViewLayout.invalidateLayout()
                }
                if !removed.isEmpty { snapshot.deleteItems(removed) }
                let addedSet = Set(added)
                if let lastAdded = nextOrder.lastIndex(where: {
                    addedSet.contains($0)
                }) {
                    let trailing = nextOrder[nextOrder.index(after: lastAdded)...]
                    if let anchor = trailing.first(where: {
                        oldSet.contains($0) && nextSet.contains($0)
                    }) {
                        snapshot.insertItems(added, beforeItem: anchor)
                    } else {
                        snapshot.appendItems(added)
                    }
                }
                if !reloaded.isEmpty { snapshot.reloadItems(reloaded) }
                dataSource.apply(snapshot, animatingDifferences: false) {
                    guard generation == self.applyGeneration,
                          self.collection === collection else { return }
                    collection.layoutIfNeeded()
                    if self.waitsForInitialBottom {
                        self.completeInitialBottom(collection)
                        return
                    }
                    if wasAtBottom,
                       !collection.isDragging,
                       !collection.isTracking,
                       !collection.isDecelerating {
                        self.setBottom(collection, animated: false)
                        return
                    }
                    if let anchor = visibleAnchors.first(where: {
                        nextSet.contains($0.id)
                    }),
                       let indexPath = dataSource.indexPath(for: anchor.id),
                       let attributes = collection.collectionViewLayout
                           .layoutAttributesForItem(at: indexPath) {
                        collection.setContentOffset(
                            CGPoint(
                                x: previousOffset.x,
                                y: attributes.frame.minY - anchor.delta
                            ),
                            animated: false
                        )
                    }
                }
                return
            }
            var snapshot = NSDiffableDataSourceSnapshot<Int, Item.ID>()
            snapshot.appendSections([0])
            snapshot.appendItems(nextOrder)
            if !changed.isEmpty { snapshot.reloadItems(changed) }
            if widthChanged {
                collection.collectionViewLayout.invalidateLayout()
            }
            dataSource.apply(snapshot, animatingDifferences: animated) {
                guard generation == self.applyGeneration,
                      self.collection === collection else { return }
                collection.layoutIfNeeded()
                if isPrepending {
                    if let anchor = prependAnchor,
                       let indexPath = dataSource.indexPath(for: anchor.id),
                       let attributes = collection.collectionViewLayout
                           .layoutAttributesForItem(at: indexPath) {
                        collection.setContentOffset(
                            CGPoint(
                                x: previousOffset.x,
                                y: attributes.frame.minY - anchor.delta
                            ),
                            animated: false
                        )
                        ChatScrollHandle.shared.clearPendingPrepend()
                        return
                    }
                    _ = ChatScrollHandle.shared.compensatePendingPrepend()
                    return
                }
                guard !collection.isTracking,
                      !collection.isDragging,
                      !collection.isDecelerating else { return }
                if self.waitsForInitialBottom {
                    self.completeInitialBottom(collection)
                    return
                }
                if self.keepsBottomOnItemChange,
                   wasAtBottom,
                   !collection.isTracking,
                   !collection.isDragging,
                   !collection.isDecelerating {
                    self.setBottom(collection, animated: false)
                    return
                }
                let minimumY = -collection.adjustedContentInset.top
                let maximumY = max(
                    minimumY,
                    collection.contentSize.height - collection.bounds.height
                        + collection.adjustedContentInset.bottom
                )
                var target = previousOffset
                target.y = min(max(target.y, minimumY), maximumY)
                collection.setContentOffset(target, animated: false)
            }
        }

        private func completeInitialBottom(_ collection: UICollectionView) {
            guard waitsForInitialBottom else { return }
            collection.layoutIfNeeded()
            setBottom(collection, animated: false)
            waitsForInitialBottom = false
            UIView.performWithoutAnimation {
                collection.alpha = 1
            }
        }

        func collectionView(_ collectionView: UICollectionView,
                            layout collectionViewLayout: UICollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> CGSize {
            let resolved = dataSource?.itemIdentifier(for: indexPath)
            let fallback = indexPath.item < order.count ? order[indexPath.item] : nil
            guard let id = resolved ?? fallback, let item = lookup[id] else { return .zero }
            let width = max(1, collectionView.bounds.width)
            let height = heights[id] ?? measuredHeight(item, width: width)
            heights[id] = height
            return CGSize(width: width, height: height)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView,
                                      willDecelerate decelerate: Bool) {
            publishScrollState(decelerate)
            if !decelerate {
                flush()
                drainDeferredWarmup()
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            ChatScrollHandle.shared.noteUserMotion()
            ChatScrollHandle.shared.beginScrollGesture(offsetY: scrollView.contentOffset.y)
            waitsForInitialBottom = false
            scrollView.alpha = 1
            // A new finger can land while the previous flick is still
            // decelerating. The aggregate scrolling state stays true, but the
            // history runway is consumed per physical gesture and must be
            // re-armed by this new touch.
            lastScrollState = false
            publishScrollState(true)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            publishScrollState(false)
            flush()
            drainDeferredWarmup()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let active = scrollView.isDragging || scrollView.isTracking
                || scrollView.isDecelerating
            if active {
                ChatScrollHandle.shared.noteUserMotion()
            }
            let y = scrollView.contentOffset.y
            ChatScrollHandle.shared.noteScroll(offsetY: y, active: active)
            if abs(y - lastReportedOffsetY) >= 16 {
                lastReportedOffsetY = y
                onScrollOffset?(y)
            }
            publishScrollState(active)
            updateVirtualScrollIndicator()
        }

        private func premeasure(_ ids: [Item.ID], nativeOnly: Bool = false) {
            let measured = collection?.bounds.width ?? 0
            let width = measured > 1 ? measured : UIScreen.main.bounds.width
            guard width > 1 else { return }
            for id in ids where heights[id] == nil {
                guard let item = lookup[id] else { continue }
                if nativeOnly, nativeHeight?(item, width) == nil { continue }
                heights[id] = measuredHeight(item, width: width)
            }
        }

        private func queueDeferredHeights(_ ids: [Item.ID]) {
            guard !ids.isEmpty else { return }
            var known = Set(deferredMeasureIDs)
            for id in ids where heights[id] == nil && known.insert(id).inserted {
                deferredMeasureIDs.append(id)
            }
            if deferredMeasureIDs.count > 240 {
                deferredMeasureIDs.removeFirst(deferredMeasureIDs.count - 240)
            }
            scheduleDeferredHeightMeasurement()
        }

        private func scheduleDeferredHeightMeasurement() {
            guard !deferredMeasureQueued, !deferredMeasureIDs.isEmpty else { return }
            deferredMeasureQueued = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.004) { [weak self] in
                self?.drainDeferredHeightMeasurement()
            }
        }

        private func drainDeferredHeightMeasurement() {
            deferredMeasureQueued = false
            guard let collection else {
                deferredMeasureIDs.removeAll(keepingCapacity: true)
                return
            }
            let width = max(1, collection.bounds.width)
            while let id = deferredMeasureIDs.first {
                deferredMeasureIDs.removeFirst()
                guard heights[id] == nil, let item = lookup[id] else { continue }
                heights[id] = measuredHeight(item, width: width)
                break
            }
            scheduleDeferredHeightMeasurement()
        }

        private func measuredHeight(_ item: Item, width: CGFloat) -> CGFloat {
            if let nativeHeight, let height = nativeHeight(item, width) {
                return max(1, height)
            }
            let host = UIHostingController(
                rootView: AnyView(row(item).frame(width: width))
            )
            host.view.backgroundColor = .clear
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: 240)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            let size = host.sizeThatFits(
                in: CGSize(width: width, height: .greatestFiniteMagnitude)
            )
            return max(1, ceil(size.height.isFinite ? size.height : 240))
        }

        func takeWarmHost(_ id: Item.ID,
                          signature: String) -> UIHostingController<AnyView>? {
            guard let cached = warmHosts[id],
                  cached.signature == signature else {
                warmHosts.removeValue(forKey: id)
                return nil
            }
            return warmHosts.removeValue(forKey: id)?.host
        }

        private func prewarm(_ ids: [Item.ID], maxCount: Int = 8) {
            guard !ids.isEmpty else { return }
            let width = max(1, collection?.bounds.width ?? UIScreen.main.bounds.width)
            let requested = Set(ids)
            for id in ids.prefix(max(1, maxCount)) {
                guard warmHosts[id] == nil,
                      let item = lookup[id],
                      let signature = signatures[id],
                      let rootView = rootView(for: item) else { continue }
                let host = UIHostingController(rootView: rootView)
                host.view.backgroundColor = .clear
                host.view.frame = CGRect(x: 0, y: 0, width: width, height: 240)
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                _ = host.sizeThatFits(
                    in: CGSize(width: width, height: .greatestFiniteMagnitude)
                )
                warmHosts[id] = (signature, host)
            }
            if warmHosts.count > 64 {
                for id in Array(warmHosts.keys) where !requested.contains(id) {
                    warmHosts.removeValue(forKey: id)
                    if warmHosts.count <= 48 { break }
                }
            }
        }

        private func enqueueWarm(_ ids: [Item.ID]) {
            guard !ids.isEmpty else { return }
            let known = Set(deferredWarmIDs)
            deferredWarmIDs.append(contentsOf: ids.filter { !known.contains($0) })
            if deferredWarmIDs.count > 80 {
                deferredWarmIDs.removeFirst(deferredWarmIDs.count - 80)
            }
        }

        private func drainDeferredWarmup() {
            guard !deferredWarmIDs.isEmpty,
                  let collection,
                  !collection.isDragging,
                  !collection.isTracking,
                  !collection.isDecelerating else { return }
            let ids = deferredWarmIDs
            deferredWarmIDs.removeAll(keepingCapacity: true)
            prewarm(ids, maxCount: 12)
        }

        func rootView(for item: Item) -> AnyView? {
            AnyView(
                row(item)
                    .frame(maxWidth: .infinity, alignment: .top)
            )
        }

        func collectionView(_ collectionView: UICollectionView,
                            prefetchItemsAt indexPaths: [IndexPath]) {
            let ids = indexPaths.compactMap { indexPath -> Item.ID? in
                guard indexPath.item >= 0, indexPath.item < order.count else { return nil }
                return order[indexPath.item]
            }
            if collectionView.isDragging || collectionView.isTracking
                || collectionView.isDecelerating {
                enqueueWarm(ids)
            } else {
                prewarm(ids, maxCount: 8)
            }
        }

        func collectionView(_ collectionView: UICollectionView,
                            cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {}

        private func flush() {
            guard let pending else { return }
            self.pending = nil
            apply(pending, animated: false)
        }
    }
}
