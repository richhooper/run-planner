import SwiftUI
import UIKit

/// Builds the coaching prompt to paste into Claude (or any AI).
struct ExportView: View {
    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var healthRuns: [WorkoutSummary] = []
    @State private var copied = false

    private var prompt: String {
        PromptBuilder.prompt(for: store.data, recentRuns: healthRuns)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if store.data.goal.nilIfBlank == nil {
                        Label("Add your goal in Goal & profile first. The AI plans around it.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Copy this prompt and paste it into Claude.")
                        Text("2. When it replies, copy the whole reply.")
                        Text("3. Come back and tap Import plan.")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    Text(prompt)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle("Get next plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { ShareLink(item: prompt) }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = prompt
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy prompt", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Link(destination: URL(string: "https://claude.ai/new")!) {
                        Label("Open Claude", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
            .task {
                // Include unplanned runs too, so the AI sees everything you did.
                healthRuns = (try? await HealthService.shared.recentRuns(days: 42)) ?? []
            }
        }
    }
}
