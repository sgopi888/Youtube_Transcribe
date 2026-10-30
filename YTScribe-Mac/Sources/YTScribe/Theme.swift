import SwiftUI
import AppKit

/// "Liquid Graphite" tokens, taken from stitch_ytscribe_macos_suite (tailwind config in each code.html).
extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

enum Theme {
    static let surface = Color(hex: 0x0F131C)
    static let lowest = Color(hex: 0x0A0E17)
    static let low = Color(hex: 0x181B25)
    static let container = Color(hex: 0x1C1F29)
    static let high = Color(hex: 0x262A34)
    static let highest = Color(hex: 0x31353F)
    static let onSurface = Color(hex: 0xDFE2EF)
    static let variant = Color(hex: 0xC7C4D7)
    static let outline = Color(hex: 0x908FA0)
    static let outlineVariant = Color(hex: 0x464554)
    static let primary = Color(hex: 0xC0C1FF)
    static let onPrimary = Color(hex: 0x1000A9)
    static let primaryContainer = Color(hex: 0x8083FF)
    static let secondary = Color(hex: 0xD0BCFF)
    static let secondaryContainer = Color(hex: 0x571BC1)
    static let tertiary = Color(hex: 0x4CD7F6)
    static let error = Color(hex: 0xFFB4AB)

    // Names used by History / Markdown.
    static let accent = primary
    static let accentText = primary
    static let violet = secondary
    static let cyan = tertiary
    static let gradient = LinearGradient(colors: [primaryContainer, secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let progress = LinearGradient(colors: [primary, tertiary], startPoint: .leading, endPoint: .trailing)
}

extension Font {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }
}

extension View {
    /// Surface card: rounded-xl, surface-container-low.
    func card(_ padding: CGFloat = 16, fill: Color = Theme.low, radius: CGFloat = 12) -> some View {
        self.padding(padding).background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
    func sectionLabel() -> some View {
        font(.ui(11, .medium)).tracking(1.1).textCase(.uppercase).foregroundStyle(Theme.variant.opacity(0.8))
    }
}

/// Recessed capsule with a sliding pill (header tabs, Rendered / Raw, History kinds).
struct GlassSegmented<T: Hashable>: View {
    @Binding var selection: T
    let items: [(label: String, value: T)]
    var size: CGFloat = 12
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let on = item.value == selection
                Text(item.label)
                    .font(.ui(size, on ? .medium : .regular))
                    .foregroundStyle(on ? Theme.onSurface : Theme.variant)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.highest)
                                .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.spring(duration: 0.25)) { selection = item.value } }
            }
        }
        .padding(2)
        .background(Theme.lowest.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = Theme.primary
    var text: Color = Theme.onPrimary
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(12.5, .medium)).foregroundStyle(text).lineLimit(1).fixedSize()
            .padding(.horizontal, 12).frame(height: 30)
            .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: fill.opacity(0.25), radius: 6)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(enabled ? 1 : 0.4)
    }
}

struct GlassButtonStyle: ButtonStyle {
    var fill: Color = Theme.high
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(12.5, .medium)).foregroundStyle(Theme.onSurface).lineLimit(1).fixedSize()
            .padding(.horizontal, 12).frame(height: 30)
            .background(configuration.isPressed ? Theme.highest : fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(enabled ? 1 : 0.4)
    }
}

/// Square icon button (pause / cancel / reveal in the mockups).
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 32
    var fill: Color = Theme.high
    var tint: Color = Theme.onSurface
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(13, .medium)).foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(configuration.isPressed ? Theme.highest : fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(enabled ? 1 : 0.4)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle { static var primary: PrimaryButtonStyle { .init() } }
extension ButtonStyle where Self == GlassButtonStyle {
    static var glass: GlassButtonStyle { .init() }
    static var ghost: GlassButtonStyle { .init(fill: .clear) }
}
extension ButtonStyle where Self == IconButtonStyle { static var icon: IconButtonStyle { .init() } }

/// Tinted capsule badge for job status.
struct Pill<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: Content
    var body: some View {
        HStack(spacing: 4) { content }
            .font(.mono(10.5, .medium))
            .padding(.horizontal, 7).frame(height: 20)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .foregroundStyle(tint)
    }
}

/// Small rectangular metadata chip (format, model, version tags).
struct Tag: View {
    let text: String
    var icon: String? = nil
    var tint: Color = Theme.variant
    var fill: Color = Theme.highest.opacity(0.6)
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.ui(10)) }
            Text(text)
        }
        .font(.mono(11)).foregroundStyle(tint)
        .padding(.horizontal, 7).frame(height: 22)
        .background(fill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// Thin progress track with the primary→tertiary fill. `nil` shows a sliding indeterminate segment.
struct ProgressBar: View {
    let value: Double?
    var height: CGFloat = 4
    var fill: AnyShapeStyle = AnyShapeStyle(Theme.progress)
    @State private var phase = false

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.highest)
                if let value {
                    Capsule().fill(fill).frame(width: max(height, g.size.width * min(max(value, 0), 1)))
                        .animation(.easeOut(duration: 0.3), value: value)
                } else {
                    Capsule().fill(fill).frame(width: g.size.width * 0.3)
                        .offset(x: phase ? g.size.width * 0.7 : 0)
                        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: phase)
                        .onAppear { phase = true }
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

/// Colored dot with a soft glow, used for live status.
struct StatusDot: View {
    var color: Color = Theme.tertiary
    var size: CGFloat = 7
    var body: some View { Circle().fill(color).frame(width: size, height: size).shadow(color: color.opacity(0.8), radius: 3) }
}

/// YouTube thumbnail for a video ID, or a gradient tile with an icon for local files.
struct Thumb: View {
    let videoID: String?
    var icon = "music.note"
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.secondaryContainer.opacity(0.6), Theme.high], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let videoID, let url = URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg") {
                AsyncImage(url: url) { img in img.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                    Image(systemName: icon).font(.ui(20)).foregroundStyle(Theme.primary.opacity(0.6))
                }
            } else {
                Image(systemName: icon).font(.ui(20)).foregroundStyle(Theme.primary)
            }
        }
        .clipped()
    }
}

/// "~/Music/YTScribe/" style path for display.
func tildePath(_ url: URL) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let p = url.path
    return (p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p) + (url.hasDirectoryPath ? "/" : "")
}

func folderSize(_ dir: URL) -> (bytes: Int64, files: Int) {
    let fm = FileManager.default
    guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: .skipsHiddenFiles) else { return (0, 0) }
    var total: Int64 = 0, n = 0
    for case let f as URL in e {
        guard let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), v.isRegularFile == true else { continue }
        total += Int64(v.fileSize ?? 0); n += 1
    }
    return (total, n)
}

func byteString(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }

func revealInFinder(_ url: URL) {
    if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    else { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); NSWorkspace.shared.open(url) }
}
