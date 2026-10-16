# Run Planner

A personal iPhone app that lists your next month of runs in order (like Couch to 5K), lets you tick them off against your real Apple Watch workouts, and hands everything to an AI coach to write the next month.

```
 ┌───────────── Run Planner (iPhone) ─────────────┐
 │  1. Do the next run (Apple Watch records it)   │
 │  2. Mark complete → pick the Watch workout,    │
 │     rate effort, add notes                     │
 │  3. Block done → "Get next plan" builds a      │──── copy ───▶  Claude
 │     prompt: goal + planned vs actual + HR/pace │                 │
 │  4. "Import plan" ← paste the reply (JSON)     │◀─── paste ──────┘
 └────────────────────────────────────────────────┘    (repeat monthly)
```

No accounts, servers or API keys. Data lives in one JSON file on the phone, and Apple Health is read-only.

## Build & install (Mac + free Apple ID)

1. On the Mac, install Xcode 15 or later from the App Store, open it once, and sign in: **Xcode › Settings › Accounts › +** with your Apple ID.
2. Copy this folder to the Mac, then:
   ```bash
   brew install xcodegen
   ```
   ```bash
   cd run-planner && xcodegen
   ```
   This creates `RunPlanner.xcodeproj`. Open it.
3. Select the **RunPlanner** target › **Signing & Capabilities**:
   - Team: *Your Name (Personal Team)*
   - Bundle Identifier: change `com.CHANGEME.runplanner` to something unique, e.g. `com.yourname.runplanner`. You can also set it in `project.yml`.
   - HealthKit should already be listed. If not, click **+ Capability › HealthKit**.
   - `RunPlanner.xcodeproj` is generated and git-ignored, so settings changed in Xcode are lost when you re-run `xcodegen`. To keep signing, add `DEVELOPMENT_TEAM: <your team ID>` under the target's `settings.base` in `project.yml`. The team ID is shown in Xcode › Settings › Accounts.
4. Plug in your iPhone and pick it as the run destination. On the iPhone, turn on **Settings › Privacy & Security › Developer Mode** (it restarts).
5. Press ▶ Run. The first time, go to **Settings › General › VPN & Device Management** on the iPhone and trust your developer profile.

**Free account limits:** the install expires after **7 days**. Plug the phone in and press ▶ Run again to refresh it. Your plan and history are kept. When you move to the paid Developer Program, change the Team and the install lasts a year (and TestFlight becomes an option).

**No XcodeGen?** Create a new iOS App project in Xcode (SwiftUI, name it RunPlanner, iOS 17), delete its generated `ContentView.swift` and `RunPlannerApp.swift`, and drag this `RunPlanner/` folder in. Then add the **HealthKit** capability and add *Privacy – Health Share Usage Description* to the Info tab.

## Using it

1. **Goal & profile** (⋯ menu): your goal, notes about you (current fitness, injuries, time limits), and runs per week.
2. **Get next plan**: copy the prompt, tap **Open Claude**, paste it, and send.
   - The first prompt includes your last 6 weeks of Apple Watch runs, so the AI knows your current fitness.
   - Later prompts include each planned run next to what you actually did: distance, time, pace, average and max heart rate, climb, effort 1–10, your notes, skipped runs, plus any unplanned runs.
3. **Import plan**: copy Claude's whole reply, tap **Paste AI reply**, check the preview, then tap **Import**. The finished block moves to history, so future prompts show long-term progress.
4. Do your runs. Tap a run, then **Mark complete**: the app lists your Apple Watch runs from the last 14 days and preselects the most likely one.

**Tip:** make a Claude **Project** called "Running coach", put your goal and background in its instructions, and run every monthly chat inside it. Claude then also remembers past conversations.

There's a **Load sample plan** button on the Import screen for trying the app out straight away.

## Plan format

The prompt includes this schema. You can also write or edit plans by hand:

```json
{
  "name": "Block 2: 10K build",
  "coachNotes": "Why this block looks the way it does.",
  "runs": [
    { "week": 1, "title": "Easy run", "type": "easy", "targetDistanceKm": 5,
      "targetPace": "6:20-6:40 /km", "targetEffort": "Zone 2", "description": "…" },
    { "week": 1, "title": "400 m repeats", "type": "intervals",
      "segments": [{ "label": "Fast", "distanceKm": 0.4, "repeats": 6, "intensity": "5K pace" }] }
  ]
}
```

`type`: easy, long, tempo, intervals, hills, recovery, strides, race, walk-run. Only `title` is required.

## Code map

| File | What it does |
|---|---|
| `Models.swift` | Plan, run, completion and workout types (Codable) |
| `PlanStore.swift` | Loads and saves `runplanner.json`; reads the plan out of the AI reply |
| `HealthService.swift` | HealthKit: reads running workouts plus HR, distance, energy and elevation |
| `PromptBuilder.swift` | Writes the coaching prompt |
| `Views/` | List, run detail, complete sheet, import, export, settings |

## Ideas for later

- A "Generate in app" button that calls the Claude API directly with your own key, removing the copy/paste.
- Per-km splits and heart-rate zones from HealthKit samples, for richer coaching.
- A Watch complication or widget showing "Up next".
