import SwiftUI

struct ReflectionTimelineScreen: View {
    @EnvironmentObject private var store: ReflectionSessionStore

    var body: some View {
        NavigationStack {
            ZStack {
                SecondTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        ScreenHeader(title: "Timeline", subtitle: "Reflection history")

                        PickerRow()

                        VStack(spacing: 12) {
                            if store.completedSessions.isEmpty {
                                AppCard(title: "No Reflections Yet") {
                                    Text("Record your first reflection from the Observatory or Capture tab. Finished reflections are saved to your device and will appear here.")
                                        .font(.subheadline)
                                        .foregroundStyle(SecondTheme.secondaryText)
                                }
                            }

                            ForEach(store.completedSessions) { session in
                                NavigationLink {
                                    ReflectionDetailScreen(session: session)
                                } label: {
                                    AppCard(title: session.startedAt.formatted(date: .abbreviated, time: .omitted), startsExpanded: true) {
                                        VStack(alignment: .leading, spacing: 12) {
                                            HStack {
                                                VStack(alignment: .leading) {
                                                    Text(session.title)
                                                        .font(.headline)

                                                    Text("\(session.timeRangeText) • \(session.durationText)")
                                                        .font(.caption)
                                                        .foregroundStyle(SecondTheme.secondaryText)
                                                }

                                                Spacer()

                                                Image(systemName: "chevron.right")
                                                    .foregroundStyle(SecondTheme.secondaryText)
                                            }

                                            Text(session.observations.first?.detail ?? "No observation yet.")
                                                .font(.caption)
                                                .foregroundStyle(SecondTheme.secondaryText)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }
}

struct PickerRow: View {
    var body: some View {
        HStack {
            Text("All")
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal)
    }
}

