import SwiftUI
import UIKit
import WidgetKit

// Виджеты для iOS 17 и новее.
// Данные пишет приложение (lib/services/widget_sync.dart) в общую папку:
// widget.json и картинки рядом.

struct WTile {
    let id: String
    let name: String
    let kind: String
    let image: UIImage?
}

struct WModel {
    var title = "Hutred"
    var artist = "Нажми, чтобы включить волну"
    var playing = false
    var progress = 0.0
    var favorite = false
    var sharp = false
    var cover: UIImage?
    var bg = Color(argb: 0xFF141414)
    var fg = Color(argb: 0xFFF5F5F5)
    var muted = Color(argb: 0xFFA3A3A3)
    var play = Color(argb: 0xFFF5F5F5)
    var playFg = Color(argb: 0xFF000000)
    var tile = Color(argb: 0xFF262626)
    var tiles: [WTile] = []

    static func load() -> WModel {
        var m = WModel()
        guard let dir = HutredGroup.folder,
              let data = try? Data(contentsOf: dir.appendingPathComponent("widget.json")),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return m }
        func img(_ name: Any?) -> UIImage? {
            guard let n = name as? String, !n.isEmpty, !n.contains("/") else { return nil }
            return UIImage(contentsOfFile: dir.appendingPathComponent(n).path)
        }
        func col(_ key: String, _ def: Color) -> Color {
            if let v = j[key] as? NSNumber { return Color(argb: v.int64Value) }
            return def
        }
        m.title = j["title"] as? String ?? m.title
        m.artist = j["artist"] as? String ?? m.artist
        m.playing = j["playing"] as? Bool ?? false
        m.progress = (j["progress"] as? NSNumber)?.doubleValue ?? 0
        m.favorite = j["favorite"] as? Bool ?? false
        m.sharp = j["sharp"] as? Bool ?? false
        m.cover = img(j["cover"])
        m.bg = col("bg", m.bg)
        m.fg = col("fg", m.fg)
        m.muted = col("muted", m.muted)
        m.play = col("play", m.play)
        m.playFg = col("playFg", m.playFg)
        m.tile = col("tile", m.tile)
        if let tiles = j["tiles"] as? [[String: Any]] {
            m.tiles = tiles.prefix(8).map {
                WTile(id: $0["id"] as? String ?? "", name: $0["name"] as? String ?? "",
                      kind: $0["kind"] as? String ?? "", image: img($0["image"]))
            }
        }
        return m
    }
}

extension Color {
    init(argb: Int64) {
        let a = Double((argb >> 24) & 0xFF) / 255
        let r = Double((argb >> 16) & 0xFF) / 255
        let g = Double((argb >> 8) & 0xFF) / 255
        let b = Double(argb & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

struct WEntry: TimelineEntry {
    let date: Date
    let m: WModel
}

struct WProvider: TimelineProvider {
    func placeholder(in context: Context) -> WEntry { WEntry(date: Date(), m: WModel()) }

    func getSnapshot(in context: Context, completion: @escaping (WEntry) -> Void) {
        completion(WEntry(date: Date(), m: WModel.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WEntry>) -> Void) {
        // Обновляет само приложение, когда меняется трек.
        completion(Timeline(entries: [WEntry(date: Date(), m: WModel.load())], policy: .never))
    }
}

// MARK: - Части

func openURL(_ item: String) -> URL {
    let enc = item.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? item
    return URL(string: "hutred://widget/open?item=\(enc)")!
}

/// Кнопка плеера: работает прямо на виджете, без открытия Hutred.
func control<L: View>(_ cmd: String, @ViewBuilder label: () -> L) -> some View {
    Button(intent: HutredPlayerIntent(cmd)) { label() }.buttonStyle(.plain)
}

struct PlayCircle: View {
    let m: WModel
    let size: CGFloat
    var icon: String? = nil
    var body: some View {
        ZStack {
            if m.sharp {
                Rectangle().fill(m.play)
            } else {
                Circle().fill(m.play)
            }
            Image(systemName: icon ?? (m.playing ? "pause.fill" : "play.fill"))
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundColor(m.playFg)
        }
        .frame(width: size, height: size)
    }
}

struct Cover: View {
    let m: WModel
    let size: CGFloat
    var radius: CGFloat = 10
    var body: some View {
        Group {
            if let c = m.cover {
                Image(uiImage: c).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(m.tile)
                    .overlay(Image(systemName: "music.note").foregroundColor(m.muted))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: m.sharp ? 0 : radius, style: .continuous))
    }
}

struct Logo: View {
    let m: WModel
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: m.sharp ? 0 : 6, style: .continuous).fill(m.fg)
            Image(systemName: "waveform").font(.system(size: 11, weight: .bold)).foregroundColor(m.bg)
        }
        .frame(width: 20, height: 20)
    }
}

struct Progress: View {
    let m: WModel
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(m.fg.opacity(0.25))
                Rectangle().fill(m.fg).frame(width: g.size.width * max(0, min(1, m.progress)))
            }
        }
        .frame(height: 3)
    }
}

struct TileView: View {
    let t: WTile
    let m: WModel
    var body: some View {
        Link(destination: openURL(t.id)) {
            ZStack {
                if let img = t.image {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(tileColor)
                    Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: m.sharp ? 0 : 10, style: .continuous))
        }
    }

    var tileColor: Color {
        switch t.kind {
        case "fav": return Color(argb: 0xFF6A4CF0)
        case "wave": return Color(argb: 0xFF1F8A6A)
        case "downloads": return Color(argb: 0xFF3A3A3A)
        default: return m.tile
        }
    }

    var icon: String {
        switch t.kind {
        case "fav": return "heart.fill"
        case "wave": return "waveform.path"
        case "downloads": return "arrow.down"
        default: return "music.note.list"
        }
    }
}

extension View {
    func widgetBackground(_ color: Color) -> some View {
        containerBackground(for: .widget) { color }
    }
}

// MARK: - Виджеты

struct NowSmallView: View {
    let m: WModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Cover(m: m, size: 72)
                Spacer()
                Logo(m: m)
            }
            Spacer(minLength: 6)
            HStack(alignment: .bottom, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.sharp ? m.title.uppercased() : m.title)
                        .font(.system(size: 14, weight: .bold)).foregroundColor(m.fg).lineLimit(1)
                    Text(m.artist).font(.system(size: 11)).foregroundColor(m.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                control("toggle") { PlayCircle(m: m, size: 40) }
            }
        }
        .padding(14)
        .widgetURL(openURL("now"))
        .widgetBackground(m.bg)
    }
}

struct WaveSmallView: View {
    let m: WModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: m.sharp ? 0 : 12, style: .continuous).fill(m.tile)
                    Image(systemName: "waveform.path").font(.system(size: 24, weight: .semibold)).foregroundColor(m.fg)
                }
                .frame(width: 52, height: 52)
                Spacer()
                Logo(m: m)
            }
            Spacer(minLength: 6)
            HStack(alignment: .bottom, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.sharp ? "МОЯ ВОЛНА" : "Моя волна")
                        .font(.system(size: 15, weight: .bold)).foregroundColor(m.fg)
                    Text("подборка под тебя").font(.system(size: 11)).foregroundColor(m.muted)
                }
                Spacer(minLength: 0)
                PlayCircle(m: m, size: 40, icon: "play.fill")
            }
        }
        .padding(14)
        .widgetURL(openURL("wave"))
        .widgetBackground(m.bg)
    }
}

struct PlayerView: View {
    let m: WModel
    @Environment(\.widgetFamily) var family

    var body: some View {
        if family == .systemLarge { large } else { medium }
    }

    var texts: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(m.sharp ? m.title.uppercased() : m.title)
                .font(.system(size: family == .systemLarge ? 17 : 14, weight: .bold))
                .foregroundColor(m.fg).lineLimit(1)
            Text(m.artist).font(.system(size: family == .systemLarge ? 12 : 11))
                .foregroundColor(m.muted).lineLimit(1)
        }
    }

    func icon(_ name: String, _ size: CGFloat) -> some View {
        Image(systemName: name).font(.system(size: size, weight: .bold)).foregroundColor(m.fg)
            .frame(width: size + 14, height: 40)
    }

    func tiles(_ range: Range<Int>) -> some View {
        HStack(spacing: 8) {
            ForEach(range, id: \.self) { i in
                if i < m.tiles.count {
                    TileView(t: m.tiles[i], m: m)
                } else {
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
    }

    var medium: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Link(destination: openURL("now")) { Cover(m: m, size: 44, radius: 8) }
                texts
                Spacer(minLength: 0)
                control("prev") { icon("backward.end.fill", 15) }
                control("toggle") { PlayCircle(m: m, size: 40) }
                control("next") { icon("forward.end.fill", 15) }
            }
            Progress(m: m).padding(.horizontal, -14)
            tiles(0..<4)
        }
        .padding(14)
        .widgetBackground(m.bg)
    }

    var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Link(destination: openURL("now")) { Cover(m: m, size: 108) }
                VStack(alignment: .leading, spacing: 0) {
                    HStack { Spacer(); Logo(m: m) }
                    texts.padding(.top, 4)
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        control("prev") { icon("backward.end.fill", 17) }
                        control("toggle") { PlayCircle(m: m, size: 44) }
                        control("next") { icon("forward.end.fill", 17) }
                        Spacer(minLength: 0)
                        control("like") { icon(m.favorite ? "heart.fill" : "heart", 17) }
                    }
                }
                .frame(height: 108)
            }
            Progress(m: m).padding(.horizontal, -16)
            Text("НЕДАВНЕЕ").font(.system(size: 11, weight: .semibold)).kerning(0.6)
                .foregroundColor(m.muted).padding(.bottom, -4)
            tiles(0..<4)
            tiles(4..<8)
        }
        .padding(16)
        .widgetBackground(m.bg)
    }
}

struct HutredNowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HutredNow", provider: WProvider()) { e in NowSmallView(m: e.m) }
            .configurationDisplayName("Сейчас играет")
            .description("Трек и кнопка паузы")
            .supportedFamilies([.systemSmall])
            .contentMarginsDisabled()
    }
}

struct HutredWaveWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HutredWave", provider: WProvider()) { e in WaveSmallView(m: e.m) }
            .configurationDisplayName("Моя волна")
            .description("Включить волну одним нажатием")
            .supportedFamilies([.systemSmall])
            .contentMarginsDisabled()
    }
}

struct HutredPlayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HutredPlayer", provider: WProvider()) { e in PlayerView(m: e.m) }
            .configurationDisplayName("Плеер Hutred")
            .description("Трек, кнопки и быстрый доступ к плейлистам")
            .supportedFamilies([.systemMedium, .systemLarge])
            .contentMarginsDisabled()
    }
}

@main
struct HutredWidgets: WidgetBundle {
    var body: some Widget {
        HutredNowWidget()
        HutredWaveWidget()
        HutredPlayerWidget()
    }
}
