//
//  FullScreenPageCollectionView.swift
//  PagedCollectionView
//
//  Created by Christian Cieza on 15/04/26.
//

import SwiftUI
import Combine

public enum PageDirection {
    case next
    case back
}

public protocol PageInfo {
    var page: Int { get set }
    var direction: PageDirection { get }

    init(page: Int, direction: PageDirection)
}

public protocol PageChange where Page: PageInfo {

    associatedtype Page

    var pageInfo: Page { get }
    var animated: Bool { get }
}

final public class FullScreenPageCollectionView<SectionIDType, ItemIdentifierType, Change>: UICollectionView, UICollectionViewDelegate, PageFlowLayoutDelegate
where
SectionIDType: Hashable & Sendable,
ItemIdentifierType: Hashable & Sendable,
Change: PageChange {

    public typealias DataSource = FullScreenPageDiffableDataSource<SectionIDType, ItemIdentifierType>
    public typealias Snapshot = NSDiffableDataSourceSnapshot<SectionIDType, ItemIdentifierType>

    private let cellProvider: DataSource.CellProvider

    private lazy var collectionDataSource: DataSource = {
        let dataSource = DataSource(
            collectionView: self,
            cellProvider: cellProvider
        )
        return dataSource
    }()

    private let pageFlowLayout = PageFlowLayout()
    private var scrollDirection: UICollectionView.ScrollDirection {
        pageFlowLayout.scrollDirection
    }
    private var cancellables = Set<AnyCancellable>()

    private var currentPageIndex: Int = .zero
    private var isScrollingToItem = false
    private let willChangePage: PassthroughSubject<Int, Never>?
    private let page: PassthroughSubject<Change.Page, Never>
    private let scrollTo: PassthroughSubject<Change, Never>
    private let willBeginDragging: PassthroughSubject<Void, Never>?
    private var previousBoundsSize: CGSize = .zero
    override public var safeAreaInsets: UIEdgeInsets { .zero }

    public init(
        frame: CGRect,
        page: PassthroughSubject<Change.Page, Never>,
        willChangePage: PassthroughSubject<Int, Never>?,
        scrollTo: PassthroughSubject<Change, Never>,
        willBeginDragging: PassthroughSubject<Void, Never>?,
        cellProvider: @escaping DataSource.CellProvider
    ) {
        self.page = page
        self.willChangePage = willChangePage
        self.scrollTo = scrollTo
        self.cellProvider = cellProvider
        self.willBeginDragging = willBeginDragging

        super.init(frame: frame, collectionViewLayout: pageFlowLayout)
        delegate = self
        pageFlowLayout.delegate = self
        configure()
        setupBindings()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesVertically = false
        isPagingEnabled = false
        contentInsetAdjustmentBehavior = .never
    }

    var onHoldPage: Change.Page?

    private func setupBindings() {
        scrollTo
            .sink { [weak self] change in
                guard let self else { return }
                let newPage = change.pageInfo.page
                guard numberOfSections > 0, numberOfItems(inSection: 0) > newPage else { return }
                let pageIndex = IndexPath(row: newPage, section: 0)
                if change.animated {
                    onHoldPage = change.pageInfo
                }
                self.willChangePage?.send(newPage)
                if change.animated {
                    self.isScrollingToItem = true
                }
                self.scrollToItem(
                    at: pageIndex,
                    at: [.centeredHorizontally, .centeredVertically],
                    animated: change.animated
                )
                if !change.animated {
                    self.currentPageIndex = change.pageInfo.page
                    self.page.send(change.pageInfo)
                }
            }
            .store(in: &cancellables)
    }

    func apply(_ snapshot: Snapshot,
               currentPage: Int,
               animatingDifferences: Bool = false,
               completion: (() -> Void)? = nil) {
        currentPageIndex = currentPage
        collectionDataSource.apply(
            snapshot,
            animatingDifferences: animatingDifferences,
            completion: completion
        )
    }

    // MARK: ScrollView delegate

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        willBeginDragging?.send()
    }

    public func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let targetPage = page(for: targetContentOffset.pointee)
        guard targetPage != currentPageIndex else { return }
        willChangePage?.send(targetPage)
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let newPage = page(for: scrollView.contentOffset)
        guard currentPageIndex != newPage else { return }
        self.page.send(Change.Page(page: newPage, direction: newPage - currentPageIndex > 0 ? .next : .back))
        // Activate scroll when page change
        if !scrollView.isScrollEnabled {
            scrollView.isScrollEnabled = true
        }
        currentPageIndex = newPage
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isScrollingToItem = false
        if let onHoldPage {
            currentPageIndex = onHoldPage.page
            page.send(onHoldPage)
            self.onHoldPage = nil
        }
    }

    private func page(for point: CGPoint) -> Int {
        var page: Int = 0
        if scrollDirection == .horizontal {
            let pageWidth = bounds.size.width
            page = Int(floor((point.x - pageWidth / 2) / pageWidth) + 1)
        } else {
            let pageWidth = bounds.size.height
            page = Int(floor((point.y - pageWidth / 2) / pageWidth) + 1)
        }
        return page
    }

    // MARK: - PageFlowLayoutDelegate

    func currentPage() -> Int {
        currentPageIndex
    }
}

protocol PageFlowLayoutDelegate: AnyObject {

    func currentPage() -> Int

}

extension FullScreenPageCollectionView {
    class PageFlowLayout: UICollectionViewFlowLayout {

        override class var layoutAttributesClass: AnyClass {
            UICollectionViewLayoutAttributes.self
        }

        private var calculatedAttributes: [UICollectionViewLayoutAttributes] = []
        private var calculatedContentWidth: CGFloat = 0
        private var calculatedContentHeight: CGFloat = 0

        public weak var delegate: PageFlowLayoutDelegate?

        override var collectionViewContentSize: CGSize {
            return CGSize(width: self.calculatedContentWidth, height: self.calculatedContentHeight)
        }

        override init() {
            super.init()
            self.estimatedItemSize = .zero
            self.scrollDirection = .horizontal
            self.minimumLineSpacing = 0
            self.minimumInteritemSpacing = 0
            self.sectionInset = .zero
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func prepare() {
            guard
                let collectionView = collectionView,
                collectionView.numberOfSections > 0,
                calculatedAttributes.isEmpty
            else { return }

            print("[PageFlowLayout] prepare() — bounds: \(collectionView.bounds.size), currentPage: \(delegate?.currentPage() ?? -1), contentOffset: \(collectionView.contentOffset)")

            estimatedItemSize = collectionView.bounds.size
            for item in 0..<collectionView.numberOfItems(inSection: 0) {
                let indexPath = IndexPath(item: item, section: 0)
                let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
                let itemOrigin = CGPoint(x: CGFloat(item) * collectionView.bounds.width, y: 0)
                attributes.frame = .init(origin: itemOrigin, size: collectionView.bounds.size)
                calculatedAttributes.append(attributes)
            }
            calculatedContentWidth = collectionView.bounds.width * CGFloat(calculatedAttributes.count)
            calculatedContentHeight = collectionView.bounds.size.height
        }

        override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
            return calculatedAttributes.compactMap { $0.frame.intersects(rect) ? $0 : nil }
        }

        override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
            return calculatedAttributes[indexPath.item]
        }

        override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
            print("[PageFlowLayout] shouldInvalidateLayout(forBoundsChange: \(newBounds))")
            guard let collectionView else { return false }
            let superValue = super.shouldInvalidateLayout(forBoundsChange: newBounds)
            print("[PageFlowLayout] shouldInvalidateLayout(forBoundsChange:) super is \(superValue))")

            if newBounds.size != collectionView.bounds.size {
                print("[PageFlowLayout] shouldInvalidateLayout — bounds changed: \(collectionView.bounds.size) → \(newBounds.size), currentPage: \(delegate?.currentPage() ?? -1)")
                return true
            }
            if newBounds.size.width > 0 {
                let pages = calculatedContentWidth / newBounds.size.width
                let arePagesExact = pages.truncatingRemainder(dividingBy: 1) == 0
                print("[PageFlowLayout] shouldInvalidateLayout(forBoundsChange:) 1 return \(!arePagesExact)")
                return !arePagesExact
            }
            print("[PageFlowLayout] shouldInvalidateLayout(forBoundsChange:) 2 return false")
            return false
        }

        override func invalidateLayout() {
            calculatedAttributes = []
            super.invalidateLayout()
        }

        override func shouldInvalidateLayout(forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes, withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes) -> Bool {
            return false
        }

        override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
            let context = super.invalidationContext(forBoundsChange: newBounds)
            if let collectionView, let currentPage = delegate?.currentPage(), newBounds.width > 0 {
                let targetX = CGFloat(currentPage) * newBounds.width
                let adjustment = targetX - collectionView.contentOffset.x
                print("[PageFlowLayout] invalidationContext — currentPage: \(currentPage), newBounds.width: \(newBounds.width), currentOffset.x: \(collectionView.contentOffset.x), targetX: \(targetX), adjustment: \(adjustment)")
                context.contentOffsetAdjustment.x = adjustment
            }
            return context
        }

        override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
            calculatedAttributes = []
            print("[PageFlowLayout] invalidateLayout(with:) — offsetAdjustment: \(context.contentOffsetAdjustment)")
            super.invalidateLayout(with: context)
        }

        override func targetContentOffset(
            forProposedContentOffset proposedContentOffset: CGPoint,
            withScrollingVelocity velocity: CGPoint
        ) ->  CGPoint {
            print("[PageFlowLayout] targetContentOffset for velocity")
            guard let collectionView, collectionView.bounds.width >  0 else {
                print("[PageFlowLayout] targetContentOffset for velocity 1")
                return proposedContentOffset
            }
            print("[PageFlowLayout] targetContentOffset for velocity 2")
            let pageWidth = collectionView.bounds.width
            let currentOffset = collectionView.contentOffset.x
            let currentPage = round(currentOffset / pageWidth)

            var targetPage: CGFloat
            if abs(velocity.x) > 0.2 {
                targetPage = velocity.x >  0 ? currentPage + 1 : currentPage - 1
            } else {
                targetPage = round(proposedContentOffset.x / pageWidth)
            }

            let pageCount = CGFloat(collectionView.numberOfItems(inSection: 0))
            targetPage = max(0, min(targetPage, pageCount - 1))
            return CGPoint(x: targetPage * pageWidth, y: 0)
        }

        // This function updates the contentOffset in case is wrong
        override func finalizeCollectionViewUpdates() {
            print("[PageFlowLayout] finalizeCollectionViewUpdates")
            guard let collectionView, let currentPage = delegate?.currentPage() else { return }
            let xPosition = CGFloat(currentPage) * collectionView.bounds.width
            print("[PageFlowLayout] finalizeCollectionViewUpdates — currentPage: \(currentPage), expectedX: \(xPosition), actualX: \(collectionView.contentOffset.x)")
            if xPosition != collectionView.contentOffset.x {
                let offset = CGPoint(x: xPosition, y: 0)
                collectionView.setContentOffset(offset, animated: false)
            }
        }
    }
}

public class FullScreenPageDiffableDataSource<SectionIDType, ItemIdentifierType>: UICollectionViewDiffableDataSource<SectionIDType, ItemIdentifierType> where SectionIDType: Hashable & Sendable, ItemIdentifierType: Hashable & Sendable {

}
