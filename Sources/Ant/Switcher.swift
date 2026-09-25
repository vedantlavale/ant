import SwiftUI

// ⌥Tab: the tabs you were last on, most recent first, the way ⌘Tab goes
// through apps. Hold ⌥, press Tab to move along (⇧ to go back), and let go
// to land. The order is taken once when ⌥Tab is first pressed and held still
// until it is let go — landing on a tab makes it the most recent, and a list
// that reordered itself under the key would never get past the second tab.
// ⌃Tab still walks the row in order.

extension Browser {
    /// The tabs of the space on screen, most recently looked at first: the
    /// one you are on, then the one before it, and so on.
    private var recentOrder: [Tab] {
        let others = tabs.filter { !$0.bench && $0.id != activeID }
            .sorted { $0.touched > $1.touched }
        return (active.map { [$0] } ?? []) + others
    }

    /// Tab pressed with ⌥ held: the first press brings the list up on the
    /// tab you were on before this one; each press after moves one along.
    func switchRecent(_ by: Int) {
        if switching.isEmpty {
            let order = recentOrder
            guard order.count > 1 else { return }
            switching = order.map(\.id)
            switchedTo = by > 0 ? 1 : order.count - 1
            return
        }
        let count = switching.count
        switchedTo = ((switchedTo + by) % count + count) % count
    }

    /// ⌥ let go of: the tab the list stopped on comes to the front.
    func landSwitch() {
        guard !switching.isEmpty else { return }
        let picked = switching.indices.contains(switchedTo) ? switching[switchedTo] : nil
        switching = []
        if let picked, let tab = tabs.first(where: { $0.id == picked }) { select(tab) }
    }

    /// Escape, or the app left behind: the list goes and nothing moves.
    func cancelSwitch() {
        switching = []
    }
}

/// The list itself, over the middle of the window.
struct Switcher: View {
    @ObservedObject var browser: Browser

    private var rows: [Tab] {
        browser.switching.compactMap { id in browser.tabs.first { $0.id == id } }
    }

    var body: some View {
        if !browser.switching.isEmpty {
            // At most nine, around the one picked, so a long row doesn't
            // stretch the list past the window.
            let all = rows
            let picked = min(browser.switchedTo, max(0, all.count - 1))
            let start = max(0, min(picked - 4, all.count - 9))
            let shown = Array(all.enumerated()).dropFirst(start).prefix(9)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(shown), id: \.element.id) { index, tab in
                    HStack(spacing: 10) {
                        Mark(icon: tab.icon, letter: tab.monogram, size: 16, dim: tab.asleep)
                        Text(tab.label)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 12)
                        if let host = tab.address?.host() {
                            Text(host.replacingOccurrences(of: "www.", with: ""))
                                .font(.system(size: 11.5))
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(index == picked ? Palette.wash : Color.clear)
                    )
                }
            }
            .padding(6)
            .frame(width: 420)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.ground)
                    .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.hairline)
            )
            .transition(.scale(scale: 0.97).combined(with: .opacity))
        }
    }
}
