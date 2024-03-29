//
//  TextToastView.swift
//  Toast
//
//  Created by Bastiaan Jansen on 29/06/2021.
//

import Foundation
import UIKit

public class TextToastView: UIStackView {
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        return label
    }()

    private lazy var subtitleLabel: UILabel = .init()

    public init(_ title: NSAttributedString, subtitle: NSAttributedString? = nil) {
        super.init(frame: CGRect.zero)
        commonInit()

        titleLabel.attributedText = title
        addArrangedSubview(titleLabel)

        if let subtitle = subtitle {
            subtitleLabel.attributedText = subtitle
            addArrangedSubview(subtitleLabel)
        }
    }

    public init(_ title: String, subtitle: String? = nil) {
        super.init(frame: CGRect.zero)
        commonInit()

        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        addArrangedSubview(titleLabel)

        if let subtitle = subtitle {
            subtitleLabel.textColor = .systemGray
            subtitleLabel.text = subtitle
            subtitleLabel.font = .systemFont(ofSize: 12, weight: .bold)
            addArrangedSubview(subtitleLabel)
        }
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func commonInit() {
        axis = .vertical
        alignment = .center
        distribution = .fillEqually
    }
}
