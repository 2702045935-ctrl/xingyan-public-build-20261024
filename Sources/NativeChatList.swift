import SwiftUI
import UIKit

struct NativeChatList<Item: Identifiable & Equatable, Row: View>: UIViewControllerRepresentable
where Item.ID: Hashable {
    let items: [Item]
    let height: (Item) -> CGFloat
    let nativeRow: ((Item) -> NativeChatRowConfiguration?)?
    let onZoneChange: (Int) -> Void
    let onRefresh: () -> Void
    @ViewBuilder let row: (Item) -> Row

    func makeCoordinator() -> Coordinator {
        Coordinator(onZoneChange: onZoneChange,
                    onRefresh: onRefresh,
                    height: height,
                    nativeRow: nativeRow,
                    row: row)
    }

    func makeUIViewController(context: Context) -> UICollectionViewController {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero
        layout.estimatedItemSize = .zero

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
        collection.allowsSelection = false
        collection.delegate = context.coordinator

        let registration = UICollectionView.CellRegistration<UICollectionViewCell, Item.ID> {
            [weak coordinator = context.coordinator] cell, _, id in
            guard let coordinator, let entry = coordinator.lookup[id] else { return }
            cell.contentConfiguration = UIHostingConfiguration {
                coordinator.row(entry)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .margins(.all, 0)
            .background(.clear)
            cell.backgroundConfiguration = .clear()
            cell.clipsToBounds = true
        }
        let nativeRegistration = UICollectionView.CellRegistration<NativeChatRowCell, Item.ID> {
            cell, _, _ in
            cell.backgroundConfiguration = .clear()
            cell.backgroundColor = .clear
        }

        let dataSource = UICollectionViewDiffableDataSource<Int, Item.ID>(
            collectionView: collection
        ) { collectionView, indexPath, id in
            if let entry = context.coordinator.lookup[id],
               let configuration = context.coordinator.nativeRow?(entry) {
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

        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator,
                          action: #selector(Coordinator.refreshPulled(_:)),
                          for: .valueChanged)
        collection.refreshControl = refresh
        return controller
    }

    func updateUIViewController(_ controller: UICollectionViewController,
                                context: Context) {
        context.coordinator.row = row
        context.coordinator.height = height
        context.coordinator.nativeRow = nativeRow
        context.coordinator.onZoneChange = onZoneChange
        context.coordinator.onRefresh = onRefresh
        context.coordinator.apply(items, animated: false)
    }

    final class Coordinator: NSObject, UICollectionViewDelegateFlowLayout {
        var lookup: [Item.ID: Item] = [:]
        var row: (Item) -> Row
        var height: (Item) -> CGFloat
        var nativeRow: ((Item) -> NativeChatRowConfiguration?)?
        var onZoneChange: (Int) -> Void
        var onRefresh: () -> Void
        weak var collection: UICollectionView?
        var dataSource: UICollectionViewDiffableDataSource<Int, Item.ID>?
        private var order: [Item.ID] = []
        private var lastZone = -1
        private var pendingItems: [Item]?
        private var applyGeneration = 0

        init(onZoneChange: @escaping (Int) -> Void,
             onRefresh: @escaping () -> Void,
             height: @escaping (Item) -> CGFloat,
             nativeRow: ((Item) -> NativeChatRowConfiguration?)?,
             row: @escaping (Item) -> Row) {
            self.onZoneChange = onZoneChange
            self.onRefresh = onRefresh
            self.height = height
            self.nativeRow = nativeRow
            self.row = row
            super.init()
        }

        func apply(_ next: [Item], animated: Bool) {
            guard let dataSource, let collection else { return }
            /*
             * Diffable apply 会异步重排 cell。滚动过程中继续换快照，系统会把当前
             * 视口推进到错误位置，表现就是会话页突然往下掉。用户手指还在屏幕上时
             * 只记下最新数据，等滚动结束再一次性合并。
             */
            if !order.isEmpty && (collection.isDragging || collection.isDecelerating) {
                pendingItems = next
                return
            }
            let nextLookup = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })
            let nextOrder = next.map(\.id)
            if nextOrder == order && next.allSatisfy({ lookup[$0.id] == $0 }) {
                pendingItems = nil
                return
            }
            let reload = next.compactMap { item -> Item.ID? in
                guard let old = lookup[item.id] else { return nil }
                return old == item ? nil : item.id
            }
            let previousOffset = collection.contentOffset
            applyGeneration += 1
            let generation = applyGeneration
            lookup = nextLookup

            var snapshot = NSDiffableDataSourceSnapshot<Int, Item.ID>()
            snapshot.appendSections([0])
            snapshot.appendItems(nextOrder, toSection: 0)
            if !reload.isEmpty {
                snapshot.reloadItems(reload)
            }
            order = nextOrder
            pendingItems = nil
            dataSource.apply(snapshot, animatingDifferences: animated) {
                guard generation == self.applyGeneration,
                      self.collection === collection,
                      !collection.isTracking,
                      !collection.isDragging,
                      !collection.isDecelerating else { return }
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

        func collectionView(_ collectionView: UICollectionView,
                            layout collectionViewLayout: UICollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> CGSize {
            let resolvedId = dataSource?.itemIdentifier(for: indexPath)
            let fallbackId = indexPath.item >= 0 && indexPath.item < order.count
                ? order[indexPath.item] : nil
            guard let id = resolvedId ?? fallbackId,
                  let item = lookup[id] else { return .zero }
            let width = max(0,
                            collectionView.bounds.width
                            - collectionView.adjustedContentInset.left
                            - collectionView.adjustedContentInset.right)
            return CGSize(width: width, height: max(1, height(item)))
        }

        @objc func refreshPulled(_ sender: UIRefreshControl) {
            onRefresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                sender.endRefreshing()
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let y = scrollView.contentOffset.y
            let zone: Int
            if y < 1 { zone = 0 }
            else if y <= 8 { zone = 1 }
            else if y <= 14 { zone = 2 }
            else { zone = 3 }
            guard zone != lastZone else { return }
            lastZone = zone
            DispatchQueue.main.async { [weak self] in
                self?.onZoneChange(zone)
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            /* 让正在等待的异步布局完成回调失效，不能把用户的拖动位置写回旧值。 */
            applyGeneration += 1
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView,
                                      willDecelerate decelerate: Bool) {
            if !decelerate { flushPendingItems() }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            flushPendingItems()
        }

        private func flushPendingItems() {
            guard let pendingItems else { return }
            self.pendingItems = nil
            apply(pendingItems, animated: false)
        }
    }
}
