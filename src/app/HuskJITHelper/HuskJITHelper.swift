// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import StikJIT

/// The debugger half of Built-in StikJIT (docs/06-built-in-jit.md).
///
/// A process cannot synchronously debug itself, so Husk starts this extension,
/// sends it its PID, the pairing file and husk-jit.js, and StikJIT attaches over
/// LocalDevVPN and services the script's trap requests until Husk detaches.
private enum HuskJITWork {
    /// One request at a time: enabling JIT holds this queue while the debugger is attached.
    static let queue = DispatchQueue(label: "com.husk.app.jit-helper")

    static func handle(_ request: HuskJITRequest) -> HuskJITRequest.Response {
        let manager = FileManager.default
        let root = manager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StikJIT", isDirectory: true)
        let paths = DDIPaths.default(in: root)

        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            if request.operation == .resetDDI {
                try StikJIT.resetCachedDDI(at: paths)
                return .init(success: true, message: "已重置开发者磁盘映像缓存。",
                             txmPresent: StikJIT.isTXMPresent)
            }
            seedBundledDDI(at: root, paths: paths, manager: manager)

            guard let pairingData = request.pairingData, !pairingData.isEmpty else {
                throw NSError(domain: "HuskJITHelper", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "未提供配对文件。"])
            }
            let pairingURL = root.appendingPathComponent("pairingFile-\(UUID().uuidString).plist")
            try pairingData.write(to: pairingURL, options: .atomic)
            defer { try? manager.removeItem(at: pairingURL) }

            switch request.operation {
            case .prepare:
                let readiness = StikJIT.prepareDevice(
                    pairingFile: pairingURL, paths: paths,
                    progress: { NSLog("[HuskJIT] prepare: %@", String(describing: $0)) })
                switch readiness {
                case .ready(let security):
                    return .init(success: true,
                                 message: "LocalDevVPN 可达，开发者磁盘映像已就绪。",
                                 txmPresent: security.isTXMPresent)
                case .unreachable(let reason), .preparationFailed(let reason):
                    return .init(success: false, message: reason, txmPresent: StikJIT.isTXMPresent)
                @unknown default:
                    return .init(success: false, message: "StikJIT 返回了未知的准备状态。",
                                 txmPresent: StikJIT.isTXMPresent)
                }
            case .enable:
                guard let targetPID = request.targetPID,
                      let scriptBase64 = request.scriptBase64, !scriptBase64.isEmpty else {
                    throw NSError(domain: "HuskJITHelper", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey:
                                    "未提供目标进程或 Husk 的 JIT 脚本。"])
                }
                try StikJIT.enableJIT(
                    targetPID: targetPID,
                    pairingFile: pairingURL,
                    ddiPaths: paths,
                    script: .customBase64(scriptBase64),
                    forceScript: true,
                    preparationProgress: { NSLog("[HuskJIT] prepare: %@", String(describing: $0)) },
                    progress: { NSLog("[HuskJIT] %@", $0) })
                return .init(success: true, message: "Husk 已从内置 JIT 助手干净地分离。",
                             txmPresent: StikJIT.isTXMPresent)
            case .resetDDI:
                preconditionFailure("Handled above")
            }
        } catch {
            return .init(success: false, message: error.localizedDescription,
                         txmPresent: StikJIT.isTXMPresent)
        }
    }

    /// Lays down the Developer Disk Image the helper mounts on its way to
    /// attaching.
    ///
    /// StikJIT fetches that image from GitHub itself, over the phone's own
    /// network, so a route that cannot reach github.com ends the first mount
    /// with "Failed to download Developer Disk Image: ...". The five files also
    /// ship in this extension's bundle (scripts/fetch_ddi.sh), and this seeds
    /// StikJIT's cache from them, so a fresh install mounts with no network
    /// involved at all.
    ///
    /// Once only, marked beside the cache. Reset Developer Disk Image still
    /// clears the cache, and because the marker survives, StikJIT then does
    /// what it always did and fetches the current image -- which is the point
    /// of that button after an iOS update. Reinstalling Husk seeds again.
    private static func seedBundledDDI(at root: URL, paths: DDIPaths, manager: FileManager) {
        let marker = root.deletingLastPathComponent()
            .appendingPathComponent("HuskBundledDDI.seeded")
        guard !manager.fileExists(atPath: marker.path) else { return }

        let wanted: [(String, String)] = [
            ("BuildManifest.plist", paths.manifestPath),
            ("Image.dmg", paths.imagePath),
            ("Image.dmg.cryptex_info", paths.cryptexInfoPath),
            ("Image.dmg.root_hash", paths.rootHashPath),
            ("Image.dmg.trustcache", paths.trustcachePath),
        ]

        // project.yml carries these as a folder reference, so the bundle keeps
        // the DDI/ level and the files arrive byte for byte.
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("DDI", isDirectory: true)
        var seeded = 0
        for (name, destination) in wanted {
            let source = bundled.appendingPathComponent(name)
            guard manager.fileExists(atPath: source.path) else { continue }
            let target = URL(fileURLWithPath: destination)
            try? manager.createDirectory(at: target.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
            try? manager.removeItem(at: target)
            if (try? manager.copyItem(at: source, to: target)) != nil { seeded += 1 }
        }

        guard seeded == wanted.count else {
            NSLog("[HuskJIT] bundled developer disk image incomplete: %d of %d",
                  seeded, wanted.count)
            return
        }
        manager.createFile(atPath: marker.path, contents: Data())
        NSLog("[HuskJIT] seeded the bundled developer disk image")
    }
}

/// NSExtensionPrincipalClass (Info.plist). The request arrives as JSON in the
/// first input item; the response goes back as JSON in the item the request
/// completes with. Enable completes only once Husk's script has detached, so
/// the request, and this process, last as long as the debugger does.
@objc(HuskJITHelperHandler)
final class HuskJITHelperHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let info = (context.inputItems.first as? NSExtensionItem)?.userInfo
        let data = info?[HuskJITRequest.itemKey] as? Data
        HuskJITWork.queue.async {
            let response: HuskJITRequest.Response
            if let data, let request = try? JSONDecoder().decode(HuskJITRequest.self, from: data) {
                response = HuskJITWork.handle(request)
            } else {
                response = .init(success: false, message: "Husk 的 JIT 助手未收到请求。",
                                 txmPresent: nil)
            }
            let item = NSExtensionItem()
            item.userInfo = [HuskJITRequest.Response.itemKey: (try? JSONEncoder().encode(response)) ?? Data()]
            context.completeRequest(returningItems: [item], completionHandler: nil)
        }
    }
}
