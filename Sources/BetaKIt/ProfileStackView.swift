//
//  ProfileStackView.swift
//  BetaKit
//
//  Created by Andreas Ink on 2/6/26.
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ProfileStackView: View {
    enum AvatarSource: Hashable {
        case appIcon
        case asset(name: String)
        case remote(URL)
        case system(name: String)
    }

    let avatars: [AvatarSource]
    var size: CGFloat = 48
    var overlap: CGFloat = 14

    init(imageNames: [String], size: CGFloat = 48, overlap: CGFloat = 14) {
        self.avatars = imageNames.map { .asset(name: $0) }
        self.size = size
        self.overlap = overlap
    }

    init(
        appIcon: Bool,
        remoteProfileURL: URL?,
        fallbackImageNames: [String] = [],
        size: CGFloat = 48,
        overlap: CGFloat = 14
    ) {
        var sources: [AvatarSource] = []
        if appIcon {
            sources.append(.appIcon)
        }
        if let remoteProfileURL {
            sources.append(.remote(remoteProfileURL))
        }
        sources.append(contentsOf: fallbackImageNames.map { .asset(name: $0) })
        if sources.isEmpty {
            sources = [.system(name: "person.crop.circle.fill")]
        }

        self.avatars = sources
        self.size = size
        self.overlap = overlap
    }

    var body: some View {
        HStack(spacing: -overlap) {
            ForEach(Array(avatars.enumerated()), id: \.offset) { _, source in
                AvatarView(source: source, size: size)
            }
        }
    }
}

private extension ProfileStackView {
    @MainActor
    struct AvatarView: View {
        let source: AvatarSource
        let size: CGFloat

        var body: some View {
            avatarContent
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                )
                .background {
                    Circle()
                        .foregroundStyle(.thickMaterial)
                }
                .shadow(color: Color.black.opacity(0.15), radius: 4, y: 2)
        }

        @ViewBuilder
        private var avatarContent: some View {
            switch source {
            case .remote(let url):
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        fallbackImage.resizable().scaledToFill()
                    }
                }
            default:
                fallbackImage.resizable().scaledToFill()
            }
        }

        private var fallbackImage: Image {
            switch source {
            case .appIcon:
                if let image = AppIconProvider.image {
                    return image
                }
                return Image(systemName: "app.fill")
            case .asset(let name):
                #if os(iOS)
                if let uiImage = UIImage(named: name) {
                    return Image(uiImage: uiImage)
                }
                #elseif os(macOS)
                if let nsImage = NSImage(named: name) {
                    return Image(nsImage: nsImage)
                }
                #endif
                return Image(systemName: "person.crop.circle.fill")
            case .system(let name):
                return Image(systemName: name)
            case .remote:
                return Image(systemName: "person.crop.circle.fill")
            }
        }
    }

    enum AppIconProvider {
        #if os(iOS)
        static var image: Image? {
            guard
                let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
                let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
                let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
                let iconName = iconFiles.last,
                let uiImage = UIImage(named: iconName)
            else {
                return nil
            }
            return Image(uiImage: uiImage)
        }
        #elseif os(macOS)
        @MainActor
        static var image: Image? {
            Image(nsImage: NSApplication.shared.applicationIconImage)
        }
        #else
        static var image: Image? { nil }
        #endif
    }

}

#Preview {
    ProfileStackView(
        appIcon: true,
        remoteProfileURL: URL(string: "https://example.com/profile.png"),
        fallbackImageNames: []
    )
    .padding()
}

private extension ProfileStackView {
    static func legacyPreviewNames() -> [String] {
        ["dev-andreas", "dev-dog", "dev-walklock"]
    }
}

#Preview("Legacy Asset Names") {
    ProfileStackView(imageNames: ProfileStackView.legacyPreviewNames())
        .padding()
}
