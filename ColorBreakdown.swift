import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Version & updates

enum AppInfo {
    /// Bump for every release; the release tag must match (v1.2.0). build.sh reads this line.
    static let version = "1.2.0"
    /// GitHub "owner/repo" whose Releases are checked on launch. "" disables update checks.
    static let updateRepo = "Buffalo-Stampeders/color-breakdown"
}

enum UpdateChecker {
    struct Release {
        let version: String
        let page: URL
    }

    /// "v1.10.0" -> [1, 10, 0]
    static func components(_ version: String) -> [Int] {
        var s = version.trimmingCharacters(in: .whitespaces)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        return s.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The latest GitHub release, or nil on any failure (offline, no releases, private repo, bad JSON).
    static func latestRelease() async -> Release? {
        guard !AppInfo.updateRepo.isEmpty,
              let api = URL(string: "https://api.github.com/repos/\(AppInfo.updateRepo)/releases/latest")
        else { return nil }
        var request = URLRequest(url: api, timeoutInterval: 8)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:))
        else { return nil }
        return Release(version: tag, page: page)
    }

    /// Launch checks stay silent unless there's an update; the menu command (`interactive`)
    /// also reports "up to date" or that the check failed.
    @MainActor
    static func check(interactive: Bool) async {
        let release = await latestRelease()
        let alert = NSAlert()
        if let release = release, isNewer(release.version, than: AppInfo.version) {
            let latest = release.version.hasPrefix("v") ? String(release.version.dropFirst()) : release.version
            alert.messageText = "Update available"
            alert.informativeText = "Color Breakdown \(latest) is available. You have \(AppInfo.version)."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.page)
            }
        } else if interactive {
            if release != nil {
                alert.messageText = "You're up to date"
                alert.informativeText = "Color Breakdown \(AppInfo.version) is the latest version."
            } else {
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = "Check your internet connection and try again."
            }
            alert.runModal()
        }
    }
}

// MARK: - Analysis

enum Precision: String, CaseIterable, Identifiable {
    case exact = "Exact"
    case fine = "Fine"
    case medium = "Medium"
    case coarse = "Coarse"

    var id: String { rawValue }

    /// Bits kept per RGB channel. 8 = every distinct colour, lower = similar colours merged.
    var bits: Int {
        switch self {
        case .exact:  return 8
        case .fine:   return 6
        case .medium: return 5
        case .coarse: return 4
        }
    }

    var help: String {
        switch self {
        case .exact:  return "Every distinct RGB value is listed separately."
        case .fine:   return "Colors within ~4 levels per channel are merged."
        case .medium: return "Colors within ~8 levels per channel are merged."
        case .coarse: return "Colors within ~16 levels per channel are merged."
        }
    }
}

struct ColorEntry: Identifiable, Hashable {
    let id: UInt32          // bucket key
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let count: Int

    var hex: String { String(format: "#%02X%02X%02X", Int(r), Int(g), Int(b)) }
    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
}

struct AnalysisResult {
    let entries: [ColorEntry]     // sorted most → least common
    let totalPixels: Int          // non-transparent pixels counted
    let width: Int
    let height: Int
    let downsampled: Bool
}

enum ImageAnalyzer {
    static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func analyze(_ image: CGImage, precision: Precision) -> AnalysisResult {
        // Very large images are scaled down so analysis stays fast.
        let maxDim = 4096
        var w = image.width
        var h = image.height
        var downsampled = false
        if max(w, h) > maxDim {
            let s = Double(maxDim) / Double(max(w, h))
            w = max(1, Int(Double(w) * s))
            h = max(1, Int(Double(h) * s))
            downsampled = true
        }

        let bytesPerRow = w * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * h)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress,
                                      width: w, height: h,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else {
            return AnalysisResult(entries: [], totalPixels: 0, width: w, height: h, downsampled: downsampled)
        }

        struct Acc {
            var n = 0, r = 0, g = 0, b = 0
            mutating func add(_ r: Int, _ g: Int, _ b: Int) {
                n += 1; self.r += r; self.g += g; self.b += b
            }
        }

        let shift = 8 - precision.bits
        let mask = UInt8(truncatingIfNeeded: 0xFF << shift)
        var buckets = [UInt32: Acc]()
        var total = 0

        pixels.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            let end = w * h * 4
            var i = 0
            while i < end {
                let a = Int(p[i + 3])
                if a != 0 {
                    var r = Int(p[i]), g = Int(p[i + 1]), b = Int(p[i + 2])
                    if a < 255 {   // un-premultiply partially transparent pixels
                        r = min(255, r * 255 / a)
                        g = min(255, g * 255 / a)
                        b = min(255, b * 255 / a)
                    }
                    let key = (UInt32(UInt8(r) & mask) << 16)
                            | (UInt32(UInt8(g) & mask) << 8)
                            |  UInt32(UInt8(b) & mask)
                    buckets[key, default: Acc()].add(r, g, b)
                    total += 1
                }
                i += 4
            }
        }

        var entries = buckets.map { key, acc -> ColorEntry in
            ColorEntry(id: key,
                       r: UInt8(acc.r / acc.n),
                       g: UInt8(acc.g / acc.n),
                       b: UInt8(acc.b / acc.n),
                       count: acc.n)
        }
        entries.sort { $0.count != $1.count ? $0.count > $1.count : $0.id < $1.id }

        return AnalysisResult(entries: entries, totalPixels: total, width: w, height: h, downsampled: downsampled)
    }
}

// MARK: - App state

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var imageURL: URL?
    @Published var previewImage: NSImage?
    @Published var result: AnalysisResult?
    @Published var isAnalyzing = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published var visibleLimit = 500
    /// Colors covering less than this percentage of the image are disregarded.
    @Published var minimumPercent: Double = 10
    @Published var precision: Precision = .exact {
        didSet { if precision != oldValue { reanalyze() } }
    }

    /// Entries that meet the minimum-coverage threshold.
    var qualifyingEntries: [ColorEntry] {
        guard let result = result, result.totalPixels > 0 else { return [] }
        let total = Double(result.totalPixels)
        return result.entries.filter { Double($0.count) / total * 100 >= minimumPercent }
    }

    private var cgImage: CGImage?
    private var analysisTask: Task<Void, Never>?

    func open(_ url: URL) {
        guard let image = ImageAnalyzer.loadImage(url) else {
            errorMessage = "\"\(url.lastPathComponent)\" couldn't be read as an image."
            return
        }
        imageURL = url
        cgImage = image
        previewImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        errorMessage = nil
        searchText = ""
        visibleLimit = 500
        reanalyze()
    }

    func reanalyze() {
        guard let image = cgImage else { return }
        analysisTask?.cancel()
        isAnalyzing = true
        let precision = self.precision
        analysisTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                ImageAnalyzer.analyze(image, precision: precision)
            }.value
            guard !Task.isCancelled else { return }
            self?.result = result
            self?.isAnalyzing = false
        }
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an image to analyze"
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    func exportCSV() {
        guard let result = result else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        let base = imageURL?.deletingPathExtension().lastPathComponent ?? "image"
        panel.nameFieldStringValue = "\(base)-colors.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var csv = "hex,red,green,blue,pixels,percent\n"
        let total = max(1, result.totalPixels)
        for e in qualifyingEntries {
            let pct = Double(e.count) / Double(total) * 100
            csv += "\(e.hex),\(e.r),\(e.g),\(e.b),\(e.count),\(String(format: "%.4f", pct))\n"
        }
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Couldn't save CSV: \(error.localizedDescription)"
        }
    }
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await UpdateChecker.check(interactive: false) }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { AppModel.shared.open(url) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ColorBreakdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("Color Breakdown") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 780, minHeight: 500)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await UpdateChecker.check(interactive: true) }
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open Image…") { model.presentOpenPanel() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Export CSV…") { model.exportCSV() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(model.result == nil)
            }
        }
    }
}

// MARK: - Views

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var dropTargeted = false
    @State private var copiedHex: String?

    var body: some View {
        Group {
            if model.result == nil && !model.isAnalyzing {
                emptyState
            } else {
                analysisView
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: handleDrop)
        .overlay(dropOverlay)
        .navigationTitle(model.imageURL?.lastPathComponent ?? "Color Breakdown")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.presentOpenPanel() } label: {
                    Label("Open Image", systemImage: "photo")
                }
                .help("Open an image (⌘O)")
            }
            ToolbarItem {
                Button { model.exportCSV() } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(model.result == nil)
                .help("Export all colors to CSV (⌘E)")
            }
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(.secondary)
            Text("Drop an image here")
                .font(.title2)
            Text("PNG, JPEG, HEIC, TIFF, GIF, BMP, WebP and more")
                .foregroundColor(.secondary)
            Button("Open Image…") { model.presentOpenPanel() }
                .keyboardShortcut(.defaultAction)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Analysis layout

    private var analysisView: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 270)
            Divider()
            colorList
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let image = model.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 200)
                    .background(checkerboard)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
            }

            if let url = model.imageURL {
                Text(url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(2)
            }

            if let result = model.result {
                VStack(alignment: .leading, spacing: 4) {
                    statLine("Size", "\(result.width) × \(result.height)" + (result.downsampled ? " (scaled)" : ""))
                    statLine("Pixels counted", result.totalPixels.formatted())
                    statLine("Unique colors", result.entries.count.formatted())
                    statLine("Shown", model.qualifyingEntries.count.formatted())
                }
                .font(.callout)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Minimum coverage").font(.caption).foregroundColor(.secondary)
                Stepper(value: $model.minimumPercent, in: 0...100, step: 1) {
                    Text(String(format: "%.0f%% of image", model.minimumPercent))
                        .font(.system(.callout, design: .monospaced))
                }
                Text("Colors covering less than this are disregarded.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Grouping").font(.caption).foregroundColor(.secondary)
                Picker("", selection: $model.precision) {
                    ForEach(Precision.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(model.precision.help)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Click any row to copy its hex code.")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(16)
    }

    private func statLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(.callout, design: .monospaced))
        }
    }

    private var checkerboard: some View {
        Canvas { ctx, size in
            let s: CGFloat = 8
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let dark = (Int(x / s) + Int(y / s)) % 2 == 0
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)),
                             with: .color(dark ? Color.gray.opacity(0.25) : Color.gray.opacity(0.08)))
                    x += s
                }
                y += s
            }
        }
    }

    // MARK: Color list

    private var filteredEntries: [ColorEntry] {
        let entries = model.qualifyingEntries
        let q = model.searchText
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
            .replacingOccurrences(of: "#", with: "")
        if q.isEmpty { return entries }
        return entries.filter { $0.hex.dropFirst().contains(q) }
    }

    private var colorList: some View {
        let entries = filteredEntries
        let visible = Array(entries.prefix(model.visibleLimit))
        let total = max(1, model.result?.totalPixels ?? 1)

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Filter by hex (e.g. FF00)", text: $model.searchText)
                    .textFieldStyle(.plain)
                if !model.searchText.isEmpty {
                    Button { model.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("\(entries.count.formatted()) colors")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if model.isAnalyzing {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Analyzing…").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(.secondary)
                    Text(model.searchText.isEmpty
                         ? String(format: "No color covers at least %.0f%% of the image.", model.minimumPercent)
                         : "No matching colors.")
                        .foregroundColor(.secondary)
                    if model.searchText.isEmpty {
                        Text("Lower the minimum coverage or choose a coarser grouping.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { entry in
                            ColorRow(entry: entry,
                                     percent: Double(entry.count) / Double(total) * 100,
                                     copied: copiedHex == entry.hex) {
                                copy(entry.hex)
                            }
                            Divider().padding(.leading, 70)
                        }
                        if entries.count > visible.count {
                            Button("Show \((entries.count - visible.count).formatted()) more") {
                                model.visibleLimit += 1000
                            }
                            .padding(14)
                        }
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func copy(_ hex: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(hex, forType: .string)
        copiedHex = hex
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedHex == hex { copiedHex = nil }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else { return false }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data = data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in AppModel.shared.open(url) }
        }
        return true
    }

    @ViewBuilder
    private var dropOverlay: some View {
        if dropTargeted {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.08)))
                .padding(8)
                .allowsHitTesting(false)
        }
    }
}

struct ColorRow: View {
    let entry: ColorEntry
    let percent: Double
    let copied: Bool
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 5)
                .fill(entry.color)
                .frame(width: 44, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15)))

            Text(entry.hex)
                .font(.system(.body, design: .monospaced))
                .frame(width: 90, alignment: .leading)
                .textSelection(.enabled)

            Text(copied ? "Copied" : "")
                .font(.caption)
                .foregroundColor(.green)
                .frame(width: 50, alignment: .leading)

            Spacer()

            Text(String(format: "%.2f%%", percent))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)

            Text("\(entry.count.formatted()) px")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onCopy)
        .contextMenu {
            Button("Copy \(entry.hex)", action: onCopy)
        }
    }
}
