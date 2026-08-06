import SwiftUI
import UIKit

struct SmallThingsImageContent: View {
    let imageData: Data
    var height: CGFloat? = nil

    var body: some View {
        Group {
            if let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                generatedPlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("小事图片，暖色晚霞占位图")
    }

    private var generatedPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.primary300, Theme.primary, Theme.roleBlush],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Theme.surfaceWarm.opacity(0.9))
                .frame(width: 88, height: 88)
                .offset(x: 78, y: -48)
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Theme.onPrimary.opacity(0.95))
        }
    }
}

struct SmallThingsImagePreview: View {
    let imageData: Data?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let imageData {
                if let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("小事大图")
                } else {
                    SmallThingsImageContent(imageData: imageData)
                        .padding(Theme.Spacing.medium)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.68), in: Circle())
            }
            .foregroundStyle(.white)
            .padding(Theme.Spacing.medium)
            .accessibilityLabel("关闭大图预览")
        }
    }
}
