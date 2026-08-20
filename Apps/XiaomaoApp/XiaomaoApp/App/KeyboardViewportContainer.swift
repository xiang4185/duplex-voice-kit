import SwiftUI
import UIKit

/// Single native viewport driver for every keyboard presentation.
///
/// The hosted SwiftUI tree never receives keyboard notifications or computes a
/// keyboard height. UIKit owns the viewport and animates this one bottom
/// constraint with the active keyboard, including interactive dismissal and
/// third-party input methods.
struct KeyboardViewportContainer<Content: View>: UIViewControllerRepresentable {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(context: Context) -> KeyboardViewportViewController<Content> {
        KeyboardViewportViewController(rootView: content)
    }

    func updateUIViewController(
        _ controller: KeyboardViewportViewController<Content>,
        context: Context
    ) {
        controller.update(rootView: content)
    }
}

final class KeyboardViewportViewController<Content: View>: UIViewController {
    private let hostingController: UIHostingController<Content>

    init(rootView: Content) {
        hostingController = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        addChild(hostingController)
        let contentView = hostingController.view!
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)

        let keyboardGuide = view.keyboardLayoutGuide
        keyboardGuide.usesBottomSafeArea = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: keyboardGuide.topAnchor),
        ])
        hostingController.didMove(toParent: self)
    }

    func update(rootView: Content) {
        hostingController.rootView = rootView
    }
}
