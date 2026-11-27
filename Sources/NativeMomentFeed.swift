import SwiftUI
import UIKit

struct NativeMomentFeedItem {
    let id: String
    let moment: Moment
    let showsDayHeader: Bool
    let dayText: String
    let isFirst: Bool
    let isLast: Bool
}

/// Native scrolling kernel for the Moments timeline. The feed uses one
/// diffable data source for cell reuse, native prefetching, page consumption
/// and the cover header, so no SwiftUI list or on-appear paging path is needed.
struct NativeMomentFeed<Header: View>: UIViewControllerRepresentable {
    let moments: [Moment]
    let revision: Int
    let mineOnly: Bool
    let dayKey: String
    let headerHeight: CGFloat
    let collapseOffset: CGFloat
    let onScrollActive: (Bool) -> Void
    let onCollapseChange: (Bool) -> Void
    let onPullChange: (CGFloat) -> Void
    let onPullEnd: (CGFloat) -> Void
    let onApproachingEnd: () -> Void
    let actions: NativeMomentActions
    let stressText: String?
    let footerText: String?
    let footerWaiting: Bool
    let dayLabel: (Moment) -> String
    @ViewBuilder let header: (CGFloat) -> Header

    func makeCoordinator() -> Coordinator {
        Coordinator(
            moments: moments,
            revision: revision,
            mineOnly: mineOnly,
            dayKey: dayKey,
            headerHeight: headerHeight,
            collapseOffset: collapseOffset,
            onScrollActive: onScrollActive,
            onCollapseChange: onCollapseChange,
            onPullChange: onPullChange,
            onPullEnd: onPullEnd,
            onApproachingEnd: onApproachingEnd,
            actions: actions,
            stressText: stressText,
            footerText: footerText,
            footerWaiting: footerWaiting,
            dayLabel: dayLabel,
            header: header
        )
    }

    func makeUIViewController(context: Context) -> UITableViewController {
        let controller = UITableViewController(style: .plain)
        controller.view.backgroundColor = .clear

        let table = controller.tableView!
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 280
        table.contentInsetAdjustmentBehavior = .never
        table.keyboardDismissMode = .interactive
        table.delaysContentTouches = false
        table.canCancelContentTouches = true
        table.decelerationRate = .normal
        table.sectionHeaderTopPadding = 0
        table.showsVerticalScrollIndicator = true
        table.verticalScrollIndicatorInsets.top = headerHeight
        table.register(NativeMomentRowCell.self,
                       forCellReuseIdentifier: NativeMomentRowCell.reuseIdentifier)

        let headerContainer = UIView()
        headerContainer.backgroundColor = .clear
        headerContainer.clipsToBounds = true
        let headerHost = UIHostingController(rootView: header(0))
        headerHost.view.backgroundColor = .clear
        headerHost.view.insetsLayoutMarginsFromSafeArea = false
        headerContainer.addSubview(headerHost.view)
        controller.addChild(headerHost)
        headerHost.didMove(toParent: controller)
        table.tableHeaderView = headerContainer

        context.coordinator.table = table
        context.coordinator.headerContainer = headerContainer
        context.coordinator.headerHost = headerHost
        context.coordinator.requestEnd = { [weak coordinator = context.coordinator] in
            coordinator?.requestNextPage()
        }
        context.coordinator.install(in: table)
        context.coordinator.layoutHeader(in: table, pull: 0)
        context.coordinator.applyIfNeeded(
            moments: moments,
            revision: revision,
            mineOnly: mineOnly,
            dayKey: dayKey
        )
        return controller
    }

    func updateUIViewController(_ controller: UITableViewController,
                                context: Context) {
        let coordinator = context.coordinator
        coordinator.header = header
        coordinator.dayLabel = dayLabel
        coordinator.onScrollActive = onScrollActive
        coordinator.onCollapseChange = onCollapseChange
        coordinator.onPullChange = onPullChange
        coordinator.onPullEnd = onPullEnd
        coordinator.onApproachingEnd = onApproachingEnd
        coordinator.actions = actions
        coordinator.stressText = stressText
        coordinator.footerText = footerText
        coordinator.footerWaiting = footerWaiting
        coordinator.requestEnd = { [weak coordinator] in
            coordinator?.requestNextPage()
        }
        coordinator.updateHeaderHeight(
            headerHeight,
            in: controller.tableView
        )
        coordinator.layoutHeader(
            in: controller.tableView,
            pull: max(0, coordinator.lastPullValue)
        )
        coordinator.applyIfNeeded(
            moments: moments,
            revision: revision,
            mineOnly: mineOnly,
            dayKey: dayKey
        )
        coordinator.refreshFooterIfNeeded()
    }

    final class Coordinator: NSObject, UITableViewDelegate,
                             UITableViewDataSourcePrefetching {
        weak var table: UITableView?
        weak var headerContainer: UIView?
        var headerHost: UIHostingController<Header>?
        var dataSource: UITableViewDiffableDataSource<Int, String>?
        var header: (CGFloat) -> Header
        var dayLabel: (Moment) -> String
        var onScrollActive: (Bool) -> Void
        var onCollapseChange: (Bool) -> Void
        var onPullChange: (CGFloat) -> Void
        var onPullEnd: (CGFloat) -> Void
        var onApproachingEnd: () -> Void
        var actions: NativeMomentActions
        var stressText: String?
        var footerText: String?
        var footerWaiting: Bool
        var requestEnd: (() -> Void)?

        private(set) var items: [NativeMomentFeedItem] = []
        private var lookup: [String: NativeMomentFeedItem] = [:]
        private var sourceMoments: [Moment] = []
        private var sourceRevision = Int.min
        private var sourceMineOnly = false
        private var sourceDayKey = ""
        private var footerSignature = ""
        private var headerHeight: CGFloat
        private var collapseOffset: CGFloat
        private var lastCollapsed = false
        private var lastScrollActive = false
        private var lastPull: CGFloat = -1
        private var endRequestInFlight = false

        var lastPullValue: CGFloat { max(0, lastPull) }

        init(moments: [Moment],
             revision: Int,
             mineOnly: Bool,
             dayKey: String,
             headerHeight: CGFloat,
             collapseOffset: CGFloat,
             onScrollActive: @escaping (Bool) -> Void,
             onCollapseChange: @escaping (Bool) -> Void,
             onPullChange: @escaping (CGFloat) -> Void,
             onPullEnd: @escaping (CGFloat) -> Void,
             onApproachingEnd: @escaping () -> Void,
             actions: NativeMomentActions,
             stressText: String?,
             footerText: String?,
             footerWaiting: Bool,
             dayLabel: @escaping (Moment) -> String,
             header: @escaping (CGFloat) -> Header) {
            _ = moments
            _ = revision
            _ = mineOnly
            _ = dayKey
            self.headerHeight = max(1, headerHeight)
            self.collapseOffset = max(0, collapseOffset)
            self.onScrollActive = onScrollActive
            self.onCollapseChange = onCollapseChange
            self.onPullChange = onPullChange
            self.onPullEnd = onPullEnd
            self.onApproachingEnd = onApproachingEnd
            self.actions = actions
            self.stressText = stressText
            self.footerText = footerText
            self.footerWaiting = footerWaiting
            self.dayLabel = dayLabel
            self.header = header
            super.init()
        }

        func install(in table: UITableView) {
            self.table = table
            table.delegate = self
            table.prefetchDataSource = self
            let source = UITableViewDiffableDataSource<Int, String>(
                tableView: table
            ) { [weak self] tableView, indexPath, id in
                guard let self, let item = self.lookup[id] else {
                    return UITableViewCell()
                }
                guard let cell = tableView.dequeueReusableCell(
                    withIdentifier: NativeMomentRowCell.reuseIdentifier,
                    for: indexPath
                ) as? NativeMomentRowCell else {
                    return UITableViewCell()
                }
                cell.configure(
                    item: item,
                    actions: self.actions,
                    stressText: item.isFirst ? self.stressText : nil,
                    footerText: item.isLast ? self.footerText : nil,
                    footerWaiting: item.isLast && self.footerWaiting
                )
                return cell
            }
            dataSource = source
        }

        func applyIfNeeded(moments: [Moment],
                           revision: Int,
                           mineOnly: Bool,
                           dayKey: String) {
            guard let dataSource else { return }
            let signatureChanged = revision != sourceRevision
                || mineOnly != sourceMineOnly
                || dayKey != sourceDayKey
            guard signatureChanged else { return }

            let previousIDs = Set(items.lazy.map(\.id))
            let previousItemCount = items.count
            let previousLastID = items.last?.id
            let isPureAppend = moments.count > sourceMoments.count
                && moments.prefix(sourceMoments.count).map(\.id)
                    == sourceMoments.map(\.id)
            let start = isPureAppend ? sourceMoments.count : 0
            let previousLastDay = isPureAppend ? items.last?.dayText : nil

            if !isPureAppend {
                items.removeAll(keepingCapacity: true)
                lookup.removeAll(keepingCapacity: true)
            } else if let previous = items.last {
                let updated = NativeMomentFeedItem(
                    id: previous.id,
                    moment: previous.moment,
                    showsDayHeader: previous.showsDayHeader,
                    dayText: previous.dayText,
                    isFirst: previous.isFirst,
                    isLast: false
                )
                items[items.count - 1] = updated
                lookup[updated.id] = updated
            }

            var day = previousLastDay ?? ""
            var seen = isPureAppend ? previousIDs : []
            for index in start..<moments.count {
                let moment = moments[index]
                let id = "moment:\(moment.id)"
                guard seen.insert(id).inserted else { continue }
                let nextDay = dayLabel(moment)
                let item = NativeMomentFeedItem(
                    id: id,
                    moment: moment,
                    showsDayHeader: index == 0 || nextDay != day,
                    dayText: nextDay,
                    isFirst: index == 0,
                    isLast: index == moments.count - 1
                )
                day = nextDay
                items.append(item)
                lookup[id] = item
            }

            sourceMoments = moments
            sourceRevision = revision
            sourceMineOnly = mineOnly
            sourceDayKey = dayKey
            endRequestInFlight = false
            let nextFooterSignature = [
                stressText ?? "",
                footerText ?? "",
                footerWaiting ? "1" : "0"
            ].joined(separator: "|")
            if nextFooterSignature != footerSignature {
                footerSignature = nextFooterSignature
            }

            let nextIDs = items.map(\.id)
            if isPureAppend {
                let added = Array(nextIDs.dropFirst(previousItemCount))
                guard !added.isEmpty else { return }
                var snapshot = dataSource.snapshot()
                if snapshot.numberOfSections == 0 {
                    snapshot.appendSections([0])
                }
                if let previousLastID {
                    snapshot.reloadItems([previousLastID])
                }
                snapshot.appendItems(added, toSection: 0)
                dataSource.apply(snapshot, animatingDifferences: false)
            } else {
                let visible = table?.indexPathsForVisibleRows?.min()
                let visibleID = visible.flatMap { dataSource.itemIdentifier(for: $0) }
                var visibleDelta: CGFloat?
                if let table, let visible {
                    visibleDelta = table.rectForRow(at: visible).minY
                        - table.contentOffset.y
                }
                var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
                snapshot.appendSections([0])
                snapshot.appendItems(nextIDs, toSection: 0)
                if !nextIDs.isEmpty {
                    snapshot.reloadItems(nextIDs)
                }
                dataSource.apply(snapshot, animatingDifferences: false) {
                    [weak self] in
                    guard let self, let table = self.table,
                          let visibleID,
                          let indexPath = dataSource.indexPath(for: visibleID)
                    else { return }
                    if let visibleDelta {
                        let targetY = table.rectForRow(at: indexPath).minY - visibleDelta
                        table.setContentOffset(
                            CGPoint(x: table.contentOffset.x, y: targetY),
                            animated: false
                        )
                    } else {
                        table.scrollToRow(at: indexPath, at: .top, animated: false)
                    }
                }
            }
        }

        func refreshFooterIfNeeded() {
            guard let table, let dataSource, !items.isEmpty else { return }
            let signature = [
                stressText ?? "",
                footerText ?? "",
                footerWaiting ? "1" : "0"
            ].joined(separator: "|")
            guard signature != footerSignature else { return }
            footerSignature = signature
            var snapshot = dataSource.snapshot()
            var ids: [String] = [items[0].id]
            if items.count > 1 { ids.append(items.last!.id) }
            snapshot.reloadItems(ids)
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        func requestNextPage() {
            guard !endRequestInFlight else { return }
            endRequestInFlight = true
            DispatchQueue.main.async { [weak self] in
                self?.onApproachingEnd()
            }
        }

        func updateHeaderHeight(_ height: CGFloat, in table: UITableView) {
            let next = max(1, height)
            guard abs(headerHeight - next) > 0.5 else { return }
            headerHeight = next
            layoutHeader(in: table, pull: max(0, lastPull))
        }

        func layoutHeader(in table: UITableView, pull: CGFloat) {
            guard let headerContainer, let headerHost else { return }
            let extra = max(0, pull)
            let targetHeight = headerHeight + extra
            var frame = CGRect(
                x: 0,
                y: 0,
                width: max(1, table.bounds.width),
                height: targetHeight
            )
            if abs(headerContainer.frame.height - targetHeight) > 0.5
                || abs(headerContainer.frame.width - frame.width) > 0.5 {
                headerContainer.frame = frame
                table.tableHeaderView = headerContainer
            }
            headerHost.view.frame = CGRect(
                x: 0,
                y: 0,
                width: frame.width,
                height: targetHeight
            )
            if !headerContainer.bounds.isEmpty {
                headerContainer.frame = frame
            }
            headerHost.rootView = header(extra)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let pull = max(0, -scrollView.contentOffset.y)
            let collapsed = scrollView.contentOffset.y > collapseOffset
            if collapsed != lastCollapsed {
                lastCollapsed = collapsed
                onCollapseChange(collapsed)
            }
            let active = scrollView.isDragging
                || scrollView.isTracking
                || scrollView.isDecelerating
            if active != lastScrollActive {
                lastScrollActive = active
                onScrollActive(active)
            }
            let quantizedPull = (pull / 2).rounded() * 2
            if abs(quantizedPull - lastPull) >= 2 {
                lastPull = quantizedPull
                onPullChange(quantizedPull)
                if let table = scrollView as? UITableView {
                    layoutHeader(in: table, pull: quantizedPull)
                }
            }
            let remaining = scrollView.contentSize.height
                - scrollView.bounds.height
                - scrollView.contentOffset.y
            if scrollView.isDragging || scrollView.isDecelerating,
               remaining < max(2_400, scrollView.bounds.height * 4) {
                requestNextPage()
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            endRequestInFlight = false
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView,
                                      willDecelerate decelerate: Bool) {
            onPullEnd(max(0, lastPull))
            if !decelerate {
                endRequestInFlight = false
                if lastScrollActive {
                    lastScrollActive = false
                    onScrollActive(false)
                }
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            endRequestInFlight = false
            if lastScrollActive {
                lastScrollActive = false
                onScrollActive(false)
            }
        }

        func tableView(_ tableView: UITableView,
                       prefetchRowsAt indexPaths: [IndexPath]) {
            for indexPath in indexPaths
            where items.indices.contains(indexPath.row) {
                NativeMomentRowCell.prefetch(items[indexPath.row].moment)
            }
            guard let maximum = indexPaths.map(\.row).max() else { return }
            if maximum >= max(0, items.count - 40) {
                requestNextPage()
            }
        }

        func tableView(_ tableView: UITableView,
                       cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {}

        func tableView(_ tableView: UITableView,
                       willDisplay cell: UITableViewCell,
                       forRowAt indexPath: IndexPath) {
            (cell as? NativeMomentRowCell)?.setPlaybackActive(true)
            if indexPath.row >= max(0, items.count - 24) {
                requestNextPage()
            }
        }

        func tableView(_ tableView: UITableView,
                       didEndDisplaying cell: UITableViewCell,
                       forRowAt indexPath: IndexPath) {
            (cell as? NativeMomentRowCell)?.setPlaybackActive(false)
        }
    }
}
