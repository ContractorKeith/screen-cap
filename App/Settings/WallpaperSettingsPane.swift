import AppKit
import ScreenCapKit
import SwiftUI
import UniformTypeIdentifiers

/// The background behind "window with background" captures.
struct WallpaperSettingsPane: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Add background to window captures", isOn: $settings.windowBackground)
            } footer: {
                Text("Window captures are placed on this background with the padding below.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("Background", selection: $settings.wallpaper.style) {
                    Text("Desktop picture").tag(WallpaperOptions.Style.desktop)
                    Text("Solid color").tag(WallpaperOptions.Style.solid)
                    Text("Gradient").tag(WallpaperOptions.Style.gradient)
                    Text("Image").tag(WallpaperOptions.Style.image)
                }
                .pickerStyle(.segmented)
                switch settings.wallpaper.style {
                case .desktop:
                    Text("Uses the current desktop picture of the display being captured.")
                        .font(.caption).foregroundStyle(.secondary)
                case .solid:
                    ColorPicker("Color", selection: color(\.solidColor), supportsOpacity: false)
                case .gradient:
                    ColorPicker("Start", selection: color(\.gradientStart), supportsOpacity: false)
                    ColorPicker("End", selection: color(\.gradientEnd), supportsOpacity: false)
                    LabeledContent("Angle") {
                        Slider(value: $settings.wallpaper.gradientAngle, in: 0...360, step: 15)
                        Text("\(Int(settings.wallpaper.gradientAngle))°").monospacedDigit().frame(width: 40)
                    }
                case .image:
                    LabeledContent("Image") {
                        HStack {
                            Text(settings.wallpaper.imageURL?.lastPathComponent ?? "None")
                                .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                            Button("Choose…", action: chooseImage)
                        }
                    }
                }
                LabeledContent("Padding") {
                    Slider(value: $settings.wallpaper.padding, in: WallpaperOptions.paddingRange, step: 4)
                    Text("\(Int(settings.wallpaper.padding)) pt").monospacedDigit().frame(width: 52)
                }
            }
            Section("Preview") {
                preview
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
    }

    /// A scaled-down window on the chosen background.
    private var preview: some View {
        GeometryReader { proxy in
            let scale = proxy.size.height / 400
            ZStack {
                background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(radius: 6)
                    .padding(settings.wallpaper.padding * scale)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .aspectRatio(16 / 10, contentMode: .fit)
    }

    @ViewBuilder private var background: some View {
        let options = settings.wallpaper
        switch options.style {
        case .solid:
            Color(options.solidColor)
        case .gradient:
            LinearGradient(colors: [Color(options.gradientStart), Color(options.gradientEnd)],
                           startPoint: UnitPoint(angle: options.gradientAngle, from: true),
                           endPoint: UnitPoint(angle: options.gradientAngle, from: false))
        case .desktop, .image:
            if let image = backgroundImage(options) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
    }

    private func backgroundImage(_ options: WallpaperOptions) -> NSImage? {
        let url = options.style == .image
            ? options.imageURL
            : NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        return url.flatMap(NSImage.init(contentsOf:))
    }

    private func color(_ keyPath: WritableKeyPath<WallpaperOptions, RGBAColor>) -> Binding<Color> {
        Binding(
            get: { Color(settings.wallpaper[keyPath: keyPath]) },
            set: { settings.wallpaper[keyPath: keyPath] = RGBAColor($0) }
        )
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.wallpaper.imageURL = url
        }
    }
}

extension Color {
    init(_ color: RGBAColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}

extension RGBAColor {
    init(_ color: Color) {
        let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: rgb.alphaComponent)
    }
}

private extension UnitPoint {
    /// Gradient endpoint for an angle in degrees, clockwise from left→right (y down).
    init(angle degrees: Double, from start: Bool) {
        let radians = degrees * .pi / 180
        let dx = cos(radians) / 2
        let dy = sin(radians) / 2
        self.init(x: 0.5 + (start ? -dx : dx), y: 0.5 + (start ? -dy : dy))
    }
}
