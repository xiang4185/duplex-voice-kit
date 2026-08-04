import SwiftUI

struct SmallThingsRootView: View {
    @StateObject private var store = SmallThingsStore()
    @State private var path: [SmallThingsRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.medium) {
                    SmallThingsLedgerCard(
                        store: store,
                        addExpense: { path.append(.composer(.expense)) },
                        openApprovals: { path.append(.approval) },
                        openBinding: { path.append(.binding) }
                    )

                    flowHeader

                    ForEach(store.sortedEntries) { entry in
                        SmallThingEntryCard(store: store, entry: entry)
                    }
                }
                .padding(.horizontal, Theme.Spacing.medium)
                .padding(.top, Theme.Spacing.small)
                .padding(.bottom, Theme.Spacing.large)
            }
            .background(Theme.bg.ignoresSafeArea())
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
    }

    private var flowHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("小 事")
                .font(Theme.captionFont.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text("· 都值得记下来")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: Theme.Spacing.small)
            Text("共 \(store.entries.count) 件")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("小事时间流，共 \(store.entries.count) 件")
    }
}

private enum SmallThingsRoute: Hashable {
    case composer(SmallThingEntryType)
    case binding
    case approval
}
