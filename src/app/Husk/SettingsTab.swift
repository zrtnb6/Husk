// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// Settings, as the iOS Settings app lays them out: a card for the app up top, then groups of rows that each
/// push a page of their own. What belongs to the app, what belongs to the emulator, and what the thing is.
struct SettingsTab: View {
    @AppStorage(AppWindows.defaultKey) private var multitask = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { AboutSettings() } label: { appCard }
                }

                Section {
                    row(JITSettings(), "bolt.fill", .yellow, "JIT 与侧载", "StikJIT 已内置——推荐方式")
                } header: {
                    Text("JIT")
                } footer: {
                    Text("Android 和转译层游戏需要 JIT。内置于 Husk 的 StikJIT 无需电脑即可开启。")
                }

                Section("General") {
                    row(DiscoverView(), "sparkle.magnifyingglass", .mint, "发现", "在 F-Droid 等软件源中查找应用")
                    row(LibrarySettings(), "square.grid.2x2.fill", .blue, "库", "你的应用及其图标")
                    row(PerformanceSettings(), "speedometer", .orange, "性能", "渲染器、声音")
                    row(AppearanceSettings(), "paintbrush.fill", .pink, "外观", "浅色或深色、强调色、应用图标")
                }

                Section {
                    Toggle(isOn: $multitask) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("以窗口方式打开应用")
                                Text("应用运行时仍可使用 Husk").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        } icon: {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.purple.gradient)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Image(systemName: "macwindow.on.rectangle")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white)
                                }
                        }
                    }
                } header: {
                    Text("Multitasking")
                } footer: {
                    Text("应用和游戏会以窗口形式打开，可以移动、调整大小，并最小化到边缘的停靠栏，类似 LiveContainer 的多任务。"
                       + "每个应用都可以在自己的设置中覆盖此选项。")
                }

                Section("Emulator") {
                    row(InputSettings(), "hand.tap.fill", .indigo, "输入", "屏幕、触控、键盘")
                    row(NetworkSettings(), "globe", .green, "网络", "互联网与已保存的会话")
                    row(SavedMachineSettings(), "externaldrive.fill", .teal, "已保存的机器", "快照与自动保存")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
        }
    }

    private var appCard: some View {
        HStack(spacing: 14) {
            HuskMark(size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("Husk").font(.title3.weight(.semibold))
                Text("版本 \(Bundle.main.version) · \(Bundle.main.commit)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func row<D: View>(_ destination: D, _ icon: String, _ tint: Color,
                              _ title: String, _ subtitle: String) -> some View {
        NavigationLink { destination } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } icon: {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.gradient)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                    }
            }
        }
    }
}

/// A Form, as the system draws one.
private struct HuskForm: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    func huskForm() -> some View { modifier(HuskForm()) }
}

// MARK: - Library

struct LibrarySettings: View {
    @ObservedObject private var host = AndroidHost.shared
    @State private var working = false

    var body: some View {
        Form {
            Section {
                DetailRow(label: "Apps", value: "\(host.packages.count)", mono: false)
                DetailRow(label: "With icons",
                          value: "\(host.packages.filter { $0.iconPath != nil }.count)",
                          mono: false)
            } footer: {
                Text("列表会写入磁盘，因此在 Android 启动完成之前"
                   + "就已经显示在屏幕上。")
            }

            Section {
                Button {
                    working = true
                    Task { await host.refreshPackages(); working = false }
                } label: {
                    Label(working ? "正在刷新…" : "从 Android 刷新",
                          systemImage: "arrow.clockwise")
                }
                .disabled(working || !host.isReady)

                Button {
                    AndroidHost.forgetIcons()
                    working = true
                    Task { await host.refreshPackages(); working = false }
                } label: {
                    Label("重新获取图标", systemImage: "photo.on.rectangle")
                }
                .disabled(working || !host.isReady)
            } footer: {
                Text("名称和图标来自 Android 自带的启动器，它会保留"
                   + "自己绘制的那一份。重新获取会丢弃 Husk 的副本，并"
                   + "再次向其索取。")
            }
        }
        .huskForm()
        .navigationTitle("Library")
    }
}

// MARK: - Performance

struct PerformanceSettings: View {
    @ObservedObject private var runner = QemuRunner.shared
    @State private var gpuMode =
        UserDefaults.standard.object(forKey: "husk.gpuMode") as? Bool ?? true
    @State private var sound = UserDefaults.standard.bool(forKey: "husk.sound")
    @State private var soundDevice =
        UserDefaults.standard.object(forKey: "husk.soundDevice") as? Bool ?? true

    var body: some View {
        Form {
            Section {
                Picker("Renderer", selection: $gpuMode) {
                    Text("GPU").tag(true)
                    Text("CPU").tag(false)
                }
                .pickerStyle(.segmented)
                .onChange(of: gpuMode) { v in
                    UserDefaults.standard.set(v, forKey: "husk.gpuMode")
                    HuskLog.log("ui", v ? "GPU renderer selected" : "CPU renderer selected")
                }
            } header: {
                Text("Renderer")
            } footer: {
                Text(gpuMode
                     ? "Android 通过 Metal 在真实 GPU 上绘制——帧率约为四倍。"
                     + "这是默认选项。"
                     : "每个像素都由模拟的 CPU 绘制。慢得多，只有"
                     + "在 GPU 出问题时才值得选择。")
            }

            Section {
                DetailRow(label: "Frame rate",
                          value: runner.fps > 0
                                 ? String(format: "%.0f fps", runner.fps) : "—")
                DetailRow(label: "Guest screen",
                          value: "\(QemuRunner.lastGuestRes.w)×\(QemuRunner.lastGuestRes.h)")
            } header: {
                Text("Now")
            }

            Section {
                Toggle("Sound", isOn: $sound)
                    .onChange(of: sound) { v in
                        UserDefaults.standard.set(v, forKey: "husk.sound")
                        HuskLog.log("ui", v ? "sound on" : "sound off")
                    }
                if sound {
                    Toggle("附加声音设备", isOn: $soundDevice)
                        .onChange(of: soundDevice) { v in
                            UserDefaults.standard.set(v, forKey: "husk.soundDevice")
                        }
                }
            } header: {
                Text("Sound")
            } footer: {
                Text("会添加一个声音设备。附加期间无法保存 Android——QEMU 拒绝为带声音设备的机器创建快照——因此每次"
                   + "启动都必须冷启动。无论开启还是关闭，都需要一次冷启动。")
            }
        }
        .huskForm()
        .navigationTitle("Performance")
    }
}

// MARK: - Input

struct InputSettings: View {
    @State private var landscapeGuest =
        UserDefaults.standard.bool(forKey: "husk.landscapeGuest")
    @State private var customRes = UserDefaults.standard.bool(forKey: "husk.customRes")
    @State private var widthText = InputSettings.stored("husk.resWidth", 720)
    @State private var heightText = InputSettings.stored("husk.resHeight", 1280)

    /// Sizes worth offering without typing. Deliberately short: these are the
    /// shapes a phone guest is actually run at, not a catalogue of every panel
    /// ever made.
    private static let presets: [(name: String, w: Int, h: Int)] = [
        ("Small — 360 × 800", 360, 800),
        ("HD — 720 × 1280", 720, 1280),
        ("Full HD — 1080 × 1920", 1080, 1920),
        ("Landscape HD — 1280 × 720", 1280, 720),
        ("Tablet — 1280 × 800", 1280, 800),
    ]

    private static func stored(_ key: String, _ fallback: Int) -> String {
        let v = UserDefaults.standard.integer(forKey: key)
        return String(v > 0 ? v : fallback)
    }

    /// What the typed numbers actually come to, or nothing if they are not a
    /// size the guest can be given.
    private var effective: (w: Int, h: Int)? {
        QemuRunner.validResolution(w: Int(widthText) ?? 0, h: Int(heightText) ?? 0)
    }

    var body: some View {
        Form {
            Section {
                Picker("Screen", selection: $landscapeGuest) {
                    Text("Portrait").tag(false)
                    Text("Landscape").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(customRes)
                .onChange(of: landscapeGuest) { v in
                    UserDefaults.standard.set(v, forKey: "husk.landscapeGuest")
                    HuskLog.log("ui", v ? "guest panel will be landscape"
                                        : "guest panel will be portrait")
                }
            } header: {
                Text("Screen")
            } footer: {
                Text(customRes
                     ? "自定义分辨率会直接决定屏幕形状，因此开启时本选项不起作用。"
                     + "横屏请填写较宽的尺寸。"
                     : "Android 在运行后无法改变屏幕形状，因此竖屏上运行横屏游戏会被压入"
                     + "一条黑边、显得很小。只有一开始就以横屏创建，游戏才能填满屏幕——竖屏应用则会被加上黑边。"
                     + "需要一次冷启动。")
            }

            Section {
                Toggle("自定义分辨率", isOn: $customRes)
                    .onChange(of: customRes) { v in
                        UserDefaults.standard.set(v, forKey: "husk.customRes")
                        store()
                        HuskLog.log("ui", v ? "custom resolution on: "
                                            + "\(widthText)x\(heightText)"
                                            : "custom resolution off")
                    }

                if customRes {
                    Picker("Preset", selection: Binding(
                        get: { presetIndex },
                        set: { i in
                            guard i >= 0, i < Self.presets.count else { return }
                            widthText = String(Self.presets[i].w)
                            heightText = String(Self.presets[i].h)
                            store()
                        })) {
                        ForEach(0..<Self.presets.count, id: \.self) { i in
                            Text(Self.presets[i].name).tag(i)
                        }
                        Text("Custom").tag(-1)
                    }

                    HStack {
                        Text("Width")
                        Spacer()
                        TextField("720", text: $widthText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.technical())
                            .frame(width: 90)
                            .onChange(of: widthText) { _ in store() }
                    }
                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("1280", text: $heightText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.technical())
                            .frame(width: 90)
                            .onChange(of: heightText) { _ in store() }
                    }

                    if let size = effective {
                        DetailRow(label: "Android will get",
                                  value: "\(size.w) × \(size.h)")
                    } else {
                        Text("宽高都必须在 240 到 2560 之间。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                DetailRow(label: "Running now", value: running)
            } header: {
                Text("Resolution")
            } footer: {
                Text("显示面板在机器启动时构建，因此修改需要"
                   + "一次冷启动，而下一次保存会替换以"
                   + "旧尺寸保存的机器——改回来还需要一次。尺寸会取整"
                   + "到 8 的倍数。越大越慢：每个像素都由模拟的手机绘制。"
                   + "Android 的显示密度不随面板变化，"
                   + "因此更大的面板是显示更多内容，而不是把内容放大。")
            }

            Section {
                Text("触控始终开启。键盘和旋转控件位于"
                   + "访客屏幕底部的药丸区域；手柄"
                   + "和指针目前尚未接入。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("Controls")
            }
        }
        .huskForm()
        .navigationTitle("Input")
    }

    /// The panel the guest actually has, which only means anything while there
    /// is a guest: the stored value is last launch's until one starts.
    private var running: String {
        guard QemuRunner.shared.isRunning else { return "not started" }
        return "\(QemuRunner.lastGuestRes.w) × \(QemuRunner.lastGuestRes.h)"
    }

    /// Which preset the typed numbers are, if any.
    private var presetIndex: Int {
        guard let size = effective else { return -1 }
        return Self.presets.firstIndex { $0.w == size.w && $0.h == size.h } ?? -1
    }

    private func store() {
        UserDefaults.standard.set(Int(widthText) ?? 0, forKey: "husk.resWidth")
        UserDefaults.standard.set(Int(heightText) ?? 0, forKey: "husk.resHeight")
    }
}

// MARK: - Network

struct NetworkSettings: View {
    @State private var keepNetwork =
        UserDefaults.standard.object(forKey: "husk.keepNetwork") as? Bool ?? true

    var body: some View {
        Form {
            Section {
                Toggle("保存后保留网络", isOn: $keepNetwork)
                    .onChange(of: keepNetwork) { v in
                        UserDefaults.standard.set(v, forKey: "husk.keepNetwork")
                    }
            } footer: {
                Text(keepNetwork
                     ? "保存会关闭应用，但让 Android 框架继续运行，"
                     + "因此恢复后网络仍然可用。"
                     : "保存也会停止框架。会清除所有 GPU 资源，"
                     + "更稳定——但网络可能要到"
                     + "冷启动后才恢复。")
            }

            Section {
                Text("Android 通过 QEMU 自有网络上的虚拟网卡"
                   + "访问互联网。你手机所在网络中的设备看不到"
                   + "访客，访客也看不到它们。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("连接方式")
            }
        }
        .huskForm()
        .navigationTitle("Network")
    }
}

// MARK: - JIT and sideloading

struct JITSettings: View {
    @ObservedObject private var runner = QemuRunner.shared
    @ObservedObject private var jit = JITCoordinator.shared
    @State private var autoStart = Onboarding.autoStart
    @AppStorage(JITCoordinator.autoEnableKey) private var autoJIT = false
    @State private var keepAttached = JITBootstrap.keepDebuggerAttached

    private var pairingLabel: String {
        switch jit.pairingSource {
        case .onDevice: return "paired on this device"
        case .imported: return "file imported"
        case nil: return "not set up"
        }
    }

    var body: some View {
        Form {
            Section {
                JITCard()
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section {
                Picker("Method", selection: $jit.method) {
                    ForEach(JITMethod.allCases) { Text($0.title).tag($0) }
                }
                DetailRow(label: "StikDebug",
                          value: JITBootstrap.isStikDebugInstalled ? "installed" : "not found", mono: false)
                DetailRow(label: "TrollStore",
                          value: JITBootstrap.isTrollStoreInstalled ? "installed" : "not found", mono: false)
                DetailRow(label: "Installed with TrollStore",
                          value: JITBootstrap.isInstalledWithTrollStore ? "yes" : "no", mono: false)
                DetailRow(label: "Jailbreak",
                          value: JITBootstrap.debuggedAtLaunch ? "JIT allowed for apps"
                               : JITBootstrap.isJailbroken ? "found" : "not found", mono: false)
                DetailRow(label: "Built-in pairing", value: pairingLabel, mono: false)
                Button {
                    jit.showSetup = true
                } label: {
                    Label("配置 JIT", systemImage: "wand.and.stars")
                }
            } header: {
                Text("其他开启 JIT 的方式")
            } footer: {
                Text(jit.method == .automatic
                     ? jit.automaticDescription + " 内置 StikJIT 需要 iOS 26、LocalDevVPN，以及一个"
                       + "配对文件；在 iOS 27 上 Husk 可以自行生成。"
                     : HuskBuiltInJIT.unavailableReason ?? "内置 StikJIT 需要 LocalDevVPN 和一个配对"
                       + "文件；在 iOS 27 上 Husk 可以自行生成。")
            }

            Section {
                DetailRow(label: "Debugger",
                          value: JITBootstrap.isDebuggerAttached ? "attached" : "not attached",
                          mono: false)
                DetailRow(label: "Executable memory",
                          value: JITBootstrap.isLive ? "granted" : "not claimed", mono: false)
                // The two routes, named separately. Either one is enough, and
                // when someone reports "JIT does not work" these two rows are
                // the whole diagnosis.
                DetailRow(label: "Trap servicer",
                          value: husk_ios_jit_self_route() != nil ? "not needed"
                               : JITBootstrap.prewarmed ? "answering" : "not answering",
                          mono: false)
                if let route = husk_ios_jit_self_route() {
                    DetailRow(label: "Made by Husk",
                              value: String(cString: route) == "MAP_JIT" ? "MAP_JIT (TrollStore entitlement)" : "plain memory (debugged or jailbroken)",
                              mono: false)
                }
                // Cached answer only: running the probe from a view body
                // could freeze the app (see JITBootstrap.mapJITWorks).
                DetailRow(label: "MAP_JIT",
                          value: JITBootstrap.deviceEnforcesTXM ? "not used (TXM)"
                               : JITBootstrap.mapJITResult.map { $0 ? "executes" : "refused" }
                                 ?? "not tested",
                          mono: false)
                DetailRow(label: "Debugger after setup",
                          value: JITBootstrap.detached ? "detached" : "attached",
                          mono: false)
                if let why = JITBootstrap.lastFailure {
                    Text(why).font(.caption).foregroundStyle(.orange)
                }
                if !JITBootstrap.ready {
                    Button {
                        jit.enable()
                    } label: {
                        Label("使用 \(jit.resolvedMethod.title) 启用 JIT", systemImage: "bolt.fill")
                    }
                    .disabled(jit.busy)
                    Button {
                        _ = JITBootstrap.requestTrollStoreAttach()
                    } label: {
                        Label("使用 TrollStore 启用 JIT", systemImage: "sparkles")
                    }
                }
            } header: {
                Text("JIT")
            } footer: {
                Text("Husk 需要既可写又可执行的内存，而在 iOS 上这需要"
                   + "已附加的调试器。获得方式有两种：一种是"
                   + "处理陷阱请求的调试器，另一种是 MAP_JIT 映射，"
                   + "内核允许任何被调试的进程使用它。任一方式都"
                   + "可行——具体可用哪种取决于设备与 iOS "
                   + "版本，因此 Husk 会实际测试两者，而不是臆断。")
            }

            Section {
                Toggle("启动时开启 JIT", isOn: $autoJIT)
                    .disabled(!HuskBuiltInJIT.isAvailable)
            } footer: {
                Text(HuskBuiltInJIT.isAvailable
                     ? "每次 Husk 在未开启 JIT 的情况下打开时，都会请求内置的 StikJIT 开启它，因此游戏无需"
                       + "点按即可运行。需要先完成一次 StikJIT 配置（配对）。"
                     : "需要内置 StikJIT，它在 iOS 26 及更高版本上可用。")
            }

            Section {
                Toggle("启动时启动 Android", isOn: $autoStart)
                    .onChange(of: autoStart) { v in
                        UserDefaults.standard.set(v, forKey: "husk.autoStart")
                    }
            } footer: {
                Text("在 JIT 可用时，Husk 一打开就启动访客系统。")
            }

            Section {
                Toggle("保持调试器附加", isOn: $keepAttached)
                    .onChange(of: keepAttached) { v in JITBootstrap.keepDebuggerAttached = v }
            } footer: {
                Text("默认关闭。一旦 JIT 区域建立，Husk 就会脱离 StikDebug，"
                   + "因为被 iOS 挂起的调试器会在下次需要时"
                   + "拖住整个应用。仅在需要收集 StikDebug 自身日志时"
                   + "才开启。")
            }

            Section {
                Text("APK 从「库」的 + 按钮或「文件」标签页安装。"
                   + "拆分安装包——基础 APK 加上其配置分片——必须一起"
                   + "选择；只安装基础包会因缺少原生"
                   + "库而失败。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("Sideloading")
            }
        }
        .huskForm()
        .navigationTitle("JIT 与侧载")
    }
}

// MARK: - Saved machine

struct SavedMachineSettings: View {
    @ObservedObject private var runner = QemuRunner.shared
    @State private var autoSave =
        UserDefaults.standard.object(forKey: "husk.autoSave") as? Bool ?? true
    @State private var useSnapshot =
        UserDefaults.standard.object(forKey: "husk.downloadSnapshot") as? Bool ?? true
    @State private var askWhichToDelete = false
    @State private var deleteResult: String?
    @AppStorage(GuestImage.askUpdatesKey) private var askUpdates = true

    var body: some View {
        Form {
            Section {
                Toggle("自动保存", isOn: $autoSave)
                    .onChange(of: autoSave) { v in
                        UserDefaults.standard.set(v, forKey: "husk.autoSave")
                        HuskLog.log("ui", v ? "automatic saving on" : "automatic saving off")
                    }
                Button {
                    QemuRunner.shared.saveState(reason: "asked from settings")
                } label: {
                    Label(runner.isSavingState ? "正在保存…" : "立即保存",
                          systemImage: "externaldrive.badge.checkmark")
                }
                .disabled(runner.isSavingState)
            } footer: {
                Text("Husk 会恢复已保存的机器而不是重新开机，只需"
                   + "数秒而非数分钟。写入期间画面会冻结。"
                   + "关闭此项后，不会自动保存任何内容——包括安装"
                   + "之后。")
            }

            Section {
                Button(role: .destructive) { askWhichToDelete = true } label: {
                    Label("删除已保存的机器", systemImage: "trash")
                }
                .disabled(!QemuRunner.shared.hasSnapshot)
                if let deleteResult {
                    Text(deleteResult).font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text(QemuRunner.shared.hasSnapshot
                     ? "当前已保存："
                     + ((QemuRunner.shared.snapshotDisplay ?? "sw").contains("gl")
                        ? "GPU" : "软件") + "。"
                     : "尚未保存任何内容，Android 将冷启动。")
            }

            Section {
                Toggle("下载预启动快照", isOn: $useSnapshot)
                    .onChange(of: useSnapshot) { v in
                        UserDefaults.standard.set(v, forKey: "husk.downloadSnapshot")
                    }
            } footer: {
                Text("会让首次下载增加约 2 GB。它是在"
                   + "软件渲染器上截取的，因此在 GPU 模式下不会使用——GPU 模式会冷启动"
                   + "一次，然后保存自己的快照。")
            }

            Section {
                Toggle("询问 Android 更新", isOn: $askUpdates)
            } footer: {
                Text("当发布新的 Android 镜像或快照时，Husk 会询问一次是否下载。"
                   + "在 Android 下载完成之前不会询问。")
            }
        }
        .huskForm()
        .navigationTitle("已保存的机器")
        .confirmationDialog("要删除哪一个？", isPresented: $askWhichToDelete,
                            titleVisibility: .visible) {
            Button("GPU 机器", role: .destructive) { forget("gl", "GPU") }
            Button("软件机器", role: .destructive) { forget("sw", "software") }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Android 会冷启动一次，然后保存一份新的。")
        }
    }

    private func forget(_ mode: String, _ name: String) {
        if QemuRunner.shared.forgetSnapshot(mode: mode) {
            deleteResult = "Deleted the \(name) machine. The next launch boots from cold."
        } else {
            deleteResult = "No \(name) machine is saved, so nothing was deleted."
        }
    }
}

// MARK: - Appearance

struct AppearanceSettings: View {
    @State private var appIcon = HuskAppIcon.current
    @AppStorage(Theme.Appearance.key) private var appearance = Theme.Appearance.system
    @ObservedObject private var theme = AppTheme.shared
    @Environment(\.colorScheme) private var scheme
    @State private var custom: Color = AppTheme.shared.accentColor

    private let iconColumns = [GridItem(.adaptive(minimum: 92), spacing: 14)]

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Theme.Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { v in
                    HuskLog.log("ui", "appearance: \(v.rawValue)")
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("随手机系统变化：白天浅色，夜间深色。访客自己的"
                   + "屏幕始终是深色的——它只是另一台手机的画面。")
            }

            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                    ForEach(AppTheme.presets) { preset in
                        Button {
                            theme.accentColor = preset.color
                            custom = preset.color
                        } label: {
                            swatch(preset.color, selected: preset.color.themeHex == theme.accentColor.themeHex)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.name)
                    }
                }
                .padding(.vertical, 6)

                ColorPicker("Custom Colour", selection: $custom, supportsOpacity: false)
                    .onChange(of: custom) { theme.accentColor = $0 }
            } header: {
                Text("强调色")
            } footer: {
                Text("为整个应用中的按钮、开关和选中状态着色。")
            }

            Section {
                LazyVGrid(columns: iconColumns, spacing: 14) {
                    ForEach(HuskAppIcon.allCases) { icon in
                        Button {
                            appIcon = icon
                            HuskAppIcon.apply(icon)
                        } label: {
                            VStack(spacing: 8) {
                                if let art = icon.preview(dark: scheme == .dark) {
                                    Image(uiImage: art)
                                        .resizable().scaledToFit()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(appIcon == icon ? Color.accentColor : .clear, lineWidth: 3))
                                }
                                Text(icon.title)
                                    .font(.caption)
                                    .foregroundStyle(appIcon == icon ? Color.accentColor : .primary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("应用图标")
            } footer: {
                Text("「自动」会跟随系统外观——浅色、深色和色调模式。其他选项则固定 "
                   + "一种样式。更改后 iOS 会显示自己的确认提示，该提示无法关闭。")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func swatch(_ color: Color, selected: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 34, height: 34)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.9), lineWidth: selected ? 2 : 0).padding(-4))
            .overlay {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(color.isLight ? .black : .white)
                }
            }
            .frame(maxWidth: .infinity)
    }
}

// MARK: - About

struct AboutSettings: View {
    @ObservedObject private var runner = QemuRunner.shared
    @State private var showLogs = false
    @AppStorage(TranslationLayer.devInfoKey) private var devInfo = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    HuskMark(size: 84)
                    Text("Husk").font(.title2.weight(.semibold))
                    Text("版本 \(Bundle.main.version)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("Build", value: Bundle.main.commit)
                LabeledContent("访客镜像", value: GuestImage.imageVersion)
                LabeledContent("渲染器",
                               value: runner.displayKind == .gl ? "GPU"
                                    : runner.displayKind == .software ? "CPU"
                                    : "未启动")
            }

            Section {
                Toggle(isOn: $devInfo) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("开发者信息")
                        Text("Android 转译层各界面中的技术细节："
                           + "库报告、设备检查和运行日志。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if devInfo {
                    NavigationLink { TLChecksView() } label: {
                        Label("设备检查", systemImage: "stethoscope")
                    }
                }
                Button { showLogs = true } label: {
                    Label("打开控制台", systemImage: "terminal")
                }
            } footer: {
                Text("Husk 在你的 iPhone 上以真实的 Android 系统运行未经修改的 APK。"
                   + "控制台会显示 Husk 的实时日志、访客的串口输出以及 QEMU 自身的"
                   + "输出——排查任何问题都要依赖这三个文件。")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLogs) { LogView() }
    }
}

extension Bundle {
    var version: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }
    var commit: String {
        (infoDictionary?["HuskBuildCommit"] as? String) ?? "?"
    }
}
