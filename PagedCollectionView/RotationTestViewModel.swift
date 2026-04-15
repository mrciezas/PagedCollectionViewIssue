//
//  RotationTestViewModel.swift
//  PagedCollectionView
//
//  Created by Christian Cieza on 15/04/26.
//

import SwiftUI
import Combine

final class RotationTestViewModel: ObservableObject {

    typealias Section = Int
    typealias Snapshot = NSDiffableDataSourceSnapshot<Section, RotationTestItem>

    @Published var lastUpdatedUUID: UUID = UUID()
    @Published var currentPage: Int = 0

    let pageSubject = PassthroughSubject<RotationTestPageInfo, Never>()
    let willChangePage = PassthroughSubject<Int, Never>()
    let scrollTo = PassthroughSubject<RotationTestPageChange, Never>()

    private(set) var snapshot: Snapshot = {
        var snap = Snapshot()
        snap.appendSections([0])
        return snap
    }()

    private var cancellables = Set<AnyCancellable>()
    private(set) var cellRegistration: UICollectionView.CellRegistration<UICollectionViewCell, RotationTestItem>!

    var itemCount: Int { snapshot.numberOfItems }
    private var nextItemId: Int = 100
    private var lastInsertedItems: [RotationTestItem] = []

    init() {
        setupCellRegistration()
        setupBindings()
        loadItems()
    }

    private func setupBindings() {
        pageSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                self?.currentPage = info.page
            }
            .store(in: &cancellables)
    }

    private func setupCellRegistration() {
        cellRegistration = UICollectionView.CellRegistration { [weak self] cell, indexPath, item in
            cell.contentConfiguration = UIHostingConfiguration {
                RotationTestCell(
                    item: item,
                    index: indexPath.item,
                    onInsert: { self?.insertAroundCurrentPage() },
                    onDelete: { self?.deleteInsertedItems() },
                    onDelayedNext: { self?.goToNextAfterDelay() }
                )
            }
            .margins(.all, 0)
        }
    }

    func cellProvider(
        _ collectionView: UICollectionView,
        indexPath: IndexPath,
        item: RotationTestItem
    ) -> UICollectionViewCell {
        collectionView.dequeueConfiguredReusableCell(
            using: cellRegistration,
            for: indexPath,
            item: item
        )
    }

    private func loadItems() {
        let colors: [ItemColor] = [.red, .blue, .green, .orange, .purple, .pink, .cyan, .yellow]
        let items = colors.enumerated().map { index, color in
            RotationTestItem(id: index, itemColor: color, label: "Page \(index + 1)")
        }
        snapshot.appendItems(items)
        lastUpdatedUUID = UUID()
    }

    func goToNext() {
        let nextPage = min(currentPage + 1, itemCount - 1)
        guard nextPage != currentPage else { return }
        let info = RotationTestPageInfo(page: nextPage, direction: .next)
        let change = RotationTestPageChange(pageInfo: info, animated: true)
        scrollTo.send(change)
    }

    func goToPrevious() {
        let prevPage = max(currentPage - 1, 0)
        guard prevPage != currentPage else { return }
        let info = RotationTestPageInfo(page: prevPage, direction: .back)
        let change = RotationTestPageChange(pageInfo: info, animated: true)
        scrollTo.send(change)
    }

    func insertAroundCurrentPage() {
        let items = snapshot.itemIdentifiers
        let colors: [ItemColor] = [.red, .blue, .green, .orange, .purple, .pink, .cyan, .yellow]
        let currentItem = items[currentPage]

        // Insert one before
        let beforeItem = RotationTestItem(id: nextItemId, itemColor: colors[nextItemId % colors.count], label: "New \(nextItemId)")
        nextItemId += 1

        // Insert one after
        let afterItem = RotationTestItem(id: nextItemId, itemColor: colors[nextItemId % colors.count], label: "New \(nextItemId)")
        nextItemId += 1

        snapshot.insertItems([beforeItem], beforeItem: currentItem)
        snapshot.insertItems([afterItem], afterItem: currentItem)
        lastInsertedItems = [beforeItem, afterItem]

        // Current page shifts by 1 because of the item inserted before
        currentPage += 1
        lastUpdatedUUID = UUID()
    }

    func deleteInsertedItems() {
        guard !lastInsertedItems.isEmpty else { return }
        let items = snapshot.itemIdentifiers
        let existing = lastInsertedItems.filter { items.contains($0) }
        guard !existing.isEmpty else { return }

        // Count how many deleted items are before the current page
        let deletedBeforeCount = existing.filter { item in
            guard let idx = items.firstIndex(of: item) else { return false }
            return idx < currentPage
        }.count

        // If the current page item is being deleted, stay on the same index
        // (which will now show the next item), but also adjust for items removed before
        let currentItem = items[currentPage]
        let isCurrentDeleted = existing.contains(currentItem)

        snapshot.deleteItems(existing)
        lastInsertedItems = []

        currentPage -= deletedBeforeCount
        if isCurrentDeleted {
            // Clamp to valid range after deletion
            currentPage = min(currentPage, snapshot.numberOfItems - 1)
        }
        lastUpdatedUUID = UUID()
    }

    func goToNextAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.goToNext()
        }
    }
}

// MARK: - Models

enum ItemColor: Sendable {
    case red, blue, green, orange, purple, pink, cyan, yellow

    var color: Color {
        switch self {
        case .red: .red
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .purple: .purple
        case .pink: .pink
        case .cyan: .cyan
        case .yellow: .yellow
        }
    }
}

struct RotationTestItem: nonisolated Hashable, Sendable {
    let id: Int
    let itemColor: ItemColor
    let label: String
}

struct RotationTestPageInfo: PageInfo {
    var page: Int
    var direction: PageDirection

    init(page: Int, direction: PageDirection) {
        self.page = page
        self.direction = direction
    }
}

struct RotationTestPageChange: PageChange {
    var pageInfo: RotationTestPageInfo
    var animated: Bool
}

// MARK: - Cell View

struct RotationTestCell: View {
    let item: RotationTestItem
    let index: Int
    var onInsert: (() -> Void)?
    var onDelete: (() -> Void)?
    var onDelayedNext: (() -> Void)?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                item.itemColor.color
                VStack(spacing: 12) {
                    Text(item.label)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text("\(Int(geo.size.width)) x \(Int(geo.size.height))")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.8))
                    Text("Index: \(index)")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.6))

                    HStack(spacing: 12) {
                        cellButton("Insert ±1") { onInsert?() }
                        cellButton("Delete ±1") { onDelete?() }
                        cellButton("Next in 3s") { onDelayedNext?() }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private func cellButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.callout.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.white)
    }
}

