//
//  RepositoryIssueSummaryModel.swift
//  Freetime
//
//  Created by Ryan Nystrom on 9/3/17.
//  Copyright © 2017 Ryan Nystrom. All rights reserved.
//

import Foundation
import IGListKit

class RepositoryIssueSummaryModel: ListDiffable {

    let id: String
    let title: NSAttributedStringSizing
    let number: Int
    let created: Date
    let author: String
    let status: IssueStatus
    let pullRequest: Bool

    init(
        id: String,
        title: NSAttributedStringSizing,
        number: Int,
        created: Date,
        author: String,
        status: IssueStatus,
        pullRequest: Bool
        ) {
        self.id = id
        self.title = title
        self.number = number
        self.created = created
        self.author = author
        self.status = status
        self.pullRequest = pullRequest
    }

    // MARK: ListDiffable

    func diffIdentifier() -> NSObjectProtocol {
        return id as NSObjectProtocol
    }

    func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        if self === object { return true }
        guard let object = object as? RepositoryIssueSummaryModel else { return false }
        return id == object.id
            && number == object.number
            && pullRequest == object.pullRequest
            && status == object.status
            && author == object.author
            && created == object.created
            && title.attributedText.string == object.title.attributedText.string
    }
}
