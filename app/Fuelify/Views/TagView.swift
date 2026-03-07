import SwiftUI

struct TagView: View {
    let text: String?
    let systemImage: String?
    let color: Color

    init(text: String, systemImage: String? = nil, color: Color) {
        self.text = text
        self.systemImage = systemImage
        self.color = color
    }

    init(systemImage: String, color: Color) {
        self.text = nil
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        if let text {
            Label {
                Text(text)
            } icon: {
                if let systemImage {
                    Image(systemName: systemImage)
                }
            }
            .font(.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
        } else if let systemImage {
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundStyle(.white)
                .frame(width: 10, height: 10)
                .padding(4)
                .background(color, in: Circle())
        }
    }
}
