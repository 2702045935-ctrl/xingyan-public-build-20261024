import SwiftUI
import UIKit

struct NativeStaticItem: Identifiable, Equatable {
    let id: String
    let signature: String
}

struct NativeStaticList<Item: Identifiable & Equatable, Row: View>: UIViewControllerRepresentable
where Item.ID: Hashable {
    let items: [Item]
    let signature: (Item) -> String
    @ViewBuilder let row: (Item) -> Row

    func makeCoordinator() -> Coordinator {
        Coordinator(signature: signature, row: row)
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
        collection.showsVerticalScrollIndicator = false
        collection.contentInsetAdjustmentBehavior = .never
        collection.keyboardDismissMode = .interactive
        collection.delaysContentTouches = false
        collection.canCancelContentTouches = true
        collection.scrollsToTop = true
        collection.isPrefetchingEnabled = false
        collection.delegate = context.coordinator

        let registration = UICollectionView.CellRegistration<UICollectionViewCell, Item.ID> {
            [weak coordinator = context.coordinator] cell, _, id in
            guard let coordinator, let item = coordinator.lookup[id] else { return }
            cell.contentConfiguration = UIHostingConfiguration {
                coordinator.row(item)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .margins(.all, 0)
            .background(.clear)
            cell.backgroundConfiguration = .clear()
            cell.backgroundColor = .clear
            cell.clipsToBounds = true
        }

        let dataSource = UICollectionViewDiffableDataSource<Int, Item.ID>(
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
        context.coordinator.signature = signature
        context.coordinator.apply(items, animated: false)
    }

    final class Coordinator: NSObject, UICollectionViewDelegateFlowLayout {
        var lookup: [Item.ID: Item] = [:]
        var row: (Item) -> Row
        var signature: (Item) -> String
        weak var collection: UICollectionView?
        var dataSource: UICollectionViewDiffableDataSource<Int, Item.ID>?
        private var order: [Item.ID] = []
        private var signatures: [Item.ID: String] = [:]
        private var heights: [Item.ID: CGFloat] = [:]
        private var width: CGFloat = 0
        private var pending: [Item]?
        private var applyGeneration = 0

        init(signature: @escaping (Item) -> String,
             row: @escaping (Item) -> Row) {
            self.signature = signature
            self.row = row
            super.init()
        }

        func apply(_ next: [Item], animated: Bool) {
            guard let collection, let dataSource else { return }
            if !order.isEmpty && (collection.isDragging || collection.isDecelerating) {
                pending = next
                return
            }
            let nextOrder = next.map(\.id)
            let nextSignatures = Dictionary(uniqueKeysWithValues: next.map {
                ($0.id, signature($0))
            })
            if nextOrder == order && nextSignatures == signatures { return }
            let nextLookup = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })
            let changed = nextOrder.filter { signatures[$0] != nextSignatures[$0] }
            for id in changed { heights[id] = nil }
            if collection.bounds.width > 1,
               abs(collection.bounds.width - width) > 0.5 {
                width = collection.bounds.width
                heights.removeAll(keepingCapacity: true)
            }
            lookup = nextLookup
            signatures = nextSignatures
            order = nextOrder
            pending = nil
            premeasure(nextOrder)
            let previousOffset = collection.contentOffset
            applyGeneration += 1
            let generation = applyGeneration
            var snapshot = NSDiffableDataSourceSnapshot<Int, Item.ID>()
            snapshot.appendSections([0])
            snapshot.appendItems(nextOrder)
            if !changed.isEmpty { snapshot.reloadItems(changed) }
            collection.collectionViewLayout.invalidateLayout()
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
            if !decelerate { flush() }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            flush()
        }

        private func premeasure(_ ids: [Item.ID]) {
            let measured = collection?.bounds.width ?? 0
            let width = measured > 1 ? measured : UIScreen.main.bounds.width
            guard width > 1 else { return }
            for id in ids where heights[id] == nil {
                guard let item = lookup[id] else { continue }
                heights[id] = measuredHeight(item, width: width)
            }
        }

        private func measuredHeight(_ item: Item, width: CGFloat) -> CGFloat {
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

        private func flush() {
            guard let pending else { return }
            self.pending = nil
            apply(pending, animated: false)
        }
    }
}
