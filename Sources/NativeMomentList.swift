import SwiftUI
import UIKit

enum NativeMomentFeedKind: Hashable {
    case cover
    case moment
    case footer
}

struct NativeMomentFeedItem: Identifiable, Equatable {
    let id: String
    let kind: NativeMomentFeedKind
    let moment: Moment?
    let day: String?
}

struct NativeMomentList<Row: View>: UIViewControllerRepresentable {
    let items: [NativeMomentFeedItem]
    let refreshing: Bool
    let onRefresh: () -> Void
    let onScrollOffset: (CGFloat) -> Void
    let onScrollActivity: (Bool) -> Void
    let onNearEnd: () -> Void
    let nativeRow: ((NativeMomentFeedItem, CGFloat) -> NativeMomentRowConfiguration?)?
    @ViewBuilder let row: (NativeMomentFeedItem) -> Row

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollOffset: onScrollOffset,
                    onScrollActivity: onScrollActivity,
                    onNearEnd: onNearEnd,
                    onRefresh: onRefresh,
                    nativeRow: nativeRow,
                    row: row)
    }

    func makeUIViewController(context: Context) -> UICollectionViewController {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.estimatedItemSize = .zero
        layout.sectionInset = .zero

        let controller = UICollectionViewController(collectionViewLayout: layout)
        controller.view.backgroundColor = .clear
        let collection = controller.collectionView!
        collection.backgroundColor = .clear
        collection.alwaysBounceVertical = true
        collection.alwaysBounceHorizontal = false
        collection.isDirectionalLockEnabled = true
        collection.showsVerticalScrollIndicator = false
        collection.contentInsetAdjustmentBehavior = .never
        collection.keyboardDismissMode = .interactive
        collection.delaysContentTouches = false
        collection.canCancelContentTouches = true
        collection.scrollsToTop = true
        collection.isPrefetchingEnabled = true
        collection.delegate = context.coordinator
        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = UIColor(C.green)
        refreshControl.addTarget(context.coordinator,
                                 action: #selector(Coordinator.refreshRequested),
                                 for: .valueChanged)
        collection.refreshControl = refreshControl
        context.coordinator.refreshControl = refreshControl
        context.coordinator.setRefreshing(refreshing)

        let registration = UICollectionView.CellRegistration<UICollectionViewCell, String> {
            [weak coordinator = context.coordinator] cell, _, id in
            guard let coordinator, let entry = coordinator.lookup[id] else { return }
            cell.contentConfiguration = UIHostingConfiguration {
                coordinator.row(entry)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .margins(.all, 0)
            .background(.clear)
            cell.backgroundConfiguration = .clear()
            cell.backgroundColor = .clear
            cell.clipsToBounds = true
        }
        let nativeRegistration = UICollectionView.CellRegistration<NativeMomentFeedCell, String> {
            cell, _, _ in
            cell.backgroundConfiguration = .clear()
            cell.backgroundColor = .clear
        }

        let dataSource = UICollectionViewDiffableDataSource<Int, String>(
            collectionView: collection
        ) { collectionView, indexPath, id in
            let width = collectionView.bounds.width > 1
                ? collectionView.bounds.width
                : UIScreen.main.bounds.width
            if let entry = context.coordinator.lookup[id],
               let configuration = context.coordinator.nativeRow?(
                   entry, width
               ) {
                let cell = collectionView.dequeueConfiguredReusableCell(
                    using: nativeRegistration,
                    for: indexPath,
                    item: id
                )
                cell.configure(configuration)
                return cell
            }
            return collectionView.dequeueConfiguredReusableCell(
                using: registration,
                for: indexPath,
                item: id
            )
        }
        context.coordinator.dataSource = dataSource
        context.coordinator.collection = collection
        context.coordinator.apply(items, animated: false)
        return controller
    }

    func updateUIViewController(_ controller: UICollectionViewController,
                                context: Context) {
        context.coordinator.row = row
        context.coordinator.onRefresh = onRefresh
        context.coordinator.onScrollOffset = onScrollOffset
        context.coordinator.onScrollActivity = onScrollActivity
        context.coordinator.onNearEnd = onNearEnd
        context.coordinator.nativeRow = nativeRow
        context.coordinator.setRefreshing(refreshing)
        context.coordinator.apply(items, animated: false)
    }

    final class Coordinator: NSObject, UICollectionViewDelegateFlowLayout {
        var lookup: [String: NativeMomentFeedItem] = [:]
        var row: (NativeMomentFeedItem) -> Row
        var onScrollOffset: (CGFloat) -> Void
        var onScrollActivity: (Bool) -> Void
        var onNearEnd: () -> Void
        var onRefresh: () -> Void
        var nativeRow: ((NativeMomentFeedItem, CGFloat) -> NativeMomentRowConfiguration?)?
        weak var collection: UICollectionView?
        weak var refreshControl: UIRefreshControl?
        var dataSource: UICollectionViewDiffableDataSource<Int, String>?
        private var order: [String] = []
        private var pendingItems: [NativeMomentFeedItem]?
        private var applyGeneration = 0
        private var lastOffset: CGFloat = .greatestFiniteMagnitude
        private var nearEndArmed = true
        private var heights: [String: CGFloat] = [:]
        private var measuredWidth: CGFloat = 0

        init(onScrollOffset: @escaping (CGFloat) -> Void,
             onScrollActivity: @escaping (Bool) -> Void,
             onNearEnd: @escaping () -> Void,
             onRefresh: @escaping () -> Void,
             nativeRow: ((NativeMomentFeedItem, CGFloat) -> NativeMomentRowConfiguration?)?,
             row: @escaping (NativeMomentFeedItem) -> Row) {
            self.onScrollOffset = onScrollOffset
            self.onScrollActivity = onScrollActivity
            self.onNearEnd = onNearEnd
            self.onRefresh = onRefresh
            self.nativeRow = nativeRow
            self.row = row
            super.init()
        }

        func apply(_ next: [NativeMomentFeedItem], animated: Bool) {
            guard let dataSource, let collection else { return }
            let nextLookup = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })
            let nextOrder = next.map(\.id)
            if !order.isEmpty && (collection.isDragging || collection.isDecelerating) {
                let known = Set(order)
                let commonOrder = nextOrder.filter { known.contains($0) }
                if commonOrder != order {
                    pendingItems = next
                    return
                }
            }
            if nextOrder == order && next.allSatisfy({ lookup[$0.id] == $0 }) {
                pendingItems = nil
                return
            }
            let width = collection.bounds.width > 1
                ? collection.bounds.width
                : UIScreen.main.bounds.width
            if abs(width - measuredWidth) > 0.5 {
                measuredWidth = width
                heights.removeAll(keepingCapacity: true)
            }
            let reload = next.compactMap { item -> String? in
                guard let old = lookup[item.id] else { return nil }
                return old == item ? nil : item.id
            }
            for id in nextOrder where lookup[id] == nil {
                heights[id] = nil
            }
            for id in reload {
                heights[id] = nil
            }
            let previousOffset = collection.contentOffset
            applyGeneration += 1
            let generation = applyGeneration
            lookup = nextLookup
            prepareHeights(nextOrder, width: width)

            var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.appendSections([0])
            snapshot.appendItems(nextOrder, toSection: 0)
            if !reload.isEmpty {
                snapshot.reloadItems(reload)
            }
            order = nextOrder
            pendingItems = nil
            collection.collectionViewLayout.invalidateLayout()
            dataSource.apply(snapshot, animatingDifferences: animated) {
                guard generation == self.applyGeneration,
                      self.collection === collection,
                      !collection.isTracking,
                      !collection.isDragging,
                      !collection.isDecelerating else { return }
                let maximumY = max(
                    -collection.adjustedContentInset.top,
                    collection.contentSize.height - collection.bounds.height
                        + collection.adjustedContentInset.bottom
                )
                var target = previousOffset
                target.y = min(max(target.y, -collection.adjustedContentInset.top), maximumY)
                collection.setContentOffset(target, animated: false)
            }
        }

        func collectionView(_ collectionView: UICollectionView,
                            layout collectionViewLayout: UICollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> CGSize {
            let resolvedId = dataSource?.itemIdentifier(for: indexPath)
            let fallbackId = indexPath.item >= 0 && indexPath.item < order.count
                ? order[indexPath.item] : nil
            guard let id = resolvedId ?? fallbackId,
                  let item = lookup[id] else { return .zero }
            let width = max(1, collectionView.bounds.width)
            if abs(width - measuredWidth) > 0.5 {
                measuredWidth = width
                heights.removeAll(keepingCapacity: true)
            }
            if let height = heights[id], height > 0 {
                return CGSize(width: width, height: height)
            }
            if let configuration = nativeRow?(item, width) {
                let height = NativeMomentFeedCell.preferredHeight(configuration)
                heights[id] = height
                return CGSize(width: width, height: height)
            }
            let height = heights[id] ?? measuredHeight(item, width: width)
            heights[id] = height
            return CGSize(width: width, height: height)
        }

        private func measuredHeight(_ item: NativeMomentFeedItem,
                                    width: CGFloat) -> CGFloat {
            let hosted = UIHostingController(
                rootView: AnyView(
                    row(item)
                        .frame(width: width)
                )
            )
            hosted.view.backgroundColor = .clear
            hosted.view.frame = CGRect(x: 0, y: 0, width: width, height: 360)
            hosted.view.setNeedsLayout()
            hosted.view.layoutIfNeeded()
            let fitted = hosted.sizeThatFits(
                in: CGSize(width: width, height: .greatestFiniteMagnitude)
            )
            return max(1, ceil(fitted.height.isFinite ? fitted.height : 360))
        }

        private func prepareHeights(_ ids: [String], width: CGFloat) {
            for id in ids where heights[id] == nil {
                guard let item = lookup[id] else { continue }
                if let configuration = nativeRow?(item, width) {
                    heights[id] = NativeMomentFeedCell.preferredHeight(configuration)
                    continue
                }
                heights[id] = measuredHeight(item, width: width)
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let y = scrollView.contentOffset.y
            let quantized = (y / 2).rounded() * 2
            if abs(quantized - lastOffset) >= 2 {
                lastOffset = quantized
                onScrollOffset(y)
            }

            let remaining = scrollView.contentSize.height
                - scrollView.contentOffset.y - scrollView.bounds.height
            if remaining < 1200 {
                if nearEndArmed {
                    nearEndArmed = false
                    onNearEnd()
                }
            } else if remaining > 1500 {
                nearEndArmed = true
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            applyGeneration += 1
            onScrollActivity(true)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView,
                                      willDecelerate decelerate: Bool) {
            if !decelerate {
                onScrollActivity(false)
                flushPendingItems()
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            onScrollActivity(false)
            flushPendingItems()
        }

        @objc func refreshRequested() {
            onRefresh()
        }

        func setRefreshing(_ active: Bool) {
            guard let refreshControl else { return }
            if active, !refreshControl.isRefreshing {
                refreshControl.beginRefreshing()
            } else if !active, refreshControl.isRefreshing {
                refreshControl.endRefreshing()
            }
        }

        private func flushPendingItems() {
            guard let pendingItems else { return }
            self.pendingItems = nil
            apply(pendingItems, animated: false)
        }
    }
}
