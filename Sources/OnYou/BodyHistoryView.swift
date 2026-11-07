import SwiftUI

struct BodyHistoryView: View {
  var store: OnYouStore
  var onRestore: () -> Void

  var body: some View {
    List {
      if store.history.isEmpty {
        ContentUnavailableView("No measurements yet", systemImage: "clock", description: Text("Saved measurements will appear here."))
          .listRowBackground(Color.clear)
      } else {
        Section {
          ForEach(store.history) { snapshot in
            NavigationLink {
              BodySnapshotView(snapshot: snapshot, store: store, onRestore: onRestore)
            } label: {
              VStack(alignment: .leading, spacing: 5) {
                Text(snapshot.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                  .font(.headline)
                Text("Chest \(snapshot.measurements.chest.formatted()) · Waist \(snapshot.measurements.waist.formatted()) · Hips \(snapshot.measurements.hips.formatted()) cm")
                  .font(.subheadline).foregroundStyle(.secondary)
              }
              .padding(.vertical, 4)
            }
          }
          .onDelete(perform: store.delete)
        } footer: {
          Text("Deleting a record keeps your current body unchanged.")
        }
      }
    }
    .navigationTitle("History")
    .toolbar { EditButton().disabled(store.history.isEmpty) }
  }
}

private struct BodySnapshotView: View {
  var snapshot: BodySnapshot
  var store: OnYouStore
  var onRestore: () -> Void

  var body: some View {
    List {
      Section {
        BodySceneView(measurements: snapshot.measurements)
          .frame(height: 300)
          .listRowInsets(EdgeInsets())
      }
      Section(snapshot.date.formatted(date: .abbreviated, time: .shortened)) {
        ForEach(BodyMeasurementField.allCases) { field in
          let value = "\(snapshot.measurements[field].formatted(.number.precision(.fractionLength(0...1)))) cm"
          LabeledContent(field.title, value: value)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(field.title)
            .accessibilityValue(value)
            .accessibilityIdentifier("snapshot.\(field.rawValue)")
        }
      }
      if let current = store.current, current != snapshot.measurements {
        Section("Change from current") {
          ForEach(BodyMeasurementField.allCases) { field in
            let change = snapshot.measurements[field] - current[field]
            LabeledContent(field.title, value: "\(change.formatted(.number.precision(.fractionLength(0...1)).sign(strategy: .always()))) cm")
          }
        }
        Section {
          Button("Use these measurements") {
            if store.save(snapshot.measurements) { onRestore() }
          }
        }
      }
    }
    .navigationTitle("Saved body")
    .navigationBarTitleDisplayMode(.inline)
  }
}
