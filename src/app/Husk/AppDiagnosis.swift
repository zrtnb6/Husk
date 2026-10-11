// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// Why an app will not run, or why it stopped, in words: from what the APK is (before it starts) and from what its run logged.
///
/// Before a start it answers the questions the files can: is this an app at all, does it have code for this iPhone's CPU, is a
/// part of it missing, does it carry protection that refuses to run anywhere but a certified Android phone. After a run it reads
/// the log for the line that ended it: a crash in one of the app's libraries, the app closing itself, an exception from its Java
/// code, a feature of Android that Husk does not have yet, Google Play services it cannot do without.
struct AppDiagnosis: Identifiable, Equatable {
    enum Kind: String {
        case badAPK, unsupportedCPU, missingSplits, protected, needsGoogle, missingFeature, javaCrash, nativeCrash, closedItself,
             missingFunction, noProgress
    }
    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
    /// The log line or report field it came from, for the curious and for bug reports.
    let evidence: String?
    /// A warning before launch that still lets the app be tried.
    var blocksLaunch: Bool { kind == .badAPK || kind == .unsupportedCPU }

    static func == (a: AppDiagnosis, b: AppDiagnosis) -> Bool { a.kind == b.kind && a.title == b.title && a.detail == b.detail }

    var symbol: String {
        switch kind {
        case .badAPK: return "doc.badge.ellipsis"
        case .unsupportedCPU: return "cpu"
        case .missingSplits: return "square.stack.3d.up.slash"
        case .protected, .closedItself: return "lock.shield"
        case .needsGoogle: return "person.crop.circle.badge.exclamationmark"
        case .missingFeature, .missingFunction: return "puzzlepiece"
        case .javaCrash, .nativeCrash: return "exclamationmark.triangle.fill"
        case .noProgress: return "hourglass"
        }
    }

    // MARK: before a start

    /// Libraries of commercial app protectors: they check the device and the app's own files, and stop the app off a real phone.
    private static let protectorLibraries = ["libjiagu", "libDexHelper", "libsecexe", "libsecmain", "libprotectClass", "libdexprotector",
                                             "libapp_shield", "libNSaferOnly", "libshell-super", "libtup", "libAppGuard", "libxloader",
                                             "libarmour", "libnesec", "libSecShell", "libkwscmm", "libmobisec",
                                             // seen in Play apps: ByteDance's metasec (TikTok, CapCut), Netflix's, Akamai's bot manager
                                             // (eBay), and games whose own library refuses uncertified devices (Clash Royale, HCR2)
                                             "libmetasec", "libcf2a", "libakamaibap", "libakamaibmp", "libk30d", "libsupercell_", "libfingersoft_hcr2", "libfp"]

    static func preflight(_ app: TLApp) -> AppDiagnosis? {
        guard let r = app.report else { return nil }
        if !r.ok || r.verdict == "unreadable" {
            return AppDiagnosis(kind: .badAPK, title: "无法读取的 APK",
                                detail: "这个文件不是 Husk 能读取的应用" + (r.error.map { "：\($0)。" } ?? "。")
                                    + " 它可能已损坏、只下载了一部分，或者根本不是 Android 应用。",
                                evidence: r.error ?? r.summary)
        }
        if r.verdict == "noArm64" {
            return AppDiagnosis(kind: .unsupportedCPU, title: "不支持：CPU 指令集类型不符",
                                detail: r.summary + " iPhone 只能运行 64 位 ARM（arm64）代码。请寻找此应用的 arm64 或通用版本。",
                                evidence: "ABIs: " + r.abis.joined(separator: ", "))
        }
        if app.apks.count == 1, let base = app.apks.first, husk_apk_split_required(base) != 0 {
            return AppDiagnosis(kind: .missingSplits, title: "应用不完整",
                                detail: "此应用分为多个部分发布（拆分 APK），而只导入了基础包，因此缺少库或"
                                    + "资源。请导入完整捆绑包（.apks、.xapk 或 .apkm），或从 Husk 的商店获取。",
                                evidence: "manifest: split APKs required")
        }
        if let lib = r.libraries.first(where: { l in protectorLibraries.contains(where: { l.name.hasPrefix($0) }) }) {
            return AppDiagnosis(kind: .protected, title: "受保护的应用",
                                detail: "此应用带有防篡改保护（\(lib.name)）。这类保护会检查它是否运行在认证的"
                                    + "Android 手机上，否则就关闭应用，因此在 Husk 中可能无法启动。",
                                evidence: lib.name)
        }
        return nil
    }

    // MARK: after a run

    /// The reason a run stopped, from its log; nil when nothing in it explains the end (the app closed the normal way).
    static func fromLog(_ text: String) -> AppDiagnosis? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        // A native crash: the runtime's crash handler names the library the bad instruction was in
        if let i = lines.lastIndex(where: { $0.contains("=== CRASH:") || $0.contains("*** FATAL SIGNAL") }) {
            let head = lines[i]
            let lib = lines[(i + 1)..<min(lines.count, i + 4)].compactMap { l -> String? in
                guard l.contains("pc ") else { return nil }
                return l.split(separator: " ").map(String.init).first { $0.hasSuffix(".so") || $0.contains(".so") }
            }.first
            let signal = head.range(of: "signal \\d+", options: .regularExpression).map { String(head[$0]) } ?? "a fatal signal"
            if let lib, !lib.hasPrefix("libhusk"), !lib.contains("Husk") {
                return AppDiagnosis(kind: .nativeCrash, title: "在 \(lib) 中崩溃",
                                    detail: "应用自身的原生代码（\(lib)）以 \(signal) 终止。它很可能需要 Husk "
                                        + "目前尚未提供的某些 Android 功能，或者做了 iOS 不允许的事。",
                                    evidence: head)
            }
            return AppDiagnosis(kind: .nativeCrash, title: "应用崩溃了",
                                detail: "它以 \(signal) 终止。报告中包含那次运行的完整日志。", evidence: head)
        }

        // The app ended itself from native code: protection that found it is not on a certified phone, most of the time
        if let l = lines.last(where: { $0.contains("bionic: exit(") && $0.contains("called from") }),
           let code = l.range(of: "exit\\((\\d+)\\)", options: .regularExpression).map({ String(l[$0]) }), code != "exit(0)" {
            let lib = l.components(separatedBy: "called from ").last?.split(separator: " ").first.map(String.init) ?? "its code"
            return AppDiagnosis(kind: .closedItself, title: "应用拒绝在此运行",
                                detail: "\(lib) 主动关闭了应用（\(code)）。带防篡改或反作弊保护的应用在"
                                    + "发现不在认证的 Android 手机上时会这样做，而 Husk 无法为它们伪装成那样。",
                                evidence: l)
        }

        // Java: the exception that ended the app's main thread
        if let l = lines.last(where: { $0.contains("main thread ended with ") }) {
            let what = l.components(separatedBy: "main thread ended with ").last ?? l
            let name = String(what.prefix { $0 != ":" && $0 != " " })
            let short = name.split(separator: ".").last.map(String.init) ?? name
            let message = what.dropFirst(name.count).drop { $0 == ":" || $0 == " " }
            let firstPart = message.components(separatedBy: " | caused by").first ?? String(message)
            if ["NoSuchMethodError", "NoClassDefFoundError", "UnsatisfiedLinkError", "AbstractMethodError", "NoSuchFieldError",
                "IncompatibleClassChangeError"].contains(short) {
                return AppDiagnosis(kind: .missingFeature, title: "用到了 Husk 尚未支持的功能",
                                    detail: "此应用需要 Husk 运行时尚未提供的某部分 Android 功能：\(apiName(firstPart))。",
                                    evidence: l)
            }
            if what.localizedCaseInsensitiveContains("google play services") || what.contains("GooglePlayServices") {
                return googleDiagnosis(l)
            }
            return AppDiagnosis(kind: .javaCrash, title: "应用崩溃了",
                                detail: "其代码以 \(short) 终止" + (firstPart.isEmpty ? "。" : "：\(firstPart.prefix(220))"),
                                evidence: l)
        }

        // Google Play services the app will not run without
        if let l = lines.last(where: { $0.contains("requires Google Play services") || $0.contains("Failed to fetch kids onboarding status")
                                        || $0.contains("GooglePlayServicesNotAvailableException") }),
           lines.contains(where: { $0.contains("the app finished") }) {
            return googleDiagnosis(l)
        }

        // An app whose work is done by Linux programs it starts as processes of their own (Winlator's and GameNative's Box64 and Wine,
        // a proot userland): its own screens run, the programs can not, as an iOS app may not start processes
        if let l = lines.first(where: { $0.contains("the app started a process:") }),
           ["box64", "box86", "wine", "proot", "/usr/bin/", "imagefs", "rootfs", "termux", "ld-linux"].contains(where: { l.localizedCaseInsensitiveContains($0) }) {
            let prog = l.components(separatedBy: "the app started a process: ").last?.components(separatedBy: " -- ").first ?? "a program"
            return AppDiagnosis(kind: .missingFeature, title: "以独立进程运行 Linux 程序",
                                detail: "此应用的主要工作由它启动的独立进程中的 Linux 程序完成（此处为 \(prog.prefix(120))）。"
                                    + "它自己的界面能在 Husk 中运行，但 iOS 不允许应用启动其他进程，因此那些程序，以及"
                                    + "它们运行的游戏或工具，目前都无法启动。",
                                evidence: l)
        }

        // An app that only works signed in to a Google account: it asked Android's account picker, got none, and closed
        if let l = lines.last(where: { $0.contains("ChooseTypeAndAccountActivity") || $0.contains("AccountManager.newChooseAccountIntent") }),
           lines.contains(where: { $0.contains("the app finished") }) {
            return AppDiagnosis(kind: .needsGoogle, title: "需要 Google 账户",
                                detail: "此应用只有在登录 Google 账户后才能使用。它请求 Android 选择一个账户，而 Husk 没有可提供的"
                                    + "Google 账户，因此应用关闭了。",
                                evidence: l)
        }

        // A game whose data comes as an expansion file the store did not install
        if let l = lines.first(where: { $0.contains("expansion file (OBB) is missing") }) {
            return AppDiagnosis(kind: .missingSplits, title: "缺少游戏数据",
                                detail: "此游戏把大部分数据放在扩展文件（OBB）中，由 Play 商店单独"
                                    + "下载。Husk 安装了应用本身，但没有那个文件，因此游戏无法加载。",
                                evidence: l)
        }

        // Video that only plays with DRM keys
        if let l = lines.first(where: { $0.contains("Husk cannot decrypt protected media") }) {
            return AppDiagnosis(kind: .protected, title: "不支持受保护的视频",
                                detail: "此应用的视频受 DRM 保护（Widevine），只有认证的 Android 设备才能解密。"
                                    + "未受保护的视频可以播放；受保护的视频则一直是黑屏。",
                                evidence: l)
        }

        // A function of Android's C library or system libraries that was never written for Husk
        if let l = lines.first(where: { $0.contains("CALLED an unresolved import: ") }), lines.contains(where: { $0.contains("the app finished") || $0.contains("CRASH") }) {
            let fn = l.components(separatedBy: "unresolved import: ").last?.split(separator: " ").first.map(String.init) ?? "?"
            return AppDiagnosis(kind: .missingFunction, title: "用到了 Husk 尚未支持的功能",
                                detail: "此应用调用了 \(fn)，这是 Husk 尚未提供的系统函数。", evidence: l)
        }
        return nil
    }

    private static func googleDiagnosis(_ line: String) -> AppDiagnosis {
        AppDiagnosis(kind: .needsGoogle, title: "需要 Google Play 服务",
                     detail: "此应用对 Google Play 服务（Google 登录、Google 的账户与设备校验）的依赖超出了 Husk "
                        + "能够代答的范围。只使用 Google 库的应用可以运行；这个应用在没有真正服务时会停止。",
                     evidence: line)
    }

    /// "android/os/StrictMode$ThreadPolicy$Builder.penaltyListener(...)" as "StrictMode.ThreadPolicy.Builder.penaltyListener".
    private static func apiName(_ s: String) -> String {
        var t = s.components(separatedBy: "(").first ?? s
        t = t.replacingOccurrences(of: "No implementation found for ", with: "")
        t = t.replacingOccurrences(of: "$", with: ".")
        let parts = t.split(separator: "/").map(String.init)
        return (parts.count > 1 ? parts.suffix(2).joined(separator: ".") : t).trimmingCharacters(in: .whitespaces)
    }
}

/// A diagnosis, as a card: on an app's page before it starts, and over an app's screen when it stops.
struct AppDiagnosisCard: View {
    let diagnosis: AppDiagnosis
    var showsEvidence = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: diagnosis.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(diagnosis.blocksLaunch ? .red : .orange)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(diagnosis.title).font(.subheadline.weight(.semibold))
                Text(diagnosis.detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if showsEvidence, let e = diagnosis.evidence {
                    Text(e).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(4).textSelection(.enabled).padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Over an app's screen when its run ends with a reason: what happened, and the way out.
struct AppStoppedOverlay: View {
    let app: TLApp
    let diagnosis: AppDiagnosis
    let close: () -> Void
    @State private var report: URL?

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text(app.label).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                AppDiagnosisCard(diagnosis: diagnosis, showsEvidence: true)
                HStack(spacing: 10) {
                    if let report {
                        ShareLink(item: report) { Label("分享报告", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered)
                    }
                    Button(action: close) { Text("关闭").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(18)
            .frame(maxWidth: 440)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(24)
        }
        .task { report = AppDiagnosis.writeReport(app: app, diagnosis: diagnosis) }
    }
}

extension AppDiagnosis {
    /// The run that just ended, in one text file to share: the reason, the app, this device, and the runtime's log of the run.
    @MainActor static func writeReport(app: TLApp, diagnosis d: AppDiagnosis) -> URL? {
        let info = Bundle.main.infoDictionary ?? [:]
        var text = """
        Husk app report
        ===============
        App      : \(app.label) (\(app.packageName ?? "?"))
        What     : \(d.title)
        Why      : \(d.detail)
        Evidence : \(d.evidence ?? "-")
        Husk     : \(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))
        Device   : \(HuskLog.deviceModel), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        APKs     : \(app.apks.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))
        Engine   : \(app.report?.runnerName ?? "?")

        ---- log of the run ----

        """
        if let c = husk_tl_attempt_log() { text += String(cString: c); free(c) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Husk report - \(app.label.replacingOccurrences(of: "/", with: "-")).txt")
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { return nil }
        return url
    }

    /// When a run has ended: why, from its log (nil when it closed the normal way).
    static func ofCurrentRun() -> AppDiagnosis? {
        guard let c = husk_tl_attempt_log() else { return nil }
        defer { free(c) }
        return fromLog(String(cString: c))
    }
}
