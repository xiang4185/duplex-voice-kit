import PhotosUI
import SwiftUI
import UIKit

struct SmallThingComposerView: View {
    @ObservedObject var store: SmallThingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var type: SmallThingEntryType
    @State private var title = ""
    @State private var details = ""
    @State private var amount = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var imageLoadFailed = false
    @State private var showsDetails = false
    @State private var saveFeedback = 0
    @FocusState private var focusedField: Field?

    init(store: SmallThingsStore, initialType: SmallThingEntryType) {
        self.store = store
        _type = State(initialValue: initialType)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                    typeSelector

                    if type == .note {
                        noteCanvas
                        imageSection
                    } else {
                        expenseCanvas
                    }

                    if let validationMessage = store.validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            .font(Theme.footnoteFont)
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("无法保存：\(validationMessage)")
                    }

                    guidance
                }
                .padding(.horizontal, Theme.Spacing.medium)
                .padding(.top, Theme.Spacing.medium)
                .padding(.bottom, Theme.Spacing.large)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focusedField) { _, field in
                guard let field else { return }
                if !reduceMotion {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(field, anchor: .center)
                    }
                }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("记下来")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            saveBar
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    focusedField = nil
                }
            }
        }
        .sensoryFeedback(.success, trigger: saveFeedback)
        .onChange(of: type) { _, _ in
            WarmHaptics.action()
            store.clearValidation()
            focusedField = nil
            showsDetails = !details.isEmpty
        }
        .onChange(of: photoItem) { _, newItem in
            loadPhoto(newItem)
        }
        .onDisappear {
            store.clearValidation()
        }
    }

    private var typeSelector: some View {
        Picker("记录类型", selection: $type) {
            Text("小记")
                .tag(SmallThingEntryType.note)
                .accessibilityIdentifier("smallThings.form.type.note")
            Text("账目")
                .tag(SmallThingEntryType.expense)
                .accessibilityIdentifier("smallThings.form.type.expense")
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("记录类型")
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Button {
                focusedField = nil
                Task { await save() }
            } label: {
                HStack(spacing: Theme.Spacing.xSmall) {
                    if store.isLoading {
                        ProgressView()
                            .tint(Theme.onPrimary)
                    }
                    Text("记下来")
                        .font(Theme.headlineFont)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(Theme.primary)
            .disabled(!canSave || store.isLoading)
            .accessibilityIdentifier("smallThings.form.save")
            .accessibilityHint(type == .note ? "保存小记并返回时间流" : "保存待审批账目并返回时间流")
            .id(Field.save)
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.small)
        }
        .background(.ultraThinMaterial)
    }

    private var noteCanvas: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            TextField("给这件小事起个名字（可选）", text: $title)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .focused($focusedField, equals: .title)
                .submitLabel(.next)
                .onSubmit { focusedField = .details }
                .id(Field.title)

            Divider().overlay(Theme.border)

            TextEditor(text: $details)
                .frame(minHeight: 150)
                .scrollContentBackground(.hidden)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textPrimary)
                .focused($focusedField, equals: .details)
                .accessibilityLabel("小记正文")
                .id(Field.details)
                .overlay(alignment: .topLeading) {
                    if details.isEmpty {
                        Text("写点什么…")
                            .font(Theme.bodyFont)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(18)
        .background(Theme.v2PaperMuted.opacity(0.7), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var expenseCanvas: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("金额")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("¥")
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.primary)
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .focused($focusedField, equals: .amount)
                        .accessibilityLabel("金额，最多两位小数")
                        .id(Field.amount)
                }
                Text("还可以一起记 \(store.remainingAmount.formatted(.number.precision(.fractionLength(2)))) 元")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Divider().overlay(Theme.border)

            VStack(alignment: .leading, spacing: 6) {
                Text("花在什么上")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
                TextField("例如：奶茶", text: $title)
                    .font(.system(size: 21, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.done)
                    .id(Field.title)
            }

            optionalDetails
        }
        .padding(18)
        .background(Theme.v2PaperMuted.opacity(0.7), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var optionalDetails: some View {
        if showsDetails || !details.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("补充一句（可选）")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
                TextEditor(text: $details)
                .frame(minHeight: 86)
                .scrollContentBackground(.hidden)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textPrimary)
                .focused($focusedField, equals: .details)
                .accessibilityLabel("账目补充说明")
                .id(Field.details)
                .padding(8)
                .background(Theme.v2Paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        } else {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    showsDetails = true
                }
                focusedField = .details
            } label: {
                Label("补充一句（可选）", systemImage: "plus.bubble")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(Theme.primary)
        }
    }

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            Text("配一张图")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)

            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(
                        imageData == nil ? "选择图片" : "更换图片",
                        systemImage: imageData == nil ? "photo.badge.plus" : "arrow.triangle.2.circlepath"
                    )
                    .font(Theme.subheadFont.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: Theme.buttonMinimumHeight)
                }
                .buttonStyle(.bordered)
                .tint(Theme.primary)
                .accessibilityIdentifier("smallThings.form.imagePicker")

                if let imageData {
                    SmallThingsImageContent(imageData: imageData, height: 210)
                        .accessibilityLabel("所选图片预览")

                    Button(role: .destructive) {
                        self.imageData = nil
                        photoItem = nil
                        imageLoadFailed = false
                    } label: {
                        Label("移除图片", systemImage: "trash")
                    }
                    .font(Theme.footnoteFont)
                }

                if imageLoadFailed {
                    Label("图片读取失败，请重新选择。", systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.footnoteFont)
                        .foregroundStyle(Theme.danger)
                }
            }
            .padding(Theme.Spacing.small)
            .background(Theme.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            }
        }
    }

    private var guidance: some View {
        Label {
            Text(
                type == .note
                    ? (store.isProduction
                        ? "图片会先在本机压缩并移除定位等元数据，再通过鉴权上传保存。"
                        : "图片只保存在本次离线 Mock 的内存中，退出 App 后不会持久化。")
                    : "保存后会标记为“等对方看”，等待对方在审批页点头或打回。"
            )
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: type == .note ? "lock.shield" : "clock.badge.checkmark")
        }
        .font(Theme.footnoteFont)
        .foregroundStyle(Theme.textSecondary)
    }

    private var canSave: Bool {
        switch type {
        case .note:
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .expense:
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let value = SmallThingsStore.validAmount(from: amount) else {
                return false
            }
            return value <= store.remainingAmount
        }
    }

    private func save() async {
        let saved: Bool
        switch type {
        case .note:
            saved = await store.addNotePersisted(
                title: title,
                body: details,
                imageData: imageData
            )
        case .expense:
            saved = await store.addExpensePersisted(
                purpose: title,
                amountText: amount,
                note: details
            )
        }

        guard saved else {
            focusedField = .save
            return
        }
        saveFeedback += 1
        dismiss()
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                let data = try await item.loadTransferable(type: Data.self)
                await MainActor.run {
                    imageData = data
                    imageLoadFailed = data == nil
                }
            } catch {
                await MainActor.run {
                    imageData = nil
                    imageLoadFailed = true
                }
            }
        }
    }
}

private extension SmallThingComposerView {
    enum Field: Hashable {
        case title
        case amount
        case details
        case save
    }
}
