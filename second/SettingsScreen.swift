import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var store: ReflectionSessionStore

    @State private var exportURL: URL?
    @State private var pendingDeleteAllConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                SecondTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        ScreenHeader(title: "Settings", subtitle: "Privacy, data, and future integrations")

                        AppCard(title: "Data Mode") {
                            VStack(spacing: 10) {
                                MetricRow(label: "Current build", value: "iPhone-only")
                                MetricRow(label: "Watch integration", value: "Planned")
                                MetricRow(label: "HealthKit", value: "Planned")
                                MetricRow(label: "Cloud sync", value: "Off")
                                MetricRow(label: "Storage", value: "Local-first")
                            }
                        }
                        .padding(.horizontal)

                        AppCard(title: "Your Data") {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Export includes every reflection's transcript, observations, and consent/provenance metadata as JSON. Raw audio recordings are not included in the export file.")
                                    .font(.caption)
                                    .foregroundStyle(SecondTheme.secondaryText)

                                if let exportURL {
                                    ShareLink(item: exportURL) {
                                        Label("Share Export File", systemImage: "square.and.arrow.up")
                                    }
                                } else {
                                    Button {
                                        exportURL = store.exportAllReflectionsJSON()
                                    } label: {
                                        Label("Prepare Export", systemImage: "doc.text")
                                    }
                                    .disabled(store.completedSessions.isEmpty)
                                }

                                Divider()

                                Button(role: .destructive) {
                                    pendingDeleteAllConfirmation = true
                                } label: {
                                    Label("Delete All Reflections & Audio", systemImage: "trash")
                                }
                                .disabled(store.completedSessions.isEmpty)
                            }
                        }
                        .padding(.horizontal)

                        AppCard(title: "Architecture Notes") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Live biometric data should come from Apple Watch using HKLiveWorkoutBuilder.")
                                Text("HealthKit queries should be used for durable backfill and reconciliation, not primary live UI.")
                                Text("WatchConnectivity should send source timestamps, not arrival timestamps.")
                                Text("Transcript and biometric events should align by session-relative time windows.")
                            }
                            .font(.caption)
                            .foregroundStyle(SecondTheme.secondaryText)
                        }
                        .padding(.horizontal)

                        AppCard(title: "Security") {
                            VStack(spacing: 10) {
                                MetricRow(label: "HIPAA compliant", value: "No")
                                MetricRow(label: "Medical diagnosis", value: "No")
                                MetricRow(label: "Camera capture", value: "No")
                                MetricRow(label: "Data export", value: "Available")
                                MetricRow(label: "Delete all data", value: "Available")
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 24)
                }
            }
            .confirmationDialog(
                "Delete All Data",
                isPresented: $pendingDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) {
                    store.deleteAllData()
                    exportURL = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes every saved reflection and its audio recording. This can't be undone.")
            }
        }
    }
}
