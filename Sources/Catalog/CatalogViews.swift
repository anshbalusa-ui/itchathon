#if DEBUG
import SwiftUI

@MainActor
struct CatalogRootView: View {
    @StateObject private var model: CatalogRootViewModel

    init(repository: any CatalogRepository = OfflineCatalogRepository()) {
        _model = StateObject(wrappedValue: CatalogRootViewModel(repository: repository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if case .loaded(let products) = model.state, !products.isEmpty {
                    if products.allSatisfy({ $0.provenance.source == .synthetic }) {
                        sampleCollectionNotice
                    } else {
                        Text("Availability reflects catalog information and isn’t verified inventory.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("catalog.availability-disclosure")
                    }
                }
                content
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Catalog")
        .navigationBarTitleDisplayMode(.large)
        .task { await model.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            CatalogNotice(
                symbol: "hourglass",
                title: "Loading collection",
                message: "Checking the items available in this catalog."
            )
            .accessibilityIdentifier("catalog.list.loading")
        case .loaded(let products):
            LazyVStack(spacing: 14) {
                ForEach(products, id: \.id) { product in
                    NavigationLink {
                        CatalogDetailView(repository: model.repository, productID: product.id)
                    } label: {
                        CatalogProductCard(product: product)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("catalog.product.\(product.id.retailerID).\(product.id.productID)")
                }
            }
        case .empty:
            CatalogNotice(
                symbol: "tshirt",
                title: "No items to show",
                message: "This collection doesn’t contain any products yet."
            )
            .accessibilityIdentifier("catalog.list.empty")
        case .unavailable:
            CatalogNotice(
                symbol: "wifi.slash",
                title: "Collection unavailable",
                message: "The catalog couldn’t be reached. Try again when it’s available.",
                actionTitle: "Try again",
                action: { Task { await model.reload() } }
            )
            .accessibilityIdentifier("catalog.list.unavailable")
        case .failed:
            CatalogNotice(
                symbol: "exclamationmark.arrow.triangle.2.circlepath",
                title: "Couldn’t load the collection",
                message: "The catalog didn’t return a usable collection.",
                actionTitle: "Try again",
                action: { Task { await model.reload() } }
            )
            .accessibilityIdentifier("catalog.list.failed")
        }
    }

    private var sampleCollectionNotice: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sample collection")
                    .font(.headline)
                Text("Offline examples only. Sample prices aren’t real; availability isn’t live inventory.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "info.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("catalog.sample-disclosure")
    }
}

@MainActor
struct CatalogDetailView: View {
    @StateObject private var model: CatalogDetailViewModel
    @ScaledMetric(relativeTo: .caption) private var colorOptionWidth = 82.0
    @ScaledMetric(relativeTo: .body) private var sizeOptionWidth = 78.0

    init(repository: any CatalogRepository, productID: CatalogProductID) {
        _model = StateObject(wrappedValue: CatalogDetailViewModel(repository: repository, productID: productID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(model.product?.title ?? "Product details")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadIfNeeded() }
        .navigationDestination(item: Binding(
            get: { model.presentedPreview },
            set: { if $0 == nil { model.dismissPreview() } }
        )) { preview in
            RendererLabView(presentation: preview.rendererPresentation)
                .id(preview.id)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.productState {
        case .loading:
            CatalogNotice(
                symbol: "hourglass",
                title: "Loading product",
                message: "Checking this item’s details."
            )
            .accessibilityIdentifier("catalog.detail.loading")
        case .notFound:
            CatalogNotice(
                symbol: "magnifyingglass",
                title: "Product not found",
                message: "This item is no longer present in the catalog."
            )
            .accessibilityIdentifier("catalog.detail.not-found")
        case .unavailable:
            CatalogNotice(
                symbol: "wifi.slash",
                title: "Product unavailable",
                message: "The catalog couldn’t provide this item right now.",
                actionTitle: "Try again",
                action: { Task { await model.reload() } }
            )
            .accessibilityIdentifier("catalog.detail.unavailable")
        case .failed:
            CatalogNotice(
                symbol: "exclamationmark.arrow.triangle.2.circlepath",
                title: "Couldn’t load this product",
                message: "The catalog didn’t return usable product details.",
                actionTitle: "Try again",
                action: { Task { await model.reload() } }
            )
            .accessibilityIdentifier("catalog.detail.failed")
        case .loaded(let product):
            productDetails(product)
        }
    }

    private func productDetails(_ product: CatalogProduct) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if product.provenance.source == .synthetic {
                Label {
                    Text("Synthetic sample. Price and availability are illustrative only, not a real product or live inventory.")
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "info.circle.fill")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("catalog.detail.sample-disclosure")
            }

            productPhoto
            VStack(alignment: .leading, spacing: 8) {
                Text(product.title)
                    .font(.largeTitle.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(product.description ?? "Description not provided.")
                    .font(.body)
                    .foregroundStyle(product.description == nil ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                productPrice(product)
            }

            if product.colors.isEmpty {
                CatalogSection(title: "Color", detail: "Color options not provided.")
            } else {
                colorPicker(product)
            }

            if product.sizes.isEmpty {
                CatalogSection(title: "Size", detail: "Size options not provided.")
            } else {
                sizePicker(product)
            }

            selectedVariantDetails
            illustrativePreview
            measurements
            avatarAvailabilityNotice
        }
    }

    private var productPhoto: some View {
        VStack(spacing: 10) {
            Image(systemName: "tshirt")
                .font(.system(size: 58, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Photo unavailable")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 210)
        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Product photo unavailable")
        .accessibilityIdentifier("catalog.detail.photo-unavailable")
    }

    private func productPrice(_ product: CatalogProduct) -> some View {
        Group {
            if let price = product.price {
                if let formatted = price.formatted() {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("From")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(formatted)
                            .font(.title3.weight(.semibold))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(product.provenance.source == .synthetic ? "Sample starting price" : "Starting price"), \(formatted)")
                } else {
                    Text("Starting price unavailable.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Starting price not provided.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("catalog.detail.product-price")
    }

    private func colorPicker(_ product: CatalogProduct) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Color")
                .font(.headline)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(product.colors, id: \.id) { color in
                        let isSelected = model.selectedColorID == color.id
                        Button {
                            model.selectColor(color.id)
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(swatchColor(color.hex))
                                        .frame(width: 42, height: 42)
                                    if color.hex == nil {
                                        Image(systemName: "questionmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(.secondary)
                                    }
                                    Circle()
                                        .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: isSelected ? 3 : 1)
                                        .frame(width: 48, height: 48)
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.primary)
                                            .padding(4)
                                            .background(.regularMaterial, in: Circle())
                                            .offset(x: 17, y: -17)
                                    }
                                }
                                Text(color.name)
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(width: colorOptionWidth)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(color.name)
                        .accessibilityValue(isSelected ? "Selected" : "Not selected")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier("catalog.color.\(color.id)")
                    }
                }
                .padding(.vertical, 3)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("catalog.colors")
        }
    }

    private func sizePicker(_ product: CatalogProduct) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Size")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeOptionWidth), alignment: .leading)], alignment: .leading, spacing: 10) {
                ForEach(product.sizes, id: \.id) { size in
                    let availability = model.availability(for: size.id)
                    let isEnabled = model.canSelectSize(size.id)
                    let isSelected = model.selectedSizeID == size.id
                    let isPending = model.pendingSizeID == size.id
                    Button {
                        Task { await model.selectSize(size.id) }
                    } label: {
                        HStack(spacing: 7) {
                            if isPending {
                                ProgressView()
                                    .controlSize(.small)
                                    .accessibilityHidden(true)
                            } else if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .accessibilityHidden(true)
                            }
                            Text(size.label)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .padding(.horizontal, 10)
                        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled)
                    .accessibilityLabel("\(size.label), \(sizeAvailabilityLabel(availability))")
                    .accessibilityValue(isSelected ? "Selected" : (isPending ? "Checking" : "Not selected"))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("catalog.size.\(size.id)")
                }
            }
            Text("Availability is based on the catalog source and isn’t verified inventory.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var selectedVariantDetails: some View {
        switch model.variantState {
        case .idle:
            EmptyView()
        case .loading:
            Label("Checking this size’s availability…", systemImage: "hourglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("catalog.variant.loading")
        case .available(let variant):
            VStack(alignment: .leading, spacing: 5) {
                if let price = variant.price {
                    if let formatted = price.formatted() {
                        Text("Selected size price · \(formatted)")
                            .font(.headline)
                    } else {
                        Text("Price for this size is unavailable.")
                            .font(.subheadline)
                    }
                } else {
                    Text("Price for this size not provided.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("Listed as available by the catalog source; inventory isn’t verified.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("catalog.variant.available")
        case .unavailable(let variant):
            Label(variantAvailabilityLabel(variant.availability), systemImage: "minus.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("catalog.variant.unavailable")
        case .notFound:
            Label("This size option wasn’t found in the latest catalog result.", systemImage: "questionmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("catalog.variant.not-found")
        case .sourceUnavailable:
            retryableVariantMessage(
                title: "Size availability couldn’t be checked.",
                identifier: "catalog.variant.source-unavailable"
            )
        case .failed:
            retryableVariantMessage(
                title: "Couldn’t check this size’s availability.",
                identifier: "catalog.variant.failed"
            )
        }
    }

    private func retryableVariantMessage(title: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Try again") {
                Task { await model.retryVariantLookup() }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("catalog.variant.retry")
        }
        .accessibilityIdentifier(identifier)
    }

    private var illustrativePreview: some View {
        let eligibility = model.previewEligibility
        let isEligible: Bool
        if case .eligible = eligibility {
            isEligible = true
        } else {
            isEligible = false
        }
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                model.openPreview()
            } label: {
                Label("View illustrative 3D preview", systemImage: "cube")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isEligible)
            .accessibilityIdentifier("catalog.preview.open")

            if case .unavailable(let reason) = eligibility {
                Text(reason.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("catalog.preview.unavailable")
            }
            Text("Generic mannequin and illustrative geometric garment only. Not based on a body scan; no physical garment size, drape, or fit is represented.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var measurements: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Garment measurements")
                .font(.headline)
            if let measurements = model.selectedVariant?.finishedMeasurements,
               measurements.basis == .finishedGarment {
                let entries = measurementEntries(measurements)
                if entries.isEmpty {
                    Text("Garment measurements not provided.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        HStack {
                            Text(entry.name)
                            Spacer(minLength: 12)
                            Text(entry.value)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                    Text("Measurements describe the finished garment.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Garment measurements not provided.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("catalog.garment-measurements")
    }

    private var avatarAvailabilityNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Personalized avatar features unavailable", systemImage: "person.crop.square")
                .font(.headline)
            Text("The generic illustration doesn’t load or create your avatar. Personalized avatar viewing, try-on, and fit features aren’t available here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("catalog.avatar-unavailable")
    }
}

private struct CatalogProductCard: View {
    let product: CatalogProduct

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: "tshirt")
                    .font(.system(size: 30, weight: .light))
                    .accessibilityHidden(true)
                Text("Photo unavailable")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.secondary)
            .frame(width: 100, height: 112)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Product photo unavailable")

            VStack(alignment: .leading, spacing: 7) {
                Text(product.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(categoryDisplayName(product.category))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(availabilitySummary)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                if let price = product.price {
                    if let formatted = price.formatted() {
                        Text("From \(formatted)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    } else {
                        Text("Starting price unavailable")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Starting price not provided")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var availabilitySummary: String {
        guard !product.variants.isEmpty else { return "Availability not provided" }
        let listedAvailable = product.variants.lazy.filter { $0.availability == .available }.count
        if listedAvailable == product.variants.count { return "All sizes listed as available" }
        if listedAvailable > 0 { return "Some sizes listed as available" }
        if product.variants.contains(where: { $0.availability == .unknown }) { return "Availability unknown" }
        if product.variants.contains(where: { $0.availability == .outOfStock }) { return "Listed as out of stock" }
        if product.variants.contains(where: { $0.availability == .discontinued }) { return "Discontinued" }
        return "No availability listed"
    }
}

private struct CatalogNotice: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("catalog.retry")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct CatalogSection: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct MeasurementDisplayRow: Identifiable {
    let name: String
    let value: String
    var id: String { name }
}

private func categoryDisplayName(_ category: CatalogCategory) -> String {
    switch category {
    case .tshirt: return "T-shirt"
    case .vest: return "Vest"
    case .unknown: return "Category not provided"
    }
}

private func sizeAvailabilityLabel(_ availability: CatalogAvailability?) -> String {
    guard let availability else { return "Not listed for this color" }
    switch availability {
    case .available: return "Listed as available"
    case .outOfStock: return "Listed as out of stock"
    case .unknown: return "Availability unknown"
    case .discontinued: return "Discontinued"
    }
}

private func variantAvailabilityLabel(_ availability: CatalogAvailability) -> String {
    switch availability {
    case .available: return "Listed as available; inventory isn’t verified."
    case .outOfStock: return "This size is listed as out of stock."
    case .unknown: return "Availability for this size is unknown."
    case .discontinued: return "This size is listed as discontinued."
    }
}

private func swatchColor(_ hex: String?) -> Color {
    guard let hex else { return Color.secondary.opacity(0.16) }
    let digits = String(hex.dropFirst())
    guard let value = UInt64(digits, radix: 16) else { return Color.secondary.opacity(0.16) }
    return Color(
        red: Double((value >> 16) & 0xFF) / 255,
        green: Double((value >> 8) & 0xFF) / 255,
        blue: Double(value & 0xFF) / 255
    )
}

private func measurementEntries(_ measurements: CatalogFinishedMeasurements) -> [MeasurementDisplayRow] {
    let labels: [(CatalogGarmentDimension, String)] = [
        (.chestFlatWidth, "Chest flat width"),
        (.shoulderWidth, "Shoulder width"),
        (.bodyLength, "Body length"),
        (.sleeveLength, "Sleeve length")
    ]
    let unit: String
    switch measurements.unit {
    case .centimeters: unit = "cm"
    case .inches: unit = "in"
    case .meters: unit = "m"
    }
    return labels.compactMap { pair in
        let (dimension, label) = pair
        guard let value = measurements.values[dimension] else { return nil }
        return MeasurementDisplayRow(name: label, value: "\(value.formatted()) \(unit)")
    }
}
#endif
