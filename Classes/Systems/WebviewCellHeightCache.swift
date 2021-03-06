//
//  WebviewCellHeightCache.swift
//  Freetime
//
//  Created by Ryan Nystrom on 7/5/17.
//  Copyright © 2017 Ryan Nystrom. All rights reserved.
//

import Foundation
import IGListKit

final class WebviewCellHeightCache: IssueCommentHtmlCellDelegate {

    private var htmlSizes = [String: CGSize]()
    private weak var sectionController: ListSectionController? = nil

    init(sectionController: ListSectionController) {
        self.sectionController = sectionController
    }

    // MARK: Public API

    func height(model: IssueCommentHtmlModel) -> CGFloat {
        return htmlSizes[model.html]?.height ?? Styles.Sizes.tableCellHeight
    }

    // MARK: IssueCommentHtmlCellDelegate

    func webViewDidResize(cell: IssueCommentHtmlCell, html: String, size: CGSize) {
        guard let sectionController = self.sectionController,
            sectionController.section != NSNotFound,
            size != htmlSizes[html]
            else { return }

        htmlSizes[html] = size

        // temporary hack until this PR lands
        // https://github.com/Instagram/IGListKit/pull/931

        let layout = (sectionController.collectionContext as! ListAdapter).collectionView?.collectionViewLayout
        layout?.invalidateLayout()

//        UIView.performWithoutAnimation {
//            sectionController.collectionContext?.invalidateLayout(for: sectionController)
//        }
    }

}

