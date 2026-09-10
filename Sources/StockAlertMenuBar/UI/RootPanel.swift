import AppKit
import SwiftUI

struct RootPanel: View {
    @Environment(MenuSession.self) private var session

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
            Divider().opacity(0.35)
            ActivityList()
            Divider().opacity(0.35)
            FooterBar()
        }
        .frame(width: 332)
        .padding(12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16, style: .continuous))
        .containerBackground(.clear, for: .window)
        .onAppear {
            session.clearTriggered()
        }
        .task {
            session.start()
        }
    }
}

struct HeaderBar: View {
    @Environment(MenuSession.self) private var session

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            BrandMark()
                .layoutPriority(1)
            Spacer(minLength: 8)
            if session.isSignedIn {
                StatusFilterControl()
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 12)
    }
}

struct StatusFilterControl: View {
    @Environment(MenuSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(session.statusFilterSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 9)
            .padding(.trailing, 7)
            .padding(.vertical, 5)
            .frame(minHeight: 24)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering || showing ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: hovering)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: showing)
            }
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .help("Status")
        .accessibilityLabel("Status")
        .accessibilityValue(session.statusFilterSummary)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            StatusFilterMenu()
                .environment(session)
        }
    }
}

private struct StatusFilterMenu: View {
    @Environment(MenuSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(ActivityStatus.allCases) { status in
                Toggle(status.label, isOn: Binding(
                    get: { session.selectedStatuses.contains(status) },
                    set: { _ in session.toggleStatus(status) }
                ))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
        .padding(.trailing, 14)
    }
}

struct PressScaleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct BrandMark: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if let bell = BrandAsset.image(
                named: colorScheme == .dark ? "BellOnDark" : "BellOnLight"
            ) {
                Image(nsImage: bell)
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
            }

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("StockAlert")
                    .foregroundStyle(.primary)
                Text(".pro")
                    .foregroundStyle(Palette.accent)
            }
            .font(.system(size: 17, weight: .semibold, design: .rounded))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("StockAlert.pro")
    }
}

struct ActivityList: View {
    @Environment(MenuSession.self) private var session

    var body: some View {
        Group {
            if session.isLoading && session.items.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 88)
            } else if !session.isSignedIn {
                EmptyActivity(kind: .signedOut)
            } else if session.visibleItems.isEmpty {
                EmptyActivity(kind: session.items.isEmpty ? .none : .filtered)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 2) {
                        ForEach(session.visibleItems) { item in
                            ActivityRow(item: item)
                        }
                    }
                }
                .scrollIndicators(.visible)
                .contentMargins(.bottom, 16, for: .scrollContent)
                .frame(height: 352)
                .accessibilityLabel("Activity")
            }
        }
        .padding(.vertical, 8)
    }
}

struct EmptyActivity: View {
    @Environment(MenuSession.self) private var session
    let kind: Kind

    enum Kind {
        case signedOut
        case none
        case filtered
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if kind == .filtered {
                Button {
                    session.selectStatuses(ActivityStatus.defaultSelection)
                } label: {
                    Text("Show Created and Triggered")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        }
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityHint("Resets the status filter.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 16)
    }

    private var title: String {
        switch kind {
        case .signedOut: "Sign in to see alerts"
        case .none: "No activity yet"
        case .filtered: "No matching activity"
        }
    }

    private var detail: String {
        switch kind {
        case .signedOut: "Use the same account as app.stockalert.pro."
        case .none: "Alerts from the last 7 days show up here."
        case .filtered: "Nothing in the last 7 days for this filter."
        }
    }
}

struct ActivityRow: View {
    @Environment(MenuSession.self) private var session
    let item: ActivityItem
    @State private var hovering = false

    var body: some View {
        Button {
            session.openItem(item)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                StockMark(symbol: item.symbol, actionType: item.actionType)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.symbol)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text(item.action)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.action(item.actionType))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(RelativeTime.string(from: item.firedAt))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    if !item.summary.isEmpty {
                        Text(item.summary)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.06) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(!item.canOpen)
        .accessibilityLabel("\(item.symbol), \(item.action), \(item.summary), \(RelativeTime.string(from: item.firedAt))")
    }
}

struct FooterBar: View {
    @Environment(MenuSession.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            if let notice = session.notice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if session.isSignedIn {
                if let email = session.email {
                    AccountIdentity(email: email)
                }
                HStack(spacing: 8) {
                    PanelButton(title: "New alert", systemImage: "plus") {
                        session.openNewAlert()
                    }
                    PanelButton(title: "Sign out", systemImage: "person.crop.circle.badge.minus") {
                        session.signOut()
                    }
                    PanelButton(title: "Quit", systemImage: "power") {
                        session.quit()
                    }
                }
            } else {
                HStack(spacing: 8) {
                    PanelButton(
                        title: session.isSigningIn ? "Signing in..." : "Sign in",
                        systemImage: "person.crop.circle.badge.plus"
                    ) {
                        session.signInFromBrowser()
                    }
                    PanelButton(title: "Quit", systemImage: "power") {
                        session.quit()
                    }
                }
            }
        }
        .padding(.top, 10)
    }
}

struct AccountIdentity: View {
    let email: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Signed in")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(email)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(email)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signed in as \(email)")
    }
}

struct PanelButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: hovering)
                }
                .accessibilityLabel(title)
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
    }
}
