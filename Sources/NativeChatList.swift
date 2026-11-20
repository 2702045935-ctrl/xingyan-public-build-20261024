import SwiftUI
import UIKit

final class NativeChatListScrollRegistry {
    static let shared = NativeChatListScrollRegistry()
    weak var chats: UIScrollView?
}

private enum NativeChatCellIdentifier {
    static let nativeRow = "NativeChatRowCell"
    static let hostingRow = "NativeChatHostingCell"
}

private func nativeChatSwipeText(_ zh: String, _ en: String, _ ru: String) -> String {
    if Lang.isRussian { return ru }
    if Lang.isEnglish { return en }
    return zh
}

/// 会话页使用 UITableView 的系统 edit action。UITableView 的滑动识别比
/// 自定义 collection cell 更稳定，点击、高亮、预取和行高仍使用原生列表实现。
struct NativeChatList<Item: Identifiable & Equatable, Row: View>: UIViewControllerRepresentable
where Item.ID: Hashable {
    let items: [Item]
    let height: (Item) -> CGFloat
    let nativeRow: ((Item) -> NativeChatRowConfiguration?)?
    let onScrollStateChange: (Bool) -> Void
    let onOffsetChange: (CGFloat) -> Void
    let onZoneChange: (Int) -> Void
    let onApproachingStart: () -> Void
    let onApproachingEnd: () -> Void
    let onRefresh: () -> Void
    let allowInsertionDuringScroll: Bool
    @ViewBuilder let row: (Item) -> Row

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollStateChange: onScrollStateChange,
                    onOffsetChange: onOffsetChange,
                    onZoneChange: onZoneChange,
                    onApproachingStart: onApproachingStart,
                    onApproachingEnd: onApproachingEnd,
                    onRefresh: onRefresh,
                    allowInsertionDuringScroll: allowInsertionDuringScroll,
                    height: height,
                    nativeRow: nativeRow,
                    row: row)
    }

    func makeUIViewController(context: Context) -> UITableViewController {
        let controller = UITableViewController(style: .plain)
        controller.view.backgroundColor = .clear
        let table = controller.tableView!
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 72
        table.alwaysBounceVertical = true
        table.alwaysBounceHorizontal = false
        table.showsVerticalScrollIndicator = false
        table.contentInsetAdjustmentBehavior = .never
        table.keyboardDismissMode = .interactive
        table.delaysContentTouches = false
        table.canCancelContentTouches = true
        table.scrollsToTop = true
        table.allowsSelection = true
        table.allowsMultipleSelection = false
        table.sectionHeaderTopPadding = 0
        if #available(iOS 26.0, *) {
            table.topEdgeEffect.style = .hard
            table.topEdgeEffect.isHidden = false
            table.bottomEdgeEffect.isHidden = true
        }
        NativeChatListScrollRegistry.shared.chats = table
        table.delegate = context.coordinator
        table.register(NativeChatRowCell.self,
                       forCellReuseIdentifier: NativeChatCellIdentifier.nativeRow)
        table.register(UITableViewCell.self,
                       forCellReuseIdentifier: NativeChatCellIdentifier.hostingRow)

        let dataSource = UITableViewDiffableDataSource<Int, Item.ID>(
            tableView: table
        ) { tableView, indexPath, id in
            let coordinator = context.coordinator
            if let entry = coordinator.lookup[id],
               let configuration = coordinator.nativeRow?(entry) {
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: NativeChatCellIdentifier.nativeRow,
                    for: indexPath
                ) as! NativeChatRowCell
                cell.configure(configuration)
                return cell
            }
            let cell = tableView.dequeueReusableCell(
                withIdentifier: NativeChatCellIdentifier.hostingRow,
                for: indexPath
            )
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.selectionStyle = .none
            if let entry = coordinator.lookup[id] {
                cell.contentConfiguration = UIHostingConfiguration {
                    coordinator.row(entry)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .margins(.all, 0)
                .background(.clear)
            }
            return cell
        }
        context.coordinator.dataSource = dataSource
        context.coordinator.table = table
        context.coordinator.apply(items, animated: false)

        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator,
                          action: #selector(Coordinator.refreshPulled(_:)),
                          for: .valueChanged)
        table.refreshControl = refresh
        return controller
    }

    func updateUIViewController(_ controller: UITableViewController,
                                context: Context) {
        context.coordinator.row = row
        context.coordinator.height = height
        context.coordinator.nativeRow = nativeRow
        context.coordinator.onScrollStateChange = onScrollStateChange
        context.coordinator.onOffsetChange = onOffsetChange
        context.coordinator.onZoneChange = onZoneChange
        context.coordinator.onApproachingStart = onApproachingStart
        context.coordinator.onApproachingEnd = onApproachingEnd
        context.coordinator.onRefresh = onRefresh
        context.coordinator.allowInsertionDuringScroll = allowInsertionDuringScroll
        context.coordinator.apply(items, animated: false)
    }

    final class Coordinator: NSObject, UITableViewDelegate {
        var lookup: [Item.ID: Item] = [:]
        var row: (Item) -> Row
        var height: (Item) -> CGFloat
        var nativeRow: ((Item) -> NativeChatRowConfiguration?)?
        var onScrollStateChange: (Bool) -> Void
        var onOffsetChange: (CGFloat) -> Void
        var onZoneChange: (Int) -> Void
        var onApproachingStart: () -> Void
        var onApproachingEnd: () -> Void
        var onRefresh: () -> Void
        var allowInsertionDuringScroll: Bool
        weak var table: UITableView?
        var dataSource: UITableViewDiffableDataSource<Int, Item.ID>?
        private var order: [Item.ID] = []
        private var lastZone = -1
        private var pendingZone = 0
        private var zoneFlushScheduled = false
        private var lastScrollActive = false
        private var pendingItems: [Item]?
        private var applyGeneration = 0
        private var endRequestInFlight = false
        private var startRequestInFlight = false
        private var appliedItemCount = 0
        private var layoutObservers: [NSObjectProtocol] = []

        init(onScrollStateChange: @escaping (Bool) -> Void,
             onOffsetChange: @escaping (CGFloat) -> Void,
             onZoneChange: @escaping (Int) -> Void,
             onApproachingStart: @escaping () -> Void,
             onApproachingEnd: @escaping () -> Void,
             onRefresh: @escaping () -> Void,
             allowInsertionDuringScroll: Bool,
             height: @escaping (Item) -> CGFloat,
             nativeRow: ((Item) -> NativeChatRowConfiguration?)?,
             row: @escaping (Item) -> Row) {
            self.onScrollStateChange = onScrollStateChange
            self.onOffsetChange = onOffsetChange
            self.onZoneChange = onZoneChange
            self.onApproachingStart = onApproachingStart
            self.onApproachingEnd = onApproachingEnd
            self.onRefresh = onRefresh
            self.allowInsertionDuringScroll = allowInsertionDuringScroll
            self.height = height
            self.nativeRow = nativeRow
            self.row = row
            super.init()
            let center = NotificationCenter.default
            for name in [UIContentSizeCategory.didChangeNotification,
                         Notification.Name.chrisUIPrefsChanged] {
                layoutObservers.append(center.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.refreshMetrics()
                })
            }
        }

        deinit {
            let center = NotificationCenter.default
            layoutObservers.forEach { center.removeObserver($0) }
        }

        func apply(_ next: [Item], animated: Bool) {
            guard let dataSource, let table else { return }
            let isScrolling = table.isDragging || table.isTracking || table.isDecelerating
            if !order.isEmpty, isScrolling {
                let oldCount = order.count
                let sameBoundaries = next.count >= oldCount
                    && next.first?.id == order.first
                    && next[oldCount - 1].id == order[oldCount - 1]
                if next.count == oldCount {
                    /* 滚动期间不为未变化的 13k+ 行做全量相等比较。
                       可见行状态变化在手指停止后统一 flush。 */
                    pendingItems = next
                    return
                }
                if allowInsertionDuringScroll,
                   next.count > oldCount,
                   sameBoundaries,
                   appendPureTail(next, from: oldCount, keepPending: true) {
                    return
                }
                pendingItems = next
                return
            }
            let nextOrder = next.map(\.id)
            let isPureAppend = !order.isEmpty
                && next.count > order.count
                && next.prefix(order.count).allSatisfy { lookup[$0.id] == $0 }
            if isPureAppend {
                _ = appendPureTail(next, from: order.count, keepPending: false)
                return
            }
            let nextLookup = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })
            if nextOrder == order && next.allSatisfy({ lookup[$0.id] == $0 }) {
                pendingItems = nil
                return
            }
            var commonPrefix = 0
            while commonPrefix < order.count,
                  commonPrefix < nextOrder.count,
                  order[commonPrefix] == nextOrder[commonPrefix] {
                commonPrefix += 1
            }
            let offsetAdjustment: CGFloat
            if commonPrefix < order.count,
               commonPrefix < nextOrder.count,
               let oldIDPosition = nextOrder.firstIndex(of: order[commonPrefix]),
               oldIDPosition > commonPrefix {
                offsetAdjustment = nextOrder[commonPrefix..<oldIDPosition].reduce(CGFloat(0)) {
                    partial, id in
                    partial + (nextLookup[id].map { height($0) } ?? 0)
                }
            } else if commonPrefix < order.count,
                      commonPrefix < nextOrder.count,
                      let newIDPosition = order.firstIndex(of: nextOrder[commonPrefix]),
                      newIDPosition > commonPrefix {
                offsetAdjustment = -order[commonPrefix..<newIDPosition].reduce(CGFloat(0)) {
                    partial, id in
                    partial + (lookup[id].map { height($0) } ?? 0)
                }
            } else {
                offsetAdjustment = 0
            }
            let reload = next.compactMap { item -> Item.ID? in
                guard let old = lookup[item.id] else { return nil }
                return old == item ? nil : item.id
            }
            let previousOffset = table.contentOffset
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
            appliedItemCount = nextOrder.count
            endRequestInFlight = false
            pendingItems = nil
            dataSource.apply(snapshot, animatingDifferences: animated) {
                guard generation == self.applyGeneration,
                      self.table === table,
                      !table.isTracking,
                      !table.isDragging,
                      !table.isDecelerating else { return }
                table.layoutIfNeeded()
                let minimumY = -table.adjustedContentInset.top
                let maximumY = max(
                    minimumY,
                    table.contentSize.height - table.bounds.height
                        + table.adjustedContentInset.bottom
                )
                var target = previousOffset
                target.y += offsetAdjustment
                target.y = min(max(target.y, minimumY), maximumY)
                table.setContentOffset(target, animated: false)
            }
        }

        @discardableResult
        private func appendPureTail(_ next: [Item],
                                    from start: Int,
                                    keepPending: Bool) -> Bool {
            guard start >= 0, start < next.count,
                  let dataSource, let table else { return false }
            let added = Array(next[start...])
            let addedIDs = added.map(\.id)
            let previousOffset = table.contentOffset
            for item in added { lookup[item.id] = item }
            order.append(contentsOf: addedIDs)
            appliedItemCount = order.count
            endRequestInFlight = false
            pendingItems = keepPending ? next : nil
            applyGeneration += 1
            let generation = applyGeneration
            var snapshot = dataSource.snapshot()
            snapshot.appendItems(addedIDs, toSection: 0)
            dataSource.apply(snapshot, animatingDifferences: false) {
                guard generation == self.applyGeneration,
                      self.table === table,
                      !table.isTracking,
                      !table.isDragging,
                      !table.isDecelerating else { return }
                table.layoutIfNeeded()
                let minimumY = -table.adjustedContentInset.top
                let maximumY = max(
                    minimumY,
                    table.contentSize.height - table.bounds.height
                        + table.adjustedContentInset.bottom
                )
                var target = previousOffset
                target.y = min(max(target.y, minimumY), maximumY)
                table.setContentOffset(target, animated: false)
            }
            return true
        }

        func tableView(_ tableView: UITableView,
                       heightForRowAt indexPath: IndexPath) -> CGFloat {
            let resolvedId = dataSource?.itemIdentifier(for: indexPath)
            let fallbackId = indexPath.row >= 0 && indexPath.row < order.count
                ? order[indexPath.row] : nil
            guard let id = resolvedId ?? fallbackId,
                  let item = lookup[id] else { return 1 }
            return max(1, height(item))
        }

        @objc func refreshPulled(_ sender: UIRefreshControl) {
            onRefresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                sender.endRefreshing()
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            publishScrollState(scrollView.isDragging
                               || scrollView.isTracking
                               || scrollView.isDecelerating)
            let y = scrollView.contentOffset.y
            onOffsetChange(max(0, y))
            let remaining = scrollView.contentSize.height
                - scrollView.bounds.height
                - y
                + scrollView.adjustedContentInset.bottom
            let fromTop = y + scrollView.adjustedContentInset.top
            /* 会话列表按“一页跑道”提前补下一页。触发点保持两屏半左右，
               让 320 行夹具在用户接近尾部前完成追加；endRequestInFlight
               保证同一时间最多只有一个下一页请求，不会插两页。 */
            let prefetchLead = max(2_400, scrollView.bounds.height * 2.5)
            if !startRequestInFlight,
               !order.isEmpty,
               (scrollView.isDragging || scrollView.isDecelerating),
               fromTop < max(1_600, scrollView.bounds.height * 1.5) {
                startRequestInFlight = true
                DispatchQueue.main.async { [weak self] in
                    self?.onApproachingStart()
                }
            }
            if !endRequestInFlight,
               !order.isEmpty,
               (scrollView.isDragging || scrollView.isDecelerating),
               remaining < prefetchLead {
                endRequestInFlight = true
                DispatchQueue.main.async { [weak self] in
                    self?.onApproachingEnd()
                }
            }
            let zone: Int
            if y < 1 { zone = 0 }
            else if y <= 8 { zone = 1 }
            else if y <= 14 { zone = 2 }
            else { zone = 3 }
            guard zone != lastZone else { return }
            lastZone = zone
            pendingZone = zone
            guard !zoneFlushScheduled else { return }
            zoneFlushScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.zoneFlushScheduled = false
                self.onZoneChange(self.pendingZone)
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            publishScrollState(true)
            applyGeneration += 1
            NotificationCenter.default.post(name: .chrisRowSwipe, object: nil)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView,
                                      willDecelerate decelerate: Bool) {
            if decelerate {
                publishScrollState(true)
            } else {
                startRequestInFlight = false
                publishScrollState(false)
                flushPendingItems()
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            startRequestInFlight = false
            publishScrollState(false)
            flushPendingItems()
        }

        func tableView(_ tableView: UITableView,
                       didSelectRowAt indexPath: IndexPath) {
            tableView.deselectRow(at: indexPath, animated: false)
            guard let id = dataSource?.itemIdentifier(for: indexPath),
                  let entry = lookup[id],
                  let configuration = nativeRow?(entry) else { return }
            if let cell = tableView.cellForRow(at: indexPath) as? NativeChatRowCell,
               cell.openFromSelection() {
                return
            }
            configuration.onOpen()
        }

        func tableView(_ tableView: UITableView,
                       didHighlightRowAt indexPath: IndexPath) {
            (tableView.cellForRow(at: indexPath) as? NativeChatRowCell)?
                .setTouchPressed(true)
        }

        func tableView(_ tableView: UITableView,
                       didUnhighlightRowAt indexPath: IndexPath) {
            (tableView.cellForRow(at: indexPath) as? NativeChatRowCell)?
                .setTouchPressed(false)
        }

        func tableView(
            _ tableView: UITableView,
            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
        ) -> UISwipeActionsConfiguration? {
            guard let id = dataSource?.itemIdentifier(for: indexPath),
                  let entry = lookup[id],
                  let configuration = nativeRow?(entry) else { return nil }
            var actions: [UIContextualAction] = []
            let deleteAction = UIContextualAction(
                style: .destructive,
                title: nativeChatSwipeText("删除", "Delete", "Удалить")
            ) { _, _, complete in
                configuration.onDelete()
                complete(true)
            }
            deleteAction.image = UIImage(systemName: "trash.fill")
            deleteAction.backgroundColor = .systemRed
            actions.append(deleteAction)

            let hideAction = UIContextualAction(
                style: .normal,
                title: nativeChatSwipeText("不显示", "Hide", "Скрыть")
            ) { _, _, complete in
                configuration.onHide()
                complete(true)
            }
            hideAction.image = UIImage(systemName: "eye.slash.fill")
            hideAction.backgroundColor = .systemGray
            actions.append(hideAction)

            if !configuration.isManuallyUnread {
                let unreadAction = UIContextualAction(
                    style: .normal,
                    title: nativeChatSwipeText(
                        "标为未读",
                        "Mark unread",
                        "Не прочитано"
                    )
                ) { _, _, complete in
                    configuration.onUnread()
                    complete(true)
                }
                unreadAction.image = UIImage(systemName: "bell.fill")
                unreadAction.backgroundColor = .systemBlue
                actions.append(unreadAction)
            }

            let swipe = UISwipeActionsConfiguration(actions: actions)
            swipe.performsFirstActionWithFullSwipe = true
            return swipe
        }

        private func publishScrollState(_ active: Bool) {
            guard active != lastScrollActive else { return }
            lastScrollActive = active
            DispatchQueue.main.async { [weak self] in
                self?.onScrollStateChange(active)
            }
        }

        private func refreshMetrics() {
            guard let table, let dataSource else { return }
            NativeChatRowMetrics.invalidateScaleCache()
            table.beginUpdates()
            table.endUpdates()
            var snapshot = dataSource.snapshot()
            guard !snapshot.itemIdentifiers.isEmpty else { return }
            snapshot.reloadItems(snapshot.itemIdentifiers)
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        private func flushPendingItems() {
            guard let pendingItems else { return }
            self.pendingItems = nil
            apply(pendingItems, animated: false)
        }
    }
}
