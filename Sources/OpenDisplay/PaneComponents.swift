// Shared building blocks for the control-panel detail panes: a section title, a
// glass card container, and a key/value row. Hoisted here once a second pane needed
// them (Resolution/Brightness/Display/Settings all use PaneTitle; the latter three
// share Card; Display and Settings share InfoRow). Pane-specific rows stay with their
// one pane instead. NOT responsible for: any pane's layout or state.

import SwiftUI

struct PaneTitle: View {
    let title: String; let sub: String?
    init(_ t: String, sub: String?) { title = t; self.sub = sub }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2).fontWeight(.semibold)
            if let sub { Text(sub).font(.callout).foregroundStyle(.secondary) }
        }
        .padding(.bottom, 4)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08)))
    }
}

struct InfoRow: View {
    let k: String; let v: String
    init(_ k: String, _ v: String) { self.k = k; self.v = v }
    var body: some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v) }
    }
}
