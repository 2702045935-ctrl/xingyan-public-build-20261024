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
    let onScrollOffset: (CGFloat) -> Void
    let onScrollActivity: (Bool) -> Void
    let onNearEnd: () -> Void
    @ViewBuilder let row: (NativeMomentFeedItem) -> Row

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollOffset: onScrollOffset,
                    onScrollActivity: onScrollActivity,
                    onNearEnd: onNearEnd,
                    row: row)
    }

    func makeUIViewController(context: Context) -> UICollectionViewController {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(360)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .zero
        section.interGroupSpacing = 0
        let layout = UICollectionViewCompositionalLayout(section: section)
        layout.configuration.interSectionSpacing = 0

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

        let dataSource = UICollectionViewDiffableDataSource<Int, String>(
            collectionView: collection
        ) { collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(
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
        context.coordinator.onScrollOffset = onScrollOffset
        context.coordinator.onScrollActivity = onScrollActivity
        context.coordinator.onNearEnd = onNearEnd
        context.coordinator.apply(items, animated: false)
    }

    final class Coordinator: NSObject, UICollectionViewDelegate {
        var lookup: [String: NativeMomentFeedItem] = [:]
        var row: (NativeMomentFeedItem) -> Row
        var onScrollOffset: (CGFloat) -> Void
        var onScrollActivity: (Bool) -> Void
        var onNearEnd: () -> Void
        weak var collection: UICollectionView?
        var dataSource: UICollectionViewDiffableDataSource<Int, String>?
        private var order: [String] = []
        private var pendingItems: [NativeMomentFeedItem]?
        private var applyGeneration = 0
        private var lastOffset: CGFloat = .greatestFiniteMagnitude
        private var nearEndArmed = true

        init(onScrollOffset: @escaping (CGFloat) -> Void,
             onScrollActivity: @escaping (Bool) -> Void,
             onNearEnd: @escaping () -> Void,
             row: @escaping (NativeMomentFeedItem) -> Row) {
            self.onScrollOffset = onScrollOffset
            self.onScrollActivity = onScrollActivity
            self.onNearEnd = onNearEnd
            self.row = row
            super.init()
        }

        func apply(_ next: [NativeMomentFeedItem], animated: Bool) {
            guard let dataSource, let collection else { return }
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
            let reload = next.compactMap { item -> String? in
                guard let old = lookup[item.id] else { return nil }
                return old == item ? nil : item.id
            }
            let previousOffset = collection.contentOffset
            applyGeneration += 1
            let generation = applyGeneration
            lookup = nextLookup

            var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
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

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let y = scrollView.contentOffset.y
            let quantized = (y / 2).rounded() * 2
            if abs(quantized - lastOffset) >= 2 {
                lastOffset = quantized
                onScrollOffset(y)
            }

            let remaining = scrollView.contentSize.height
                - scrollView.contentOffset.y - scrollView.bounds.height
            if remaining < 680 {
                if nearEndArmed {
                    nearEndArmed = false
                    onNearEnd()
                }
            } else if remaining > 1000 {
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

        private func flushPendingItems() {
            guard let pendingItems else { return }
            self.pendingItems = nil
            apply(pendingItems, animated: false)
        }
    }
}
