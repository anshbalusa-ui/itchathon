import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: ProfileStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FitCheck")
                        .font(.largeTitle.bold())
                    Text("Know how it fits before you buy it.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    BodyProfileView()
                } label: {
                    HomeCard(
                        title: store.bodyProfile.isUsable ? "Your fit profile" : "Create your fit profile",
                        subtitle: store.bodyProfile.isUsable ? "Measurements saved on this phone" : "Start with the measurements that matter most",
                        icon: "person.crop.rectangle"
                    )
                }

                NavigationLink {
                    GarmentScanView()
                } label: {
                    HomeCard(
                        title: "Scan a garment",
                        subtitle: "Measure chest, shoulders, waist, and length",
                        icon: "tshirt"
                    )
                }
                .disabled(!store.bodyProfile.isUsable)

                if let comparison = store.sizeComparison {
                    NavigationLink {
                        SizeComparisonView(comparison: comparison)
                    } label: {
                        HomeCard(
                            title: comparison.closestMatch.map { "Closest size match: \($0.sizeLabel)" } ?? "Compare sizes",
                            subtitle: comparison.closestMatch.map {
                                "Fit Score \(formatScore($0.report.score)) · 0 is ideal"
                            } ?? "See how every available size would fit",
                            icon: "square.grid.2x2"
                        )
                    }
                }

                if let report = store.lastReport {
                    NavigationLink {
                        FitResultView(report: report)
                    } label: {
                        HomeCard(
                            title: "\(formatScore(report.score)) Fit Score",
                            subtitle: "Single scanned garment · \(report.band.rawValue)",
                            icon: "checkmark.seal"
                        )
                    }
                }

                Button("Load demo data") {
                    store.loadDemoData()
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formatScore(_ score: Int) -> String {
        score > 0 ? "+\(score)" : "\(score)"
    }
}

private struct HomeCard: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
