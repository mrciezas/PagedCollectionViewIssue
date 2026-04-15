//
//  RotationTestView.swift
//  PagedCollectionView
//
//  Created by Christian Cieza on 15/04/26.
//

import SwiftUI
import Combine

struct RotationTestView: View {

    @StateObject private var viewModel = RotationTestViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PageCollectionView(
                snapshot: viewModel.snapshot,
                lastUpdatedUUID: viewModel.lastUpdatedUUID,
                currentPage: viewModel.currentPage,
                accessibilityIdentifier: "CollectionView: RotationTest",
                page: viewModel.pageSubject,
                willChangePage: viewModel.willChangePage,
                willBeginDragging: nil,
                scrollTo: viewModel.scrollTo,
                cellProvider: viewModel.cellProvider
            )
            .collectionViewBackgroundColor(.black)
            .ignoresSafeArea()

            VStack {
                Text("Page \(viewModel.currentPage + 1) of \(viewModel.itemCount)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer()

                HStack(spacing: 20) {
                    Button("< Prev") {
                        viewModel.goToPrevious()
                    }
                    Button("Next >") {
                        viewModel.goToNext()
                    }
                }
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(.bottom, 40)
            }
            .padding(.top, 60)
        }
    }
}

#Preview {
    RotationTestView()
}
