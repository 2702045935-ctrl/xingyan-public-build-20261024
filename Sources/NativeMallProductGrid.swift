import SwiftUI
import UIKit

final class NativeMallProductGridController {
    weak var collectionView: UICollectionView?

    func attach(_ collectionView: UICollectionView?) {
        self.collectionView = collectionView
    }

    func scrollToProductStart(animated: Bool = true) {
        guard let collectionView,
              collectionView.numberOfItems(inSection: 0) > 0 else { return }
        collectionView.scrollToItem(
            at: IndexPath(item: 0, section: 0),
            at: .top,
            animated: animated
        )
    }
}

private final class NativeMallImageLoader {
    static let shared = NativeMallImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 900
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    func image(path: String, side: CGFloat) async -> UIImage? {
        guard !path.isEmpty else { return nil }
        let stable = ImageCacheKey.stablePath(path)
        let key = stable + "#mall-native-" + String(Int(max(160, side)))
        if let hit = cache.object(forKey: key as NSString) { return hit }

        lock.lock()
        if let task = inFlight[key] {
            lock.unlock()
            return await task.value
        }
        let task = Task<UIImage?, Never> {
            var data = await Task.detached(priority: .utility) {
                ImageStore.shared.diskRead(stable)
            }.value
            if data == nil, let url = API.shared.assetURL(path) {
                data = try? await API.shared.imageData(url)
            }
            guard let data else { return nil }
            return await Task.detached(priority: .userInitiated) {
                RemoteImage.downsampled(data, maxSide: side)
            }.value
        }
        inFlight[key] = task
        lock.unlock()

        let image = await task.value
        lock.lock()
        inFlight.removeValue(forKey: key)
        lock.unlock()
        if let image {
            cache.setObject(image,
                            forKey: key as NSString,
                            cost: Int(image.size.width * image.size.height * 4))
        }
        return image
    }

    func prefetch(_ paths: [String], side: CGFloat) {
        for path in paths where !path.isEmpty {
            Task(priority: .utility) {
                _ = await image(path: path, side: side)
            }
        }
    }

    func cancelPrefetch(_ paths: [String], side: CGFloat) {
        for path in paths where !path.isEmpty {
            let stable = ImageCacheKey.stablePath(path)
            let key = stable + "#mall-native-" + String(Int(max(160, side)))
            lock.lock()
            inFlight.removeValue(forKey: key)?.cancel()
            lock.unlock()
        }
    }
}

private final class NativeMallProductCell: UICollectionViewCell {
    static let reuseID = "NativeMallProductCell"
    static let estimatedHeight: CGFloat = 304

    private let imageView = UIImageView()
    private let sellerLabel = UILabel()
    private let titleLabel = UILabel()
    private let tagLabel = UILabel()
    private let priceLabel = UILabel()
    private let originalLabel = UILabel()
    private let shopLabel = UILabel()
    private let soldLabel = UILabel()
    private let addButton = UIButton(type: .system)
    private var imageTask: Task<Void, Never>?
    private var addAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = 13
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = 0.6
        contentView.clipsToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true

        sellerLabel.font = pfUIFont(9.5, .semibold)
        sellerLabel.textColor = .white
        sellerLabel.backgroundColor = UIColor(hex: 0xE23427)
        sellerLabel.layer.cornerRadius = 8
        sellerLabel.layer.cornerCurve = .continuous
        sellerLabel.clipsToBounds = true
        sellerLabel.textAlignment = .center

        titleLabel.font = pfUIFont(14, .medium)
        titleLabel.numberOfLines = 2

        tagLabel.font = pfUIFont(10, .medium)
        tagLabel.textColor = UIColor.dyn(0xD92D20, 0xFF6961)
        tagLabel.numberOfLines = 1

        priceLabel.font = pfUIFont(20, .bold)
        priceLabel.textColor = UIColor.dyn(0xD92D20, 0xFF6961)

        originalLabel.font = pfUIFont(10, .regular)
        originalLabel.textColor = UIColor.dyn(0x86868B, 0x7C7C80)

        shopLabel.font = pfUIFont(9.5, .regular)
        shopLabel.textColor = UIColor.dyn(0x86868B, 0x8E8E93)
        shopLabel.lineBreakMode = .byTruncatingTail

        soldLabel.font = pfUIFont(9.5, .regular)
        soldLabel.textColor = UIColor.dyn(0x86868B, 0x7C7C80)
        soldLabel.textAlignment = .right

        addButton.setImage(UIImage(systemName: "plus"), for: .normal)
        addButton.tintColor = .white
        addButton.backgroundColor = UIColor.dyn(0x0071E3, 0x0A84FF)
        addButton.layer.cornerRadius = 15
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)

        [imageView, sellerLabel, titleLabel, tagLabel, priceLabel,
         originalLabel, shopLabel, soldLabel, addButton].forEach {
            contentView.addSubview($0)
        }
        applyTheme()
    }

    required init?(coder: NSCoder) { nil }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else {
            return
        }
        applyTheme()
    }

    private func applyTheme() {
        let dark = traitCollection.userInterfaceStyle == .dark
        contentView.backgroundColor = dark ? UIColor(hex: 0x1C1C1E) : .white
        contentView.layer.borderColor = (dark
            ? UIColor(hex: 0x38383A)
            : UIColor(hex: 0xE5E5EA)).cgColor
        imageView.backgroundColor = dark ? UIColor(hex: 0x2C2C2E) : UIColor(hex: 0xF5F5F7)
        titleLabel.textColor = dark ? UIColor(hex: 0xF5F5F7) : UIColor(hex: 0x1D1D1F)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        imageView.image = nil
        addAction = nil
    }

    func configure(_ product: DDProduct, add: (() -> Void)?) {
        sellerLabel.text = "  " + Tr(product.isSelfOperated ? "自营" : "第三方") + "  "
        sellerLabel.backgroundColor = UIColor(hex: product.isSelfOperated ? 0xE23427 : 0x555A63)
        titleLabel.text = product.title
        tagLabel.text = product.tags.first.map { Tr($0) } ?? Tr("包邮")
        priceLabel.text = "¥" + moneyFmt(product.price)
        originalLabel.attributedText = NSAttributedString(
            string: "¥" + moneyFmt(product.orig),
            attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
        )
        shopLabel.text = product.shop.isEmpty ? Tr("星言官方旗舰店") : product.shop
        soldLabel.text = Tr("已售") + (product.sold.isEmpty ? "1000+" : product.sold)
        addAction = add
        addButton.isHidden = add == nil

        let path = product.img ?? ""
        imageTask = Task { [weak self] in
            let image = await NativeMallImageLoader.shared.image(path: path, side: 360)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.imageView.image == nil else { return }
                self?.imageView.image = image
            }
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        let imageSide = width
        imageView.frame = CGRect(x: 0, y: 0, width: width, height: imageSide)
        sellerLabel.frame = CGRect(x: 9, y: 9,
                                   width: min(72, width * 0.36), height: 22)
        titleLabel.frame = CGRect(x: 10, y: imageSide + 8,
                                  width: width - 20, height: 39)
        tagLabel.frame = CGRect(x: 10, y: imageSide + 48,
                                width: width - 20, height: 16)
        priceLabel.frame = CGRect(x: 10, y: imageSide + 68,
                                  width: min(120, width - 54), height: 28)
        originalLabel.frame = CGRect(x: min(width - 68, priceLabel.frame.maxX + 4),
                                     y: imageSide + 76,
                                     width: max(24, width - priceLabel.frame.maxX - 14),
                                     height: 16)
        addButton.frame = CGRect(x: width - 40, y: imageSide + 65,
                                 width: 30, height: 30)
        shopLabel.frame = CGRect(x: 10, y: imageSide + 101,
                                 width: width * 0.55, height: 16)
        soldLabel.frame = CGRect(x: width * 0.55, y: imageSide + 101,
                                 width: width * 0.45 - 10, height: 16)
    }

    @objc private func addTapped() {
        addAction?()
    }
}

final class NativeMallGridCoordinator: NSObject,
                                       UICollectionViewDelegate,
                                       UICollectionViewDataSourcePrefetching {
    var products: [DDProduct] = []
    var onOpen: ((DDProduct) -> Void)?
    var onAddCart: ((DDProduct) -> Void)?
    var header: AnyView?
    var footer: AnyView?
    var headerRevision = ""
    var footerRevision = ""
    private var lookup: [String: DDProduct] = [:]
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>?

    func makeDataSource(for collectionView: UICollectionView)
        -> UICollectionViewDiffableDataSource<Int, String> {
        let source = UICollectionViewDiffableDataSource<Int, String>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, id in
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: NativeMallProductCell.reuseID,
                for: indexPath
            )
            guard let self,
                  let product = self.lookup[id],
                  let productCell = cell as? NativeMallProductCell else {
                return cell
            }
            productCell.configure(product) { [weak self] in
                self?.onAddCart?(product)
            }
            productCell.accessibilityLabel = product.title
            productCell.accessibilityTraits = .button
            return productCell
        }
        source.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard let self else { return nil }
            let isHeader = kind == UICollectionView.elementKindSectionHeader
            let candidate = isHeader
                ? self.header.map { ($0, self.headerRevision) }
                : self.footer.map { ($0, self.footerRevision) }
            guard let (content, revision) = candidate else { return nil }
            let view = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: NativeMallHostingSupplementaryView.reuseID,
                for: indexPath
            )
            (view as? NativeMallHostingSupplementaryView)?
                .configure(content, revision: revision)
            return view
        }
        dataSource = source
        return source
    }

    func updateSupplementary(
        in collectionView: UICollectionView,
        header: AnyView?,
        footer: AnyView?,
        headerRevision: String,
        footerRevision: String
    ) {
        let headerChanged = self.headerRevision != headerRevision
        let footerChanged = self.footerRevision != footerRevision
        self.header = header
        self.footer = footer
        self.headerRevision = headerRevision
        self.footerRevision = footerRevision
        if headerChanged,
           let view = collectionView.supplementaryView(
               forElementKind: UICollectionView.elementKindSectionHeader,
               at: IndexPath(item: 0, section: 0)
           ) as? NativeMallHostingSupplementaryView {
            view.configure(header, revision: headerRevision)
        }
        if footerChanged,
           let view = collectionView.supplementaryView(
               forElementKind: UICollectionView.elementKindSectionFooter,
               at: IndexPath(item: 0, section: 0)
           ) as? NativeMallHostingSupplementaryView {
            view.configure(footer, revision: footerRevision)
        }
        if headerChanged || footerChanged {
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    func apply(_ next: [DDProduct],
               to collectionView: UICollectionView,
               resetToTop: Bool) {
        guard let dataSource else { return }
        var uniqueProducts: [DDProduct] = []
        var uniqueIDs = Set<String>()
        for product in next where uniqueIDs.insert(product.id).inserted {
            uniqueProducts.append(product)
        }
        let next = uniqueProducts
        let old = products
        let nextIDs = next.map(\.id)
        guard old.map(\.id) != nextIDs || old != next else { return }

        let previousOffset = collectionView.contentOffset
        let topIndexPath = collectionView.indexPathsForVisibleItems.min()
        let topAnchorID = topIndexPath.flatMap { dataSource.itemIdentifier(for: $0) }
        let topAnchorDelta = topIndexPath.map {
            collectionView.contentOffset.y
                - (collectionView.layoutAttributesForItem(at: $0)?.frame.minY ?? 0)
        }

        let oldLookup = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        products = next
        lookup = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(nextIDs, toSection: 0)
        let changed = next.compactMap { product -> String? in
            guard let previous = oldLookup[product.id] else { return nil }
            return previous == product ? nil : product.id
        }
        if !changed.isEmpty {
            snapshot.reloadItems(changed)
        }
        dataSource.apply(snapshot, animatingDifferences: false) {
            collectionView.layoutIfNeeded()
            if resetToTop {
                collectionView.setContentOffset(.zero, animated: false)
            } else if let topAnchorID,
                      let indexPath = dataSource.indexPath(for: topAnchorID),
                      let delta = topAnchorDelta,
                      let attributes = collectionView.layoutAttributesForItem(at: indexPath) {
                collectionView.setContentOffset(
                    CGPoint(x: previousOffset.x, y: attributes.frame.minY + delta),
                    animated: false
                )
            } else {
                collectionView.setContentOffset(previousOffset, animated: false)
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < products.count else { return }
        onOpen?(products[indexPath.item])
    }

    func collectionView(_ collectionView: UICollectionView,
                        prefetchItemsAt indexPaths: [IndexPath]) {
        let paths = indexPaths.compactMap { index -> String? in
            guard index.item < products.count else { return nil }
            return products[index.item].img
        }
        NativeMallImageLoader.shared.prefetch(paths, side: 360)
    }

    func collectionView(_ collectionView: UICollectionView,
                        cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let paths = indexPaths.compactMap { index -> String? in
            guard index.item < products.count else { return nil }
            return products[index.item].img
        }
        NativeMallImageLoader.shared.cancelPrefetch(paths, side: 360)
    }
}

private final class NativeMallHostingSupplementaryView: UICollectionReusableView {
    static let reuseID = "NativeMallHostingSupplementaryView"
    private var revision: String?

    func configure(_ content: AnyView?, revision: String) {
        guard self.revision != revision else { return }
        self.revision = revision
        guard let content else {
            contentConfiguration = nil
            return
        }
        contentConfiguration = UIHostingConfiguration {
            content
        }
        .margins(.all, 0)
        .background(.clear)
    }
}

struct NativeMallProductGrid: UIViewRepresentable {
    let products: [DDProduct]
    let onOpen: (DDProduct) -> Void
    var onAddCart: ((DDProduct) -> Void)? = nil
    var header: AnyView? = nil
    var footer: AnyView? = nil
    var headerRevision: String = ""
    var footerRevision: String = ""
    var controller: NativeMallProductGridController? = nil

    func makeCoordinator() -> NativeMallGridCoordinator {
        NativeMallGridCoordinator()
    }

    func makeUIView(context: Context) -> UICollectionView {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(0.5),
                heightDimension: .fractionalHeight(1)
            )
        )
        item.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 5,
                                                     bottom: 5, trailing: 5)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(NativeMallProductCell.estimatedHeight)
            ),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 7,
                                                        bottom: 16, trailing: 7)
        var supplementary: [NSCollectionLayoutBoundarySupplementaryItem] = []
        if header != nil {
            supplementary.append(NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(2_400)
                ),
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            ))
        }
        if footer != nil {
            supplementary.append(NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(1_800)
                ),
                elementKind: UICollectionView.elementKindSectionFooter,
                alignment: .bottom
            ))
        }
        section.boundarySupplementaryItems = supplementary
        let layout = UICollectionViewCompositionalLayout(section: section)
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = UIColor.dyn(0xF5F5F7, 0x000000)
        view.indicatorStyle = .default
        view.alwaysBounceVertical = true
        view.showsVerticalScrollIndicator = true
        view.prefetchDataSource = context.coordinator
        view.delegate = context.coordinator
        let dataSource = context.coordinator.makeDataSource(for: view)
        view.dataSource = dataSource
        view.register(NativeMallProductCell.self,
                      forCellWithReuseIdentifier: NativeMallProductCell.reuseID)
        view.register(
            NativeMallHostingSupplementaryView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: NativeMallHostingSupplementaryView.reuseID
        )
        view.register(
            NativeMallHostingSupplementaryView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
            withReuseIdentifier: NativeMallHostingSupplementaryView.reuseID
        )
        view.contentInsetAdjustmentBehavior = .never
        context.coordinator.header = header
        context.coordinator.footer = footer
        context.coordinator.headerRevision = headerRevision
        context.coordinator.footerRevision = footerRevision
        controller?.attach(view)
        context.coordinator.apply(products, to: view, resetToTop: true)
        return view
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onOpen = onOpen
        coordinator.onAddCart = onAddCart
        controller?.attach(collectionView)
        coordinator.updateSupplementary(
            in: collectionView,
            header: header,
            footer: footer,
            headerRevision: headerRevision,
            footerRevision: footerRevision
        )
        let resetToTop = coordinator.products.first?.id != products.first?.id
        coordinator.apply(products, to: collectionView, resetToTop: resetToTop)
    }
}
