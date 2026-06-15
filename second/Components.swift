import SwiftUI

struct AppCard<Content: View>: View {
    let title: String; let content: Content; @State private var isExpanded: Bool
    init(title: String, startsExpanded: Bool = true, @ViewBuilder content: () -> Content) { self.title = title; self.content = content(); self._isExpanded = State(initialValue: startsExpanded) }
    var body: some View { VStack(alignment: .leading, spacing: 12) { Button { withAnimation { isExpanded.toggle() } } label: { HStack { Text(title).font(.headline).foregroundStyle(SecondTheme.primaryText); Spacer(); Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(SecondTheme.secondaryText) } }.buttonStyle(.plain); if isExpanded { content } }.padding().background(SecondTheme.card).overlay(RoundedRectangle(cornerRadius: 18).stroke(SecondTheme.border.opacity(0.7))).clipShape(RoundedRectangle(cornerRadius: 18)).shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4) }
}

struct MetricRow: View { let label: String; let value: String; var color: Color = SecondTheme.secondaryText
    var body: some View { HStack { Text(label).foregroundStyle(SecondTheme.primaryText); Spacer(); Text(value).foregroundStyle(color).multilineTextAlignment(.trailing) }.font(.subheadline) }
}

struct MiniLineChart: View { let values: [Double]; let color: Color
    var body: some View { GeometryReader { g in let minV = values.min() ?? 0; let maxV = values.max() ?? 1; let range = max(maxV-minV, 1); Path { p in for i in values.indices { let x = g.size.width * CGFloat(i) / CGFloat(max(values.count-1,1)); let y = g.size.height - g.size.height * CGFloat((values[i]-minV)/range); i == values.startIndex ? p.move(to: CGPoint(x:x,y:y)) : p.addLine(to: CGPoint(x:x,y:y)) } }.stroke(color, lineWidth: 2) }.frame(height: 46) }
}

struct ScreenHeader: View { let title: String; let subtitle: String?
    var body: some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(.largeTitle).bold().foregroundStyle(SecondTheme.primaryText); if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(SecondTheme.secondaryText) } }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.top, 12) }
}

struct SignalBadge: View { let icon: String; let title: String; let value: String; let color: Color
    var body: some View { HStack(spacing: 8) { Image(systemName: icon).foregroundStyle(color); VStack(alignment: .leading) { Text(title).font(.caption2).foregroundStyle(SecondTheme.secondaryText); Text(value).font(.headline).foregroundStyle(color) } } }
}

extension Date { var shortTimeWithSeconds: String { formatted(date: .omitted, time: .standard) }; var shortTime: String { formatted(date: .omitted, time: .shortened) } }
