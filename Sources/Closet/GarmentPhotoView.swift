import SwiftUI

struct GarmentPhotoView: View {
  var url: URL
  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image { Image(uiImage: image).resizable().scaledToFit().padding(8) }
      else { Image(systemName: "tshirt").font(.largeTitle).foregroundStyle(.secondary) }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task(id: url) {
      let loaded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
        guard let source = try? Data(contentsOf: url), let cg = try? GarmentImageProcessor.normalized(source) else { return nil }
        return UIImage(cgImage: cg)
      }.value
      guard !Task.isCancelled else { return }
      image = loaded
    }
  }
}
