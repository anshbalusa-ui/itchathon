import SwiftUI

struct HomeView: View {
  @EnvironmentObject private var store: ProfileStore
  @State private var showDeleteConfirmation = false
  @State private var actionError: String?

  private var hasBody: Bool { store.bodyProfile.isUsable }
  private var hasFavorite: Bool { store.preferredGarment?.isUsable == true }
  private var hasCandidate: Bool { store.currentGarment.isUsable }

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 8) {
          Text("Find your fit")
            .font(.title2.bold())
          Text("Your body sets the limits. Your favorite shirt sets the feel. Check another shirt against both.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      Section("Your measurements") {
        NavigationLink {
          BodyProfileView()
        } label: {
          StepRow(
            title: "My Body",
            detail: hasBody ? "Measurements saved" : "Add your measurements",
            symbol: "figure.stand",
            complete: hasBody
          )
        }

        NavigationLink {
          GarmentEntryView(purpose: .favorite, initial: store.preferredGarment ?? GarmentProfile()) { draft in
            try store.saveGarment(draft, role: .preferred)
          }
        } label: {
          StepRow(
            title: "My Fit",
            detail: store.preferredGarment?.name ?? "Add a favorite shirt",
            symbol: "tshirt",
            complete: hasFavorite
          )
        }

        NavigationLink {
          GarmentEntryView(purpose: .candidate, initial: store.currentGarment) { draft in
            try store.saveGarment(draft, role: .candidate)
            if hasBody && hasFavorite {
              do { try store.evaluateCurrentGarment() }
              catch { actionError = error.localizedDescription }
            }
          }
        } label: {
          StepRow(
            title: "Check a Garment",
            detail: hasCandidate ? store.currentGarment.name : "Measure a shirt to compare",
            symbol: "ruler",
            complete: hasCandidate
          )
        }
      }

      Section("Comparison") {
        if let report = store.lastReport {
          NavigationLink {
            FitResultView(report: report)
          } label: {
            Label("View Results", systemImage: "chart.bar.xaxis")
          }
        } else {
          Label(
            missingPrerequisiteMessage,
            systemImage: "info.circle"
          )
          .foregroundStyle(.secondary)
          if hasBody && hasFavorite && hasCandidate {
            Button("Calculate Results") {
              do { try store.evaluateCurrentGarment() }
              catch { actionError = error.localizedDescription }
            }
          }
        }
      }

      Section("Compare sizes") {
        NavigationLink {
          SizeChartEntryView()
        } label: {
          Label("Enter a garment size chart", systemImage: "square.grid.2x2")
        }
        if store.currentSizeChart != nil && hasBody && hasFavorite && store.sizeComparison == nil {
          Button("Compare Entered Sizes", systemImage: "chart.bar.xaxis") {
            do { try store.evaluateAvailableSizes() }
            catch { actionError = error.localizedDescription }
          }
        }
        if let comparison = store.sizeComparison {
          NavigationLink {
            SizeComparisonView(comparison: comparison)
          } label: {
            Label("View size comparison", systemImage: "chart.bar.xaxis")
          }
        }
      }

      if hasBody || hasFavorite || hasCandidate || store.currentSizeChart != nil {
        Section {
          Button("Delete FitCheck measurements", systemImage: "trash", role: .destructive) {
            showDeleteConfirmation = true
          }
        } footer: {
          Text("Deleting removes your saved body, favorite, candidate, and size chart from this iPhone.")
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("FitCheck")
    .confirmationDialog("Delete all FitCheck measurements?", isPresented: $showDeleteConfirmation) {
      Button("Delete Measurements", role: .destructive) {
        store.deleteMeasurements()
      }
    } message: {
      Text("This removes your body, favorite shirt, candidate shirt, and size chart from this iPhone.")
    }
    .alert("Unable to compare", isPresented: Binding(
      get: { actionError != nil },
      set: { if !$0 { actionError = nil } }
    )) {
      Button("OK", role: .cancel) { actionError = nil }
    } message: {
      Text(actionError ?? "Review your measurements and try again.")
    }
  }

  private var missingPrerequisiteMessage: String {
    if !hasBody && !hasFavorite { return "Add your body and favorite shirt to see results." }
    if !hasBody { return "Add your body measurements to see results." }
    if !hasFavorite { return "Add your favorite shirt to see results." }
    if !hasCandidate { return "Check a garment to see results." }
    return "Review measurements to calculate results."
  }
}

private struct StepRow: View {
  var title: String
  var detail: String
  var symbol: String
  var complete: Bool

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: symbol)
        .font(.title3)
        .foregroundStyle(.tint)
        .frame(width: 34)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.headline)
        Text(detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
      if complete {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .accessibilityLabel("Complete")
      }
    }
    .padding(.vertical, 5)
    .accessibilityElement(children: .combine)
  }
}
