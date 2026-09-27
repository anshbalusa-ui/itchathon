import Foundation
import SwiftUI

struct MeasurementField: View {
  var title: String
  @Binding var meters: Double
  var unit: LengthUnit
  var required = true
  @Binding var isValid: Bool
  var onEdit: (() -> Void)? = nil

  @State private var text = ""
  @State private var hasLoaded = false
  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(title)
        Spacer(minLength: 8)
        TextField("0", text: $text)
          .keyboardType(.decimalPad)
          .focused($isFocused)
          .multilineTextAlignment(.trailing)
          .frame(minWidth: 70, maxWidth: 112)
          .accessibilityLabel("\(title) in \(unit.rawValue)")
          .onChange(of: text) { _, value in update(value) }
        Text(unit.symbol)
          .foregroundStyle(.secondary)
          .frame(minWidth: 24, alignment: .leading)
      }
      if !isValid {
        Text(required ? "Enter a positive measurement." : "Enter a positive measurement or leave blank.")
          .font(.footnote)
          .foregroundStyle(.red)
          .accessibilityAddTraits(.updatesFrequently)
      }
    }
    .onAppear {
      guard !hasLoaded else { return }
      hasLoaded = true
      text = displayText
    }
    .onChange(of: unit) { _, _ in text = displayText }
    .onChange(of: meters) { _, _ in
      if !isFocused { text = displayText }
    }
  }

  private var displayText: String {
    guard meters.isFinite, meters > 0 else { return "" }
    return unit.display(meters).formatted(.number.precision(.fractionLength(0...1)))
  }

  private func update(_ value: String) {
    guard hasLoaded else { return }
    if !isFocused && value == displayText {
      isValid = !required || validMeters
      return
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      isValid = !required
      if !required {
        meters = 0
        onEdit?()
      }
      return
    }
    guard let number = Self.positiveNumber(trimmed),
          unit.meters(number).isFinite else {
      isValid = false
      return
    }
    isValid = true
    meters = unit.meters(number)
    onEdit?()
  }

  private var validMeters: Bool { meters.isFinite && meters > 0 }

  private static func positiveNumber(_ value: String) -> Double? {
    let formatter = NumberFormatter()
    formatter.locale = .current
    formatter.numberStyle = .decimal
    formatter.isLenient = false
    formatter.generatesDecimalNumbers = true
    var object: AnyObject?
    var range = NSRange(location: 0, length: (value as NSString).length)
    do { try formatter.getObjectValue(&object, for: value, range: &range) }
    catch { return nil }
    guard range.location == 0,
          range.length == (value as NSString).length,
          let number = object as? NSNumber,
          number.doubleValue.isFinite,
          number.doubleValue > 0 else { return nil }
    return number.doubleValue
  }
}
