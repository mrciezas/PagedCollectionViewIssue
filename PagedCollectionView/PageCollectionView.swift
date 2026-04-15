//
//  PageCollectionView.swift
//  PagedCollectionView
//
//  Created by Christian Cieza on 15/04/26.
//

import SwiftUI
import Combine

extension PageCollectionView {
    public typealias UIKitCollectionView = FullScreenPageCollectionView<SectionIDType, ItemIdentifierType, Change>
    public typealias DataSource = FullScreenPageDiffableDataSource<SectionIDType, ItemIdentifierType>
    public typealias Snapshot = NSDiffableDataSourceSnapshot<SectionIDType, ItemIdentifierType>
    public typealias UpdateCompletion = () -> Void
}

public struct PageCollectionView<SectionIDType, ItemIdentifierType, Change>
where
SectionIDType: Hashable & Sendable,
ItemIdentifierType: Hashable & Sendable,
Change: PageChange {

    private let snapshot: Snapshot
    private let lastUpdatedUUID: UUID
    private let currentPage: Int
    private let accessibilityIdentifier: String
    private let cellProvider: DataSource.CellProvider

    private(set) var backgroundColor: UIColor = .white
    private(set) var animatingDifferences: Bool = true
    private(set) var updateCallBack: UpdateCompletion?
    private let page: PassthroughSubject<Change.Page, Never>
    private let willChangePage: PassthroughSubject<Int, Never>?
    private let scrollTo: PassthroughSubject<Change, Never>
    private let willBeginDragging: PassthroughSubject<Void, Never>?

    public init(
        snapshot: Snapshot,
        lastUpdatedUUID: UUID,
        currentPage: Int,
        accessibilityIdentifier: String,
        page: PassthroughSubject<Change.Page, Never>,
        willChangePage: PassthroughSubject<Int, Never>?,
        willBeginDragging: PassthroughSubject<Void, Never>?,
        scrollTo: PassthroughSubject<Change, Never>,
        cellProvider: @escaping DataSource.CellProvider
    ) {
        self.snapshot = snapshot
        self.lastUpdatedUUID = lastUpdatedUUID
        self.currentPage = currentPage
        self.accessibilityIdentifier = accessibilityIdentifier
        self.cellProvider = cellProvider
        self.page = page
        self.willChangePage = willChangePage
        self.scrollTo = scrollTo
        self.willBeginDragging = willBeginDragging
    }
}

extension PageCollectionView: UIViewRepresentable {
    public func makeUIView(context: Context) -> UIKitCollectionView {
        let collectionView = UIKitCollectionView(
            frame: .zero,
            page: page,
            willChangePage: willChangePage,
            scrollTo: scrollTo,
            willBeginDragging: willBeginDragging,
            cellProvider: cellProvider
        )
        collectionView.accessibilityIdentifier = accessibilityIdentifier
        return collectionView
    }

    public func updateUIView(_ uiView: UIKitCollectionView,
                             context: Context) {
        uiView.backgroundColor = backgroundColor
        if lastUpdatedUUID != context.coordinator.lastUpdatedUUID {
            uiView.apply(
                snapshot,
                currentPage: currentPage,
                animatingDifferences: animatingDifferences,
                completion: updateCallBack
            )
            context.coordinator.lastUpdatedUUID = lastUpdatedUUID
        }
    }

    public func makeCoordinator() -> Coordinator {
        return Coordinator()
    }

    public class Coordinator {
        var lastUpdatedUUID: UUID?
    }
}

public extension PageCollectionView {
    func animateDifferences(_ animate: Bool) -> Self {
        var selfCopy = self
        selfCopy.animatingDifferences = animate
        return selfCopy
    }

    func onUpdate(_ perform: (() -> Void)?) -> Self {
        var selfCopy = self
        selfCopy.updateCallBack = perform
        return selfCopy
    }

    func collectionViewBackgroundColor(_ color: Color) -> Self {
        var selfCopy = self
        selfCopy.backgroundColor = UIColor(color)
        return selfCopy
    }
}
