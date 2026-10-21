#if DEBUG
import SwiftUI

/// Navigation composition, not a consumer journey or an avatar-readiness decision.
struct InternalDevelopmentHub: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label("Internal development only", systemImage: "hammer")
                    .font(.headline)
                Text("Test the modules independently")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Scanner observations remain experimental. No personalized avatar, try-on or validated fit is available. Physical scanner validation is NOT RUN.")
                    .foregroundStyle(.secondary)

                NavigationLink {
                    AvatarPilotRootView()
                } label: {
                    Label("Avatar foundation and scanner", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("internal.open-avatar")

                NavigationLink {
                    CatalogRootView()
                } label: {
                    Label("Offline sample catalog", systemImage: "tshirt")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("internal.open-catalog")

                Text("Catalog browsing needs no avatar or body information. Products, prices and availability are fictional fixtures, not retailer offers.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Internal Development")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("internal-development-hub")
    }
}
#endif
