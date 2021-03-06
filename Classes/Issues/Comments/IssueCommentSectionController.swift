//
//  IssueCommentSectionController.swift
//  Freetime
//
//  Created by Ryan Nystrom on 5/19/17.
//  Copyright © 2017 Ryan Nystrom. All rights reserved.
//

import UIKit
import IGListKit
import TUSafariActivity

protocol IssueCommentSectionControllerDelegate: class {
    func didEdit(sectionController: IssueCommentSectionController)
}

final class IssueCommentSectionController: ListBindingSectionController<IssueCommentModel>,
    ListBindingSectionControllerDataSource,
    ListBindingSectionControllerSelectionDelegate,
    IssueCommentDetailCellDelegate,
IssueCommentReactionCellDelegate,
AttributedStringViewIssueDelegate {

    private var collapsed = true
    private let generator = UIImpactFeedbackGenerator()
    private let client: GithubClient
    private let model: IssueDetailsModel
    private weak var delegate: IssueCommentSectionControllerDelegate? = nil

    private lazy var webviewCache: WebviewCellHeightCache = {
        return WebviewCellHeightCache(sectionController: self)
    }()
    private lazy var photoHandler: PhotoViewHandler = {
        return PhotoViewHandler(viewController: self.viewController)
    }()
    private lazy var imageCache: ImageCellHeightCache = {
        return ImageCellHeightCache(sectionController: self)
    }()

    // set when sending a mutation and override the original issue query reactions
    private var reactionMutation: IssueCommentReactionViewModel? = nil

    // set and reload to enter "editing" UI mode
    private var editing = false

    init(model: IssueDetailsModel, client: GithubClient, delegate: IssueCommentSectionControllerDelegate) {
        self.model = model
        self.client = client
        self.delegate = delegate
        super.init()
        self.dataSource = self
        self.selectionDelegate = self
    }

    override func didUpdate(to object: Any) {
        super.didUpdate(to: object)

        // set the inset based on whether or not this is part of a comment thread
        guard let object = self.object else { return }
        switch object.threadState {
        case .single:
            inset = Styles.Sizes.listInsetLarge
        case .neck:
            inset = .zero
        case .tail:
            inset = Styles.Sizes.listInsetLargeTail
        }
    }

    // MARK: Private API

    func shareAction(sender: UIView) -> UIAlertAction? {
        guard let number = object?.number,
            let url = URL(string: "https://github.com/\(model.owner)/\(model.repo)/issues/\(model.number)#issuecomment-\(number)")
        else { return nil }
        weak var weakSelf = self
        
        return AlertAction(AlertActionBuilder { $0.rootViewController = weakSelf?.viewController })
            .share([url], activities: [TUSafariActivity()]) { $0.popoverPresentationController?.sourceView = sender }
    }

    func edit() -> UIAlertAction? {
        return nil
    }

    @discardableResult
    private func uncollapse() -> Bool {
        guard collapsed else { return false }
        collapsed = false
        // clear any collapse state before updating so we don't have a dangling overlay
        for cell in collectionContext?.visibleCells(for: self) ?? [] {
            if let cell = cell as? CollapsibleCell {
                cell.setCollapse(visible: false)
            }
        }
        update(animated: true)
        return true
    }

    private func react(content: ReactionContent, isAdd: Bool) {
        guard let object = self.object else { return }

        let previousReaction = reactionMutation
        reactionMutation = IssueLocalReaction(
            fromServer: object.reactions,
            previousLocal: reactionMutation,
            content: content,
            add: isAdd
        )
        update(animated: true)
        generator.impactOccurred()

        client.react(subjectID: object.id, content: content, isAdd: isAdd) { [weak self] result in
            if result == nil {
                self?.reactionMutation = previousReaction
                self?.update(animated: true)
            }
        }
    }

    // MARK: ListBindingSectionControllerDataSource

    func sectionController(
        _ sectionController: ListBindingSectionController<ListDiffable>,
        viewModelsFor object: Any
        ) -> [ListDiffable] {
        guard let object = self.object else { return [] }

        var bodies = [ListDiffable]()
        for body in object.bodyModels {
            bodies.append(body)
            if collapsed && body === object.collapse?.model {
                break
            }
        }

        return [ object.details ]
            + bodies
            + [ reactionMutation ?? object.reactions ]
    }

    func sectionController(
        _ sectionController: ListBindingSectionController<ListDiffable>,
        sizeForViewModel viewModel: Any,
        at index: Int
        ) -> CGSize {
        guard let width = collectionContext?.containerSize.width
            else { fatalError("Collection context must be set") }

        let height: CGFloat
        if collapsed && (viewModel as AnyObject) === object?.collapse?.model {
            height = object?.collapse?.height ?? 0
        } else if viewModel is IssueCommentReactionViewModel {
            height = 40.0
        } else if viewModel is IssueCommentDetailsViewModel {
            height = Styles.Sizes.rowSpacing * 3 + Styles.Sizes.avatar.height
        } else {
            height = BodyHeightForComment(
                viewModel: viewModel,
                width: width,
                webviewCache: webviewCache,
                imageCache: imageCache
            )
        }

        return CGSize(width: width, height: height)
    }

    func sectionController(
        _ sectionController: ListBindingSectionController<ListDiffable>,
        cellForViewModel viewModel: Any,
        at index: Int
        ) -> UICollectionViewCell {
        guard let context = self.collectionContext else { fatalError("Collection context must be set") }

        let cellClass: AnyClass
        switch viewModel {
        case is IssueCommentDetailsViewModel: cellClass = IssueCommentDetailCell.self
        case is IssueCommentReactionViewModel: cellClass = IssueCommentReactionCell.self
        default: cellClass = CellTypeForComment(viewModel: viewModel)
        }
        let cell = context.dequeueReusableCell(of: cellClass, for: self, at: index)

        // extra config outside of bind API. applies to multiple cell types.
        if let cell = cell as? CollapsibleCell {
            cell.setCollapse(visible: collapsed && (viewModel as AnyObject) === object?.collapse?.model)
        }

        // connect specific cell delegates
        if let cell = cell as? IssueCommentDetailCell {
            cell.setBorderVisible(object?.threadState == .single)
            cell.delegate = self
        } else if let cell = cell as? IssueCommentReactionCell {
            let threadState = object?.threadState
            let showBorder = threadState == .single || threadState == .tail
            cell.setBorderVisible(showBorder)
            cell.delegate = self
        }

        ExtraCommentCellConfigure(
            cell: cell,
            imageDelegate: photoHandler,
            htmlDelegate: webviewCache,
            htmlNavigationDelegate: viewController,
            attributedDelegate: viewController,
            issueAttributedDelegate: self,
            imageHeightDelegate: imageCache
        )

        return cell
    }

    // MARK: ListBindingSectionControllerSelectionDelegate

    func sectionController(
        _ sectionController: ListBindingSectionController<ListDiffable>,
        didSelectItemAt index: Int,
        viewModel: Any
        ) {
        switch viewModel {
        case is IssueCommentReactionViewModel,
             is IssueCommentDetailsViewModel: return
        default: break
        }
        uncollapse()
    }

    // MARK: IssueCommentDetailCellDelegate

    func didTapMore(cell: IssueCommentDetailCell, sender: UIView) {
        let alert = UIAlertController.configured(preferredStyle: .actionSheet)
        alert.popoverPresentationController?.sourceView = sender
        alert.addActions([
            shareAction(sender: sender),
            AlertAction.cancel()
        ])
        viewController?.present(alert, animated: true)
    }

    func didTapProfile(cell: IssueCommentDetailCell) {
        guard let login = object?.details.login else { return }
        viewController?.presentProfile(login: login)
    }

    // MARK: IssueCommentReactionCellDelegate

    func didAdd(cell: IssueCommentReactionCell, reaction: ReactionContent) {
        react(content: reaction, isAdd: true)
    }

    func didRemove(cell: IssueCommentReactionCell, reaction: ReactionContent) {
        react(content: reaction, isAdd: false)
    }

    // MARK: AttributedStringViewIssueDelegate

    func didTapIssue(view: AttributedStringView, issue: IssueDetailsModel) {
        let controller = IssuesViewController(client: client, model: issue)
        viewController?.show(controller, sender: nil)
    }

}
