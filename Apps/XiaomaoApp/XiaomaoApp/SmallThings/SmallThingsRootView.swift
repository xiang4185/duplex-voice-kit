import SwiftUI

struct SmallThingsRootView: View {
    @ObservedObject var store: SmallThingsStore
    @State private var path: [SmallThingsRoute] = []
    @Environment(\.appVisualMode) private var visualMode

    private var visual: Theme.VisualTokens { Theme.visual(visualMode) }

    init(store: SmallThingsStore) {
        self.store = store
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.medium) {
                    if store.isLoading && store.entries.isEmpty {
                        ProgressView("正在加载小事…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.xLarge)
                    }

                    if let error = store.operationError {
                        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                            Text(error)
                                .font(Theme.subheadFont)
                                .foregroundStyle(Theme.textPrimary)
                            Button("重试") {
                                Task { await store.refreshFromBackend() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.primary)
                        }
                        .padding(Theme.Spacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .warmCard()
                    }

                    SmallThingsLedgerCard(
                        store: store,
                        addExpense: { path.append(.composer(.expense)) },
                        openApprovals: { path.append(.approval) },
                        openBinding: { path.append(.binding) }
                    )

                    flowHeader

                    if store.sortedEntries.isEmpty && !store.isLoading {
                        emptyTimeline
                    } else {
                        ForEach(store.sortedEntries) { entry in
                            SmallThingEntryCard(store: store, entry: entry)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.medium)
                .padding(.top, Theme.Spacing.small)
                .padding(.bottom, Theme.Spacing.large)
            }
            .scrollIndicators(.hidden)
            .background(visual.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SmallThingsRoute.self) { route in
                switch route {
                case .composer(let initialType):
                    SmallThingComposerView(store: store, initialType: initialType)
                case .binding:
                    SmallThingsBindingView(store: store)
                case .approval:
                    SmallThingsApprovalView(store: store)
                }
            }
        }
        .accessibilityIdentifier("smallThings.root")
        .task {
            if store.isProduction {
                await store.refreshFromBackend()
            }
        }
    }

    private var flowHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            HStack(alignment: .firstTextBaseline) {
                Text("生活时间流")
                    .font(Theme.title3Font)
                    .foregroundStyle(visual.textPrimary)
                Spacer(minLength: Theme.Spacing.small)
                Text("共 \(store.entries.count) 件")
                    .font(Theme.captionFont)
                    .foregroundStyle(visual.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(visual.surfaceSoft, in: Capsule())
            }
            HStack(spacing: Theme.Spacing.xSmall) {
                Text("小事，都值得记下来")
                    .font(Theme.captionFont)
                    .foregroundStyle(visual.textSecondary)
                Spacer(minLength: Theme.Spacing.small)
                if !store.pendingApprovals.isEmpty {
                    Button {
                        path.append(.approval)
                    } label: {
                        Label("待我确认 \(store.pendingApprovals.count)", systemImage: "clock")
                            .font(Theme.captionFont.weight(.semibold))
                            .foregroundStyle(visual.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("smallThings.timeline.pending")
                }
            }
        }
        .padding(.top, Theme.Spacing.xSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("小事时间流，共 \(store.entries.count) 件")
    }

    private var emptyTimeline: some View {
        VStack(spacing: Theme.Spacing.small) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(visual.primary)
            Text("还没有记下小事")
                .font(Theme.headlineFont)
                .foregroundStyle(visual.textPrimary)
            Text("从上面记一笔开始，让两个人的日常慢慢长出来。")
                .font(Theme.captionFont)
                .foregroundStyle(visual.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xLarge)
        .padding(.horizontal, Theme.Spacing.large)
        .background(visual.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .stroke(visual.border.opacity(0.75), lineWidth: 1)
        }
    }
}

private enum SmallThingsRoute: Hashable {
    case composer(SmallThingEntryType)
    case binding
    case approval
}
