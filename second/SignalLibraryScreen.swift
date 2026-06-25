import SwiftUI

struct SignalLibraryScreen: View {
    @StateObject private var registry = SignalLibraryRegistry()

    var body: some View {
        ZStack {
            SecondTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    ScreenHeader(
                        title: "Signal Libraries",
                        subtitle: "Versioned phrase and pattern rules"
                    )

                    AppCard(title: "Library Principle") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Detection logic should be modular, inspectable, versioned, and eventually importable—not permanently hard-coded into Swift engines.")
                                .font(.subheadline)

                            Text("This screen shows the first local library foundation. Future versions can add database storage, import/export, authoring tools, validation, and moderation.")
                                .font(.caption)
                                .foregroundStyle(SecondTheme.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)

                    ForEach(registry.libraries) { library in
                        AppCard(title: library.name, startsExpanded: true) {
                            VStack(alignment: .leading, spacing: 12) {
                                MetricRow(label: "Library ID", value: library.id)
                                MetricRow(label: "Version", value: library.version)
                                MetricRow(label: "Author", value: "\(library.author) / \(library.authorType.rawValue)")
                                MetricRow(label: "Domain", value: library.domain.rawValue)
                                MetricRow(label: "Enabled", value: library.isEnabledByDefault ? "Yes" : "No")

                                Text(library.description)
                                    .font(.caption)
                                    .foregroundStyle(SecondTheme.secondaryText)

                                Divider()

                                Text("Rules")
                                    .font(.subheadline)
                                    .bold()

                                ForEach(library.rules) { rule in
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(rule.name)
                                            .font(.caption)
                                            .bold()

                                        Text("\(rule.id) • \(rule.matchType.rawValue)")
                                            .font(.caption2)
                                            .foregroundStyle(SecondTheme.secondaryText)

                                        Text("Event: \(rule.title)")
                                            .font(.caption2)
                                            .foregroundStyle(SecondTheme.secondaryText)

                                        Text("Phrases: \(rule.phrases.prefix(5).joined(separator: ", "))")
                                            .font(.caption2)
                                            .foregroundStyle(SecondTheme.secondaryText)
                                            .lineLimit(2)

                                        Text("Confidence: \(rule.confidence.rawValue.capitalized)")
                                            .font(.caption2)
                                            .foregroundStyle(SecondTheme.secondaryText)
                                    }

                                    Divider()
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    AppCard(title: "v113 Scope") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Implemented")
                                .font(.subheadline)
                                .bold()

                            Text("• Versioned local signal library model")
                            Text("• Library-backed cognitive detector")
                            Text("• Provenance tags on generated observation events")
                            Text("• Inspectable library/rule screen")

                            Text("Not yet implemented")
                                .font(.subheadline)
                                .bold()
                                .padding(.top, 6)

                            Text("• Database persistence")
                            Text("• Import/export UI")
                            Text("• Third-party library validation")
                            Text("• Migration of every hard-coded detector")
                            Text("• Clinical or biometric rules")
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Libraries")
        .navigationBarTitleDisplayMode(.inline)
    }
}
