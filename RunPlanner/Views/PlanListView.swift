import SwiftUI

enum ActiveSheet: String, Identifiable {
    case importPlan, getPlan, settings
    var id: String { rawValue }
}

struct PlanListView: View {
    @Environment(PlanStore.self) private var store
    @State private var sheet: ActiveSheet?

    var body: some View {
        NavigationStack {
            Group {
                if let plan = store.data.currentPlan {
                    planList(plan)
                } else {
                    EmptyPlanView(sheet: $sheet)
                }
            }
            .navigationTitle(store.data.currentPlan?.name ?? "Run Planner")
            .navigationDestination(for: UUID.self) { RunDetailView(runID: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { sheet = .getPlan } label: { Label("Get next plan from AI", systemImage: "sparkles") }
                        Button { sheet = .importPlan } label: { Label("Import plan", systemImage: "square.and.arrow.down") }
                        Divider()
                        Button { sheet = .settings } label: { Label("Goal & profile", systemImage: "target") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $sheet) { which in
                Group {
                    switch which {
                    case .importPlan: ImportView()
                    case .getPlan: ExportView()
                    case .settings: SettingsView()
                    }
                }
                .environment(store)
            }
        }
    }

    private func planList(_ plan: TrainingPlan) -> some View {
        ScrollViewReader { proxy in
            List {
                Section { ProgressHeader(plan: plan) }

                if plan.isFinished {
                    Section {
                        Button { sheet = .getPlan } label: {
                            Label("Block complete! Get your next plan", systemImage: "sparkles")
                                .font(.headline)
                        }
                    }
                }

                ForEach(plan.weeks, id: \.self) { week in
                    Section(week == 0 ? "Runs" : "Week \(week)") {
                        ForEach(plan.runsInWeek(week)) { run in
                            NavigationLink(value: run.id) {
                                RunRow(run: run, number: plan.number(of: run), isNext: run.id == plan.nextRun?.id)
                            }
                            .id(run.id)
                        }
                    }
                }
            }
            .onAppear {
                if let id = plan.nextRun?.id { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

struct ProgressHeader: View {
    let plan: TrainingPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(plan.resolvedCount) of \(plan.runs.count) runs")
                    .font(.headline)
                Spacer()
                if plan.totalKm > 0 {
                    Text(Format.km(plan.totalKm)).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: Double(plan.resolvedCount), total: Double(max(plan.runs.count, 1)))
            if let notes = plan.coachNotes?.nilIfBlank {
                Text(notes).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct RunRow: View {
    let run: PlannedRun
    let number: Int
    let isNext: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(badgeColor)
                if run.isDone {
                    Image(systemName: "checkmark").font(.subheadline.bold()).foregroundStyle(.white)
                } else if run.isSkipped {
                    Image(systemName: "forward.fill").font(.caption).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.subheadline.bold())
                        .foregroundStyle(isNext ? .white : .primary)
                }
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(run.title).font(.headline)
                    if isNext {
                        Text("UP NEXT")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor))
                            .foregroundStyle(.white)
                    }
                }
                let target = run.targetSummary()
                if !target.isEmpty {
                    Text(target).font(.subheadline).foregroundStyle(.secondary)
                }
                if let w = run.completion?.workout {
                    Text([w.distanceKm.map(Format.km), w.paceSecPerKm.map(Format.pace)]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.green)
                }
            }

            Spacer()
            Image(systemName: run.symbol).foregroundStyle(run.color)
        }
        .opacity(run.completion != nil ? 0.65 : 1)
    }

    private var badgeColor: Color {
        if run.isDone { return .green }
        if run.isSkipped { return .gray }
        return isNext ? .accentColor : Color(uiColor: .tertiarySystemFill)
    }
}

struct EmptyPlanView: View {
    @Binding var sheet: ActiveSheet?

    var body: some View {
        ContentUnavailableView {
            Label("No plan yet", systemImage: "figure.run")
        } description: {
            Text("Set your goal, ask AI for your first month of runs, then paste the plan in here.")
        } actions: {
            VStack(spacing: 12) {
                Button("1. Set your goal") { sheet = .settings }
                    .buttonStyle(.bordered)
                Button("2. Get a plan from AI") { sheet = .getPlan }
                    .buttonStyle(.bordered)
                Button("3. Import plan") { sheet = .importPlan }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
