//
//  DefaultToastView.swift
//  Toast
//
//  Created by Bastiaan Jansen on 29/06/2021.
//

import Foundation
import UIKit

public class IconAppleToastView: UIStackView {
    private lazy var vStack: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 2
        stackView.alignment = .center

        return stackView
    }()

    private lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 28),
            imageView.heightAnchor.constraint(equalToConstant: 28),
        ])

        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        return label
    }()

    private lazy var subtitleLabel: UILabel = .init()

    public static var defaultImageTint: UIColor {
        if #available(iOS 13.0, *) {
            return .label
        } else {
            return .black
        }
    }

    public init(
        image: UIImage,
        imageTint: UIColor? = defaultImageTint,
        title: NSAttributedString,
        subtitle: NSAttributedString? = nil
    ) {
        super.init(frame: CGRect.zero)
        commonInit()

        titleLabel.attributedText = title
        vStack.addArrangedSubview(titleLabel)

        if let subtitle = subtitle {
            subtitleLabel.attributedText = subtitle
            vStack.addArrangedSubview(subtitleLabel)
        }

        imageView.image = image
        imageView.tintColor = imageTint

        addArrangedSubview(imageView)
        addArrangedSubview(vStack)
    }

    public init(image: UIImage, imageTint: UIColor? = defaultImageTint, title: String, subtitle: String? = nil) {
        super.init(frame: CGRect.zero)
        commonInit()

        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        vStack.addArrangedSubview(titleLabel)

        if let subtitle = subtitle {
            subtitleLabel.textColor = .systemGray
            subtitleLabel.text = subtitle
            subtitleLabel.font = .systemFont(ofSize: 12, weight: .bold)
            vStack.addArrangedSubview(subtitleLabel)
        }

        imageView.image = image
        imageView.tintColor = imageTint

        addArrangedSubview(imageView)
        addArrangedSubview(vStack)
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func commonInit() {
        axis = .horizontal
        spacing = 15
        alignment = .center
        distribution = .fill
    }
}
