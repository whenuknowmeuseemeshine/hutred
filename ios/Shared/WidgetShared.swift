import Foundation
import AppIntents

/// Общая папка приложения и виджета.
/// SideStore при установке меняет имя группы (дописывает свой код) и
/// записывает настоящее имя в Info.plist (ALTAppGroups) — берём оттуда.
enum HutredGroup {
    static let fallback = "group.ru.hutred.hutred"

    static var candidates: [String] {
        var out: [String] = []
        let own = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        out.append(contentsOf: own)
        // Виджет лежит внутри приложения: Runner.app/PlugIns/HutredWidget.appex
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        if appURL.pathExtension == "app", let app = Bundle(url: appURL) {
            out.append(contentsOf: app.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? [])
        }
        out.append(fallback)
        return out
    }

    static var folder: URL? {
        for id in candidates {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
                return url.appendingPathComponent("widget", isDirectory: true)
            }
        }
        return nil
    }
}

extension Notification.Name {
    static let hutredWidgetCommand = Notification.Name("HutredWidgetCommand")
}

/// Кнопки плеера на виджете (iOS 17+). AudioPlaybackIntent система
/// выполняет в самом приложении, поэтому команда доходит до плеера.
@available(iOS 17.0, *)
struct HutredPlayerIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Управление Hutred"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Команда")
    var command: String

    init() {
        self.command = "toggle"
    }

    init(_ command: String) {
        self.command = command
    }

    func perform() async throws -> some IntentResult {
        let cmd = command
        await MainActor.run {
            NotificationCenter.default.post(name: .hutredWidgetCommand, object: cmd)
        }
        return .result()
    }
}
