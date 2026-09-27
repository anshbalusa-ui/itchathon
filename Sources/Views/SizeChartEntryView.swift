import SwiftUI

struct SizeChartEntryView: View {
  @EnvironmentObject private var store: ProfileStore
  @Environment(\.dismiss) private var dismiss
  @AppStorage("fitcheck.preferredUnit") private var unitRaw = LengthUnit.centimeters.rawValue

  @State private var productName = ""
  @State private var brand = ""
  @State private var sourceNote = ""
  @State private var measurementBasisRaw = ""
  @State private var chestBasisRaw = ChestInputBasis.flatWidth.rawValue
  @State private var sourceRaw = MeasurementSource.retailer.rawValue
  @State private var rows: [SizeChartRowDraft] = [SizeChartRowDraft()]
  @State private var didLoad = false
  @State private var errorMessage: String?

  private var unit: LengthUnit { LengthUnit(rawValue: unitRaw) ?? .centimeters }
  private var chestBasis: ChestInputBasis { ChestInputBasis(rawValue: chestBasisRaw) ?? .flatWidth }

  var body: some View {
    Form {
      Section {
        TextField("Product name", text: $productName)
          .textInputAutocapitalization(.words)
        TextField("Brand (optional)", text: $brand)
          .textInputAutocapitalization(.words)
        TextField("Source or product page", text: $sourceNote, axis: .vertical)
          .lineLimit(1...3)
          .textInputAutocapitalization(.sentences)
      } header: {
        Text("About this chart")
      } footer: {
        Text("Name where these measurements came from. FitCheck does not fetch or verify retailer charts.")
      }

      Section {
        Picker("What do these values measure?", selection: $measurementBasisRaw) {
          Text("Choose chart type").tag("")
          Text("Finished garment").tag(ChartMeasurementBasis.finishedGarment.rawValue)
          Text("Recommended body size").tag(ChartMeasurementBasis.bodyRecommendation.rawValue)
        }
        if measurementBasisRaw == ChartMeasurementBasis.bodyRecommendation.rawValue {
          Label("Body-size charts cannot be used to calculate garment fit. Get the shirt's finished measurements or measure it directly.", systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      } header: {
        Text("Chart meaning")
      } footer: {
        Text("A body-size range is not a shirt's measured chest width. FitCheck will not invent the missing ease.")
      }

      if measurementBasisRaw == ChartMeasurementBasis.finishedGarment.rawValue {
        Section("How values are listed") {
          Picker("Chest measurement", selection: $chestBasisRaw) {
            Text("Flat width (pit to pit)").tag(ChestInputBasis.flatWidth.rawValue)
            Text("Garment circumference").tag(ChestInputBasis.circumference.rawValue)
          }
          .onChange(of: chestBasisRaw) { oldValue, newValue in
            guard oldValue != newValue else { return }
            let oldBasis = ChestInputBasis(rawValue: oldValue) ?? .flatWidth
            let newBasis = ChestInputBasis(rawValue: newValue) ?? .flatWidth
            for index in rows.indices where rows[index].chest > 0 {
              let flat = oldBasis.flatMeters(from: rows[index].chest)
              rows[index].chest = newBasis == .flatWidth ? flat : flat * 2
            }
          }
          Picker("Units", selection: $unitRaw) {
            ForEach(LengthUnit.allCases) { option in
              Text(option == .centimeters ? "Centimeters" : "Inches")
                .tag(option.rawValue)
            }
          }
          .pickerStyle(.segmented)
          Picker("Measurement source", selection: $sourceRaw) {
            Text("Retailer listing").tag(MeasurementSource.retailer.rawValue)
            Text("Measured by me").tag(MeasurementSource.manual.rawValue)
            Text("External source").tag(MeasurementSource.external.rawValue)
          }
        }

        ForEach($rows) { $row in
          Section {
            TextField("Size label, for example M", text: $row.label)
              .textInputAutocapitalization(.characters)
              .accessibilityLabel("Size label")
            MeasurementField(title: chestBasis == .flatWidth ? "Chest width" : "Chest circumference", meters: $row.chest, unit: unit, isValid: $row.chestValid)
            MeasurementField(title: "Shoulders", meters: $row.shoulders, unit: unit, isValid: $row.shouldersValid)
            MeasurementField(title: "Length", meters: $row.length, unit: unit, isValid: $row.lengthValid)
            MeasurementField(title: "Waist width", meters: $row.waist, unit: unit, required: false, isValid: $row.waistValid)
            if row.waist > 0 {
              Toggle("Waist at navel level", isOn: $row.waistAtNavel)
            }
            if rows.count > 1 {
              Button("Remove Size", systemImage: "minus.circle", role: .destructive) {
                rows.removeAll { $0.id == row.id }
              }
            }
          } header: {
            Text(row.label.isEmpty ? "Size" : "Size \(row.label)")
          }
        }

        Section {
          Button("Add Size", systemImage: "plus") {
            rows.append(SizeChartRowDraft())
          }
        }
      }
    }
    .navigationTitle("Size Chart")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") { save() }
          .fontWeight(.semibold)
      }
    }
    .alert("Check size chart", isPresented: Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) { errorMessage = nil }
    } message: {
      Text(errorMessage ?? "Review the chart and try again.")
    }
    .onAppear { loadExistingChart() }
  }

  private func loadExistingChart() {
    guard !didLoad else { return }
    didLoad = true
    guard let chart = store.currentSizeChart else { return }
    productName = chart.garmentName
    brand = chart.brand ?? ""
    sourceNote = chart.sourceNote ?? ""
    measurementBasisRaw = chart.measurementBasis?.rawValue ?? ""
    rows = chart.sizes.map { variant in
      SizeChartRowDraft(
        id: variant.id,
        label: variant.label,
        chest: variant.chestFlat,
        shoulders: variant.shoulderWidth,
        length: variant.length,
        waist: variant.waistFlat,
        waistAtNavel: variant.waistAtNavel == true
      )
    }
    if rows.isEmpty { rows = [SizeChartRowDraft()] }
  }

  private func save() {
    guard measurementBasisRaw == ChartMeasurementBasis.finishedGarment.rawValue else {
      errorMessage = "Choose finished garment measurements. A body-size recommendation chart cannot be used for this comparison."
      return
    }
    let name = productName.trimmingCharacters(in: .whitespacesAndNewlines)
    let note = sourceNote.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !note.isEmpty else {
      errorMessage = "Add a product name and a source for these measurements."
      return
    }
    let labels = rows.map { $0.label.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard labels.allSatisfy({ !$0.isEmpty }),
          Set(labels.map { $0.localizedLowercase }).count == labels.count else {
      errorMessage = "Every size needs a unique label."
      return
    }
    guard rows.allSatisfy({ $0.isValid(chestBasis: chestBasis) }) else {
      errorMessage = "Each size needs positive chest, shoulder, and length values. Waist may be blank."
      return
    }

    let source = MeasurementSource(rawValue: sourceRaw) ?? .retailer
    let variants = zip(rows, labels).map { row, label in
      let origin = MeasurementOrigin(source: source)
      var origins: [String: MeasurementOrigin] = [
        MeasurementKey.garmentChestFlat.rawValue: origin,
        MeasurementKey.garmentShoulderWidth.rawValue: origin,
        MeasurementKey.garmentLength.rawValue: origin
      ]
      if row.waist > 0 { origins[MeasurementKey.garmentWaistFlat.rawValue] = origin }
      return GarmentSizeVariant(
        id: row.id,
        label: label,
        chestFlat: chestBasis.flatMeters(from: row.chest),
        waistFlat: row.waist,
        shoulderWidth: row.shoulders,
        length: row.length,
        origins: origins,
        waistAtNavel: row.waist > 0 ? row.waistAtNavel : nil
      )
    }
    let chart = GarmentSizeChart(
      garmentName: name,
      brand: brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : brand.trimmingCharacters(in: .whitespacesAndNewlines),
      category: .tshirt,
      sizes: variants,
      measurementBasis: .finishedGarment,
      sourceNote: note
    )
    do {
      try store.saveSizeChart(chart)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct SizeChartRowDraft: Identifiable {
  var id = UUID()
  var label = ""
  var chest = 0.0
  var shoulders = 0.0
  var length = 0.0
  var waist = 0.0
  var waistAtNavel = false
  var chestValid = true
  var shouldersValid = true
  var lengthValid = true
  var waistValid = true

  func isValid(chestBasis: ChestInputBasis) -> Bool {
    chestValid && shouldersValid && lengthValid && waistValid
      && validLength(chestBasis.flatMeters(from: chest))
      && validLength(shoulders)
      && validLength(length)
      && waist.isFinite && waist >= 0
  }
}
