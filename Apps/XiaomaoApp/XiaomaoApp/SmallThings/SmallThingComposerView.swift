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
                        noteFields
                        imageSection
                    } else {
                        expenseFields
                    }

                    detailsField
                    guidance

                    if let validationMessage = store.validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            .font(Theme.footnoteFont)
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("无法保存：\(validationMessage)")
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        Text("保存")
                            .font(Theme.headlineFont)
                            .foregroundStyle(Theme.onPrimary)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(
                                canSave ? Theme.primary : Theme.primary.opacity(0.38),
                                in: RoundedRectangle(
                                    cornerRadius: Theme.Radius.medium,
                                    style: .continuous
                                )
                            )
                            .shadow(
                                color: canSave ? Theme.ctaShadow : .clear,
                                radius: 12,
                                y: 5
                            )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .disabled(!canSave || store.isLoading)
                    .accessibilityIdentifier("smallThings.form.save")
                    .accessibilityHint(type == .note ? "保存小记并返回时间流" : "保存待审批账目并返回时间流")
                    .id(Field.save)
                }
                .padding(.horizontal, Theme.Spacing.medium)
                .padding(.top, Theme.Spacing.medium)
                .padding(.bottom, Theme.Spacing.xLarge)
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
            store.clearValidation()
            focusedField = nil
        }
        .onChange(of: photoItem) { _, newItem in
            loadPhoto(newItem)
        }
        .onDisappear {
            store.clearValidation()
        }
    }

    private var typeSelector: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            Text("想记什么")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)

            Picker("记录类型", selection: $type) {
                Text("记个小记")
                    .tag(SmallThingEntryType.note)
                    .accessibilityIdentifier("smallThings.form.type.note")
                Text("记一笔账")
                    .tag(SmallThingEntryType.expense)
                    .accessibilityIdentifier("smallThings.form.type.expense")
            }
            .pickerStyle(.segmented)
            .tint(Theme.primary)
            .padding(Theme.Spacing.xxSmall)
            .background(Theme.surfaceWarm)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(Theme.border.opacity(0.85), lineWidth: 1)
            }
        }
    }

    private var noteFields: some View {
        inputGroup(title: "标题或内容", hint: "标题和正文至少填写一项") {
            TextField("给这件小事起个名字（可选）", text: $title)
                .focused($focusedField, equals: .title)
                .submitLabel(.next)
                .onSubmit { focusedField = .details }
                .id(Field.title)
        }
    }

    private var expenseFields: some View {
        VStack(spacing: Theme.Spacing.medium) {
            inputGroup(title: "用途", hint: "写清楚这笔钱花在哪里") {
                TextField("例如：奶茶", text: $title)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .amount }
                    .id(Field.title)
            }

            inputGroup(
                title: "金额",
                hint: "当前可用 \(store.remainingAmount.formatted(.number.precision(.fractionLength(2)))) 元"
            ) {
                HStack(spacing: Theme.Spacing.xSmall) {
                    Text("¥")
                        .font(Theme.title3Font)
                        .foregroundStyle(Theme.primary)
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .amount)
                        .accessibilityLabel("金额，最多两位小数")
                }
                .id(Field.amount)
            }
        }
    }

    private var detailsField: some View {
        inputGroup(
            title: type == .note ? "多说一句" : "补充说明",
            hint: type == .note ? "正文也可以写在这里" : "可以告诉对方为什么记这笔账"
        ) {
            TextEditor(text: $details)
                .frame(minHeight: 112)
                .scrollContentBackground(.hidden)
                .focused($focusedField, equals: .details)
                .accessibilityLabel(type == .note ? "小记正文" : "账目补充说明")
                .id(Field.details)
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

    private func inputGroup<Content: View>(
        title: String,
        hint: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            Text(title)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)

            content()
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.Spacing.small)
                .padding(.vertical, 11)
                .background(Theme.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                }

            Text(hint)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
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
