import SwiftUI

struct RemoteImage: View {
    let url: String?
    var contentMode: ContentMode = .fill

    var body: some View {
        if let url, let u = URL(string: url) {
            AsyncImage(url: u, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: contentMode)
                case .failure:
                    placeholder
                default:
                    placeholder.overlay(ProgressView().tint(.white.opacity(0.4)))
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Theme.surface)
            .overlay(Image(systemName: "film").foregroundStyle(.white.opacity(0.2)))
    }
}

struct PosterCard: View {
    let meta: MetaPreview
    var width: CGFloat = 112
    var progress: Double?

    private var isLandscape: Bool { meta.posterShape == "landscape" }
    private var isSquare: Bool { meta.posterShape == "square" }

    private var height: CGFloat {
        if isLandscape { return width * 9 / 16 * 1.0 }
        if isSquare { return width }
        return width * 1.5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: meta.poster)
                .frame(width: isLandscape ? width * 1.6 : width, height: isLandscape ? width : height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottom) {
                    if let progress, progress > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.black.opacity(0.6))
                                Capsule().fill(Theme.accent).frame(width: geo.size.width * progress)
                            }
                        }
                        .frame(height: 4)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.06))
                )
            Text(meta.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2, reservesSpace: true)
                .frame(width: isLandscape ? width * 1.6 : width, alignment: .leading)
        }
    }
}

struct Pill: View {
    let text: String
    var color: Color = .white.opacity(0.15)
    var foreground: Color = .white
    var outlined = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(outlined ? color : foreground)
            .background {
                if outlined {
                    Capsule().strokeBorder(color, lineWidth: 1)
                } else {
                    Capsule().fill(color)
                }
            }
    }
}

struct DubBadge: View {
    let result: DubDetector.Result

    var body: some View {
        switch result {
        case .yes:
            Pill(text: "EN DUB", color: Theme.dub, foreground: .black)
        case .likely:
            Pill(text: "EN DUB?", color: Theme.dub, outlined: true)
        }
    }
}

struct RailHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.title3.weight(.bold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

extension String {
    var capitalizedType: String {
        switch self {
        case "movie": return "Movies"
        case "series": return "Series"
        case "anime": return "Anime"
        case "tv": return "TV"
        case "channel": return "Channels"
        default: return capitalized
        }
    }
}
