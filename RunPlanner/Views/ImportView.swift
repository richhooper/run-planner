import SwiftUI
import UIKit

struct ImportView: View {
    @Environment(PlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var confirmReplace = false

    private var result: Result<TrainingPlan, Error>? {
        text.trimmed.isEmpty ? nil : Result { try PlanImporter.parse(text) }
    }

    private var parsedPlan: TrainingPlan? {
        if case .success(let plan)? = result { return plan }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        text = UIPasteboard.general.string ?? ""
                    } label: {
                        Label("Paste AI reply", systemImage: "doc.on.clipboard")
                    }
                    TextEditor(text: $text)
                        .font(.system(.caption, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .frame(minHeight: 160)
                } footer: {
                    Text("Paste the AI's whole reply. The app finds the JSON plan in it.")
                }

                if let result {
                    switch result {
                    case .success(let plan):
                        Section("Preview") {
                            LabeledContent("Name", value: plan.name)
                            LabeledContent("Runs", value: "\(plan.runs.count)")
                            if plan.weeks.count > 1 { LabeledContent("Weeks", value: "\(plan.weeks.count)") }
                            if let notes = plan.coachNotes { Text(notes).font(.footnote).foregroundStyle(.secondary) }
                            ForEach(plan.runs.prefix(4)) { run in
                                Label(run.title, systemImage: run.symbol).foregroundStyle(run.color)
                            }
                            if plan.runs.count > 4 { Text("…and \(plan.runs.count - 4) more").foregroundStyle(.secondary) }
                        }
                    case .failure(let error):
                        Section("Problem") {
                            Text(error.localizedDescription).foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Button("Load sample plan") { text = Self.samplePlan }
                } footer: {
                    Text("A generic 4-week block for trying the app out.")
                }
            }
            .navigationTitle("Import plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        if store.data.currentPlan?.isFinished == false { confirmReplace = true } else { importPlan() }
                    }
                    .bold()
                    .disabled(parsedPlan == nil)
                }
            }
            .confirmationDialog("Your current plan still has runs left.", isPresented: $confirmReplace, titleVisibility: .visible) {
                Button("Replace current plan", role: .destructive, action: importPlan)
            } message: {
                Text("Runs you've completed are kept in your history.")
            }
        }
    }

    private func importPlan() {
        guard let plan = parsedPlan else { return }
        store.install(plan)
        dismiss()
    }

    private static var samplePlan: String {
        guard let url = Bundle.main.url(forResource: "SamplePlan", withExtension: "json"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }
}
