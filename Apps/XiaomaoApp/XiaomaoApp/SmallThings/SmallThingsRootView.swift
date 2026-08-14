import SwiftUI

struct SmallThingsRootView: View {
    @ObservedObject var store: SmallThingsStore
    @State private var path: [SmallThingsRoute] = []
    @State private var appeared = false
    @State private var ambientMotion = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appVisualMode) private var visualMode

    private var visual: Theme.VisualTokens { Theme.visual(visualMode) }

    init(store: SmallThingsStore) {
        self.store = store
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 18) {
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
                                WarmHaptics.action()
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
                    .opacity(reduceMotion || appeared ? 1 : 0)
                    .offset(y: reduceMotion || appeared ? 0 : 18)
                    .scaleEffect(reduceMotion || appeared ? 1 : 0.975)
                    .animation(
                        reduceMotion
                            ? nil
                            : .spring(response: 0.52, dampingFraction: 0.84).delay(0.04),
                        value: appeared
                    )

                    flowHeader
                        .opacity(reduceMotion || appeared ? 1 : 0)
                        .offset(y: reduceMotion || appeared ? 0 : 12)
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeOut(duration: 0.42).delay(0.16),
                            value: appeared
                        )

                    if store.sortedEntries.isEmpty && !store.isLoading {
                        emptyTimeline
                    } else {
                        ForEach(store.sortedEntries) { entry in
                            SmallThingEntryCard(store: store, entry: entry)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(smallThingsBackdrop)
            .navigationTitle("小事本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("共 \(store.entries.count) 件")
                        .font(.caption)
                        .foregroundStyle(visual.textSecondary)
                        .accessibilityLabel("共 \(store.entries.count) 件小事")
                }
            }
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
        .onAppear {
            appeared = true
            ambientMotion = true
        }
        .task {
            if store.isProduction {
                await store.refreshFromBackend()
            }
        }
    }

    private var smallThingsBackdrop: some View {
        ZStack {
            Theme.v2Paper
            LinearGradient(
                colors: [Theme.v2CoralSoft.opacity(0.26), .clear, Theme.v2Lavender.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Theme.v2CoralSoft.opacity(0.26))
                .frame(width: 250, height: 250)
                .blur(radius: 54)
                .offset(
                    x: ambientMotion && !reduceMotion ? -112 : -154,
                    y: ambientMotion && !reduceMotion ? -230 : -170
                )
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: 13).repeatForever(autoreverses: true),
                    value: ambientMotion
                )

            Circle()
                .fill(Theme.v2Lavender.opacity(0.18))
                .frame(width: 280, height: 280)
                .blur(radius: 58)
                .offset(
                    x: ambientMotion && !reduceMotion ? 132 : 92,
                    y: ambientMotion && !reduceMotion ? 300 : 360
                )
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: 16).repeatForever(autoreverses: true),
                    value: ambientMotion
                )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var flowHeader: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.small) {
            Text("最近记下")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.v2Ink)
            Spacer(minLength: Theme.Spacing.small)
            if !store.pendingApprovals.isEmpty {
                Button {
                    WarmHaptics.action()
                    path.append(.approval)
                } label: {
                    Label("待我确认 \(store.pendingApprovals.count)", systemImage: "clock")
                        .font(Theme.captionFont.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(visual.primary)
                .accessibilityIdentifier("smallThings.timeline.pending")
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
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
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
