// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

// MARK: - what's new

/// What this version brought, shown once after updating to it (not on a first install: onboarding is the welcome then).
enum WhatsNew {
    struct Item: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        var id: String { title }
    }

    /// The version whose notes these are. A build of the same version shows nothing again.
    static let version = "1.0.1"
    static let items: [Item] = [
        Item(symbol: "bag.fill", title: "Google Play",
             detail: "在「商店」标签页获取游戏。Play 商店的下载内容（含拆分 APK 与资源包）会在转译层中运行。"),
        Item(symbol: "checkmark.seal.fill", title: "Google Play 服务",
             detail: "游戏会认为 Play 服务已存在但未登录，因此不再反复索取，可以继续运行。"),
        Item(symbol: "arrow.up.doc.fill", title: "存档备份",
             detail: "在游戏页面把存档备份为 .zip，之后随时恢复，也可以转移到另一台设备。"),
        Item(symbol: "exclamationmark.bubble.fill", title: "崩溃报告",
             detail: "当游戏导致 Husk 退出时，下次启动会说明发生了什么，并给你一份可分享的报告。"),
        Item(symbol: "checkmark.circle.fill", title: "了解哪些能跑",
             detail: "库中的每个游戏都会标注上次的结果：正常运行、崩溃，还是没能启动。"),
        Item(symbol: "gamecontroller.fill", title: "Godot 游戏",
             detail: "用 Godot 3 和 4 制作的游戏现在可以在转译层中运行了。"),
        Item(symbol: "slider.horizontal.below.square.and.square.filled", title: "自定义按键",
             detail: "每个游戏都可以单独移动、调整大小和隐藏屏幕控制器上的按钮。"),
        Item(symbol: "keyboard.fill", title: "在 Minecraft 中输入",
             detail: "聊天、告示牌和世界名称等输入框都会唤出键盘。"),
        Item(symbol: "arrow.left.arrow.right", title: "切换游戏",
             detail: "关闭 Husk 即可换成另一个游戏，再次打开 Husk 时它会自动启动。"),
        Item(symbol: "puzzlepiece.extension.fill", title: "Geode",
             detail: "为 Geometry Dash 提供 mod 支持（含 Geode 5），在游戏设置中开启。"),
    ]

    private static let seenKey = "husk.whatsNew.seen"

    /// Whether to show the notes now: an update to this version, not a new install.
    static var due: Bool {
        let seen = UserDefaults.standard.string(forKey: seenKey)
        if seen == version { return false }
        if Onboarding.needed { markSeen(); return false }       // a first install: onboarding welcomes them
        return true
    }

    static func markSeen() { UserDefaults.standard.set(version, forKey: seenKey) }
}

struct WhatsNewSheet: View {
    var done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Husk \(WhatsNew.version) 更新内容").font(.largeTitle.weight(.bold))
                        Text("首个正式版本。").foregroundStyle(.secondary)
                    }
                    .padding(.top, 36)
                    ForEach(WhatsNew.items) { item in
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 26))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.headline)
                                Text(item.detail).font(.subheadline).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
            }
            Button(action: done) {
                Text("继续").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .interactiveDismissDisabled()
    }
}

// MARK: - a newer Husk

/// A newer Husk on GitHub: the releases page is asked at launch (at most twice a day) and the person is told once per release.
@MainActor
final class AppUpdates: ObservableObject {
    static let shared = AppUpdates()

    struct Release: Equatable {
        let version: String
        let page: URL
    }

    @Published var available: Release?

    private static let api = URL(string: "https://api.github.com/repos/Leviidev/Husk/releases/latest")!
    private static let checkedKey = "husk.updates.checked", dismissedKey = "husk.updates.dismissed"

    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    func check() async {
        let d = UserDefaults.standard
        if Date().timeIntervalSince1970 - d.double(forKey: Self.checkedKey) < 12 * 3600 { return }
        var req = URLRequest(url: Self.api)
        req.timeoutInterval = 20
        req.setValue("Husk", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let page = (obj["html_url"] as? String).flatMap(URL.init(string:)) else { return }
        d.set(Date().timeIntervalSince1970, forKey: Self.checkedKey)
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard Self.newer(version, than: Self.current), d.string(forKey: Self.dismissedKey) != version else { return }
        HuskLog.log("update", "Husk \(version) is out (this is \(Self.current))")
        available = Release(version: version, page: page)
    }

    func dismiss() {
        if let v = available?.version { UserDefaults.standard.set(v, forKey: Self.dismissedKey) }
        available = nil
    }

    /// "1.0.10" is newer than "1.0.9": compared number by number.
    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
