import PhotosUI
import SwiftUI
import UIKit

struct SmallThingsRootView: View {
    @StateObject private var store = SmallThingsStore()
    @State private var showingForm = false
    @State private var formType: SmallThingEntryType = .note

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    header
                    ledgerCard
                    HStack {
                        Text("小 事 · 都值得记下来").font(.caption.bold()).foregroundStyle(SmallThingsPalette.secondaryText)
                        Spacer()
                        Text("共 \(store.entries.count) 件").font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(store.sortedEntries) { entry in
                        SmallThingEntryCard(store: store, entry: entry)
                    }
                }
                .padding(16)
            }
            .background(SmallThingsPalette.background.ignoresSafeArea())
            .navigationTitle("小事")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        formType = .note
                        showingForm = true
                    } label: { Image(systemName: "plus") }
                    .accessibilityIdentifier("smallThings.add")
                    .accessibilityLabel("新增小事或账目")
                }
            }
            .sheet(isPresented: $showingForm) {
                SmallThingFormView(store: store, initialType: formType)
            }
        }
        .accessibilityIdentifier("smallThings.root")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("小事").font(.system(size: 34, weight: .bold, design: .serif)).foregroundStyle(SmallThingsPalette.text)
            Text("和图图的小日子").font(.subheadline).foregroundStyle(SmallThingsPalette.secondaryText)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ledgerCard: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("52 元小本本").font(.title3.bold())
                    Text("我和图图的账").font(.caption).foregroundStyle(SmallThingsPalette.secondaryText)
                }
                Spacer()
                Text("待我批 \(store.pendingApprovals.count)").font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 5).background(SmallThingsPalette.primarySoft).clipShape(Capsule())
            }
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(SmallThingsPalette.border, lineWidth: 8)
                    Circle().trim(from: 0, to: store.approvedRatio).stroke(SmallThingsPalette.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int((store.approvedRatio * 100).rounded()))%").bold()
                        Text("已点头").font(.caption2)
                    }
                }.frame(width: 76, height: 76)
                VStack(spacing: 7) {
                    ledgerRow("已点头", store.approvedAmount)
                    ledgerRow("等看看", store.pendingAmount)
                    ledgerRow("还剩下", store.remainingAmount)
                }
            }
            HStack {
                Button("记一笔") { formType = .expense; showingForm = true }
                    .buttonStyle(.borderedProminent).tint(SmallThingsPalette.primary)
                    .accessibilityIdentifier("smallThings.ledger.addExpense")
                NavigationLink("等你点头") { SmallThingsApprovalView(store: store) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("smallThings.ledger.pendingApproval")
            }
            HStack {
                NavigationLink("演示绑定") { SmallThingsBindingView(store: store) }
                    .font(.caption)
                Spacer()
                Text("谁都能记，记了等对方点头").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(SmallThingsPalette.warmSurface)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .shadow(color: .black.opacity(0.06), radius: 14, y: 7)
        .accessibilityIdentifier("smallThings.ledger")
    }

    private func ledgerRow(_ label: String, _ value: Double) -> some View {
        HStack { Text(label).foregroundStyle(SmallThingsPalette.secondaryText); Spacer(); Text(value, format: .number.precision(.fractionLength(2))).bold() }.font(.subheadline)
    }
}

private struct SmallThingEntryCard: View {
    @ObservedObject var store: SmallThingsStore
    let entry: SmallThingEntry
    @State private var commentsOpen = false
    @State private var draft = ""
    @State private var replyTarget: (commentID: UUID, author: SmallThingRequester)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.type == .expense ? entry.title : authorText).font(.headline)
                    Text(entry.type == .expense ? "\(authorText) · 记了一笔账" : "记了一件事").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if entry.type == .expense { Text(entry.amount, format: .number.precision(.fractionLength(2))).font(.title3.bold()).foregroundStyle(SmallThingsPalette.primary) }
            }
            if !entry.body.isEmpty { Text(entry.body).foregroundStyle(SmallThingsPalette.text) }
            if let imageData = entry.imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("小事图片")
            } else if entry.imageData != nil {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [SmallThingsPalette.primarySoft, SmallThingsPalette.primary.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 180)
                    .overlay(Image(systemName: "sun.horizon.fill").font(.system(size: 44)).foregroundStyle(.white))
                    .accessibilityLabel("晚霞占位图")
            }
            if !entry.approvalMessage.isEmpty { Text("审批留言：\(entry.approvalMessage)").font(.caption).padding(9).frame(maxWidth: .infinity, alignment: .leading).background(SmallThingsPalette.primarySoft).clipShape(RoundedRectangle(cornerRadius: 10)) }
            HStack {
                Button { store.toggleReaction(entryID: entry.id) } label: { Label("回应", systemImage: entry.reacted ? "heart.fill" : "heart") }.foregroundStyle(entry.reacted ? SmallThingsPalette.primary : SmallThingsPalette.secondaryText)
                Button { commentsOpen.toggle() } label: { Label("\(entry.comments.count)", systemImage: "bubble.left") }.foregroundStyle(SmallThingsPalette.secondaryText)
                Spacer()
                if let status = entry.expenseStatus { statusLabel(status) }
            }.font(.caption)
            if commentsOpen { commentsSection }
        }
        .padding(14).background(.white).clipShape(RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(SmallThingsPalette.border)).shadow(color: .black.opacity(0.04), radius: 8, y: 4)
    }

    private var authorText: String { entry.requester == .me ? "我" : "图图" }

    @ViewBuilder private func statusLabel(_ status: SmallThingExpenseStatus) -> some View {
        let text = status == .pending ? "等待点头" : status == .approved ? "已点头" : "再想想"
        let color = status == .pending ? SmallThingsPalette.primary : status == .approved ? SmallThingsPalette.success : SmallThingsPalette.danger
        Label(text, systemImage: status == .approved ? "checkmark.circle.fill" : status == .rejected ? "arrow.uturn.backward.circle.fill" : "clock.fill").foregroundStyle(color).font(.caption.bold())
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(entry.comments) { comment in
                VStack(alignment: .leading, spacing: 5) {
                    Button { replyTarget = (comment.id, comment.author) } label: { Text("\(name(comment.author))：\(comment.text)").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                    ForEach(comment.replies) { reply in
                        Button { replyTarget = (comment.id, reply.author) } label: { Text("\(name(reply.author)) 回复 \(name(reply.replyToAuthor))：\(reply.text)").font(.caption).foregroundStyle(SmallThingsPalette.secondaryText).padding(.leading, 14) }.buttonStyle(.plain)
                    }
                }
            }
            HStack {
                TextField(replyTarget == nil ? "说点什么" : "回复 \(name(replyTarget!.author))", text: $draft)
                    .textFieldStyle(.roundedBorder)
                Button("发送") {
                    let sent: Bool
                    if let target = replyTarget { sent = store.addReply(entryID: entry.id, commentID: target.commentID, replyTo: target.author, text: draft) }
                    else { sent = store.addComment(entryID: entry.id, text: draft) }
                    if sent { draft = ""; replyTarget = nil }
                }.buttonStyle(.borderedProminent).tint(SmallThingsPalette.primary).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(10).background(SmallThingsPalette.elevated).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func name(_ author: SmallThingRequester) -> String { author == .me ? "我" : "图图" }
}

struct SmallThingFormView: View {
    @ObservedObject var store: SmallThingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var type: SmallThingEntryType
    @State private var title = ""
    @State private var details = ""
    @State private var amount = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?

    init(store: SmallThingsStore, initialType: SmallThingEntryType) {
        self.store = store
        _type = State(initialValue: initialType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("记录类型", selection: $type) {
                    Text("记个小记").tag(SmallThingEntryType.note).accessibilityIdentifier("smallThings.form.type.note")
                    Text("记一笔账").tag(SmallThingEntryType.expense).accessibilityIdentifier("smallThings.form.type.expense")
                }.pickerStyle(.segmented)
                Section(type == .note ? "记下了什么" : "花在了什么上") { TextField(type == .note ? "标题（可选）" : "用途", text: $title) }
                if type == .expense { Section("金额") { TextField("0.00", text: $amount).keyboardType(.decimalPad); Text("当前可用 \(store.remainingAmount, format: .number.precision(.fractionLength(2))) 元").font(.caption).foregroundStyle(.secondary) } }
                Section("多说一句（可选）") { TextEditor(text: $details).frame(minHeight: 100) }
                if type == .note {
                    Section("配一张图（可选）") {
                        PhotosPicker(selection: $photoItem, matching: .images) { Label(imageData == nil ? "选择图片" : "更换图片", systemImage: "photo") }
                            .onChange(of: photoItem) { _, newValue in Task { imageData = try? await newValue?.loadTransferable(type: Data.self) } }
                        if let selectedImageData = imageData, let image = UIImage(data: selectedImageData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .accessibilityLabel("所选图片预览")
                            Button("移除图片", role: .destructive) {
                                imageData = nil
                                photoItem = nil
                            }
                        }
                    }
                }
                if let message = store.validationMessage { Text(message).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("记下来")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.accessibilityIdentifier("smallThings.form.save") }
            }
        }
    }

    private func save() {
        let ok = type == .note ? store.addNote(title: title, body: details, imageData: imageData) : store.addExpense(purpose: title, amountText: amount, note: details)
        if ok { dismiss() }
    }
}

struct SmallThingsApprovalView: View {
    @ObservedObject var store: SmallThingsStore
    @State private var message = ""
    @State private var showUndo = false
    @State private var undoDismissTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 16) {
            if let entry = store.pendingApprovals.first {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { VStack(alignment: .leading) { Text(entry.title).font(.title2.bold()); Text("图图发起 · 等你看").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(entry.amount, format: .number.precision(.fractionLength(2))).font(.title.bold()).foregroundStyle(SmallThingsPalette.primary) }
                    Text(entry.body).padding().frame(maxWidth: .infinity, alignment: .leading).background(SmallThingsPalette.elevated).clipShape(RoundedRectangle(cornerRadius: 16))
                    TextField("你有话说（可不填）", text: $message, axis: .vertical).textFieldStyle(.roundedBorder)
                }.padding().background(.white).clipShape(RoundedRectangle(cornerRadius: 24))
                HStack {
                    Button("再想想") { review(entry, .rejected) }.buttonStyle(.bordered).tint(SmallThingsPalette.danger).accessibilityIdentifier("smallThings.approval.reject")
                    Button("点头") { review(entry, .approved) }.buttonStyle(.borderedProminent).tint(SmallThingsPalette.primary).accessibilityIdentifier("smallThings.approval.approve")
                }
            } else {
                ContentUnavailableView("都看完了", systemImage: "checkmark.seal", description: Text("目前没有需要你审批的账目"))
            }
            Spacer()
        }
        .padding().background(SmallThingsPalette.background.ignoresSafeArea()).navigationTitle("等你点头")
        .overlay(alignment: .bottom) {
            if showUndo {
                HStack {
                    Text("审批已保存")
                    Button("撤销") {
                        undoDismissTask?.cancel()
                        undoDismissTask = nil
                        store.undoLastReview()
                        showUndo = false
                    }
                }
                .padding()
                .background(.black.opacity(0.85))
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .padding(.bottom, 20)
            }
        }
        .onDisappear {
            undoDismissTask?.cancel()
            undoDismissTask = nil
        }
    }

    private func review(_ entry: SmallThingEntry, _ status: SmallThingExpenseStatus) {
        store.review(entryID: entry.id, status: status, message: message)
        message = ""
        showUndo = true
        undoDismissTask?.cancel()
        undoDismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            showUndo = false
            undoDismissTask = nil
        }
    }
}

struct SmallThingsBindingView: View {
    @ObservedObject var store: SmallThingsStore
    @State private var code = ""

    var body: some View {
        Form {
            Section("本地演示码") {
                Text("842971").font(.system(size: 34, weight: .bold, design: .rounded)).tracking(8).frame(maxWidth: .infinity)
                Text("仅用于离线界面演示，不会建立真实账号、设备或服务端绑定。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("输入六位数字") {
                TextField("000000", text: $code).keyboardType(.numberPad).onChange(of: code) { _, value in code = String(value.filter(\.isNumber).prefix(6)) }.accessibilityIdentifier("smallThings.binding.codeInput")
                Button("提交演示绑定") { _ = store.bindDemo(code: code) }.disabled(code.count != 6).accessibilityIdentifier("smallThings.binding.submit")
            }
            if store.isDemoBound { Label("本地演示绑定成功", systemImage: "checkmark.circle.fill").foregroundStyle(SmallThingsPalette.success) }
            if let message = store.validationMessage { Text(message).foregroundStyle(.red) }
        }.navigationTitle("一起记")
    }
}
