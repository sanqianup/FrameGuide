import SwiftUI

struct SettingsScreen: View {
    @ObservedObject var motion: MotionMonitor
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @AppStorage("cloud.uploadAllowed") private var uploadAllowed = false
    var body: some View {
        NavigationStack {
            Form {
                Section("本机能力") {
                    Text("连续引导来自 Apple Vision 与构图规则，并非高级摄影师模型。无需训练、账号或联网。")
                    Text("原始 HEIC / JPEG 保存在 App 内，存入系统相册需单独允许添加权限。不读取既有相册。前置预览镜像，保存原图不镜像。")
                }
                Section("水平校准") {
                    Text("将手机竖起，以可靠的水平边缘为参照，保持稳定后校准；朝正上方或正下方时读数不可用。各屏幕方向分别校准。")
                    LevelIndicator(motion: motion)
                    Button("用当前姿态校准") { motion.calibrate() }.disabled(!motion.stable || motion.angle == nil)
                    Button("恢复此方向默认校准") { motion.resetCalibration() }
                }
                Section("照片上传控制") {
                    Toggle("允许手动请求云端服务", isOn: $uploadAllowed)
                    Text("默认关闭；开启后每次取景帧或照片请求仍需明确确认。连接测试也会访问所选服务，可能产生费用。不会逐帧上传，也不会后台自动重试。")
                    ForEach(RemoteKind.allCases) { kind in NavigationLink(kind.title) { RemoteSettingsScreen(kind: kind) } }
                }
                Section {
                    NavigationLink("性能与验收读数") { DiagnosticsScreen() }
                    Text("目标设备：iPhone 16 Pro / iOS 18.5。其他版本直到 iOS 27 仍需独立构建与真机验证。")
                }
            }.navigationTitle("设置")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.onAppear { motion.start() }.onDisappear { motion.stop() }
            .onChange(of: phase) { _, value in if value == .active { motion.start() } else { motion.stop() } }
    }
}

struct RemoteSettingsScreen: View {
    let kind: RemoteKind
    @State private var config: RemoteConfiguration
    @State private var key = ""
    @State private var message: String?
    @State private var confirmTest = false
    @State private var testing = false
    @State private var testTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var phase
    init(kind: RemoteKind) { self.kind = kind; _config = State(initialValue: RemoteConfiguration.load(kind)) }
    var body: some View {
        Form {
            Section("独立服务配置") {
                Toggle("启用此服务", isOn: $config.enabled)
                TextField("完整 HTTPS 请求端点", text: $config.endpoint).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("模型名", text: $config.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("鉴权头", selection: $config.auth) {
                    ForEach(KeyHeader.allCases, id: \.self) { Text($0.header).tag($0) }
                }
                Stepper("超时 \(Int(config.timeout)) 秒", value: $config.timeout, in: 5...90, step: 5)
                Toggle(kind == .vision ? "已核对模型支持 image_url 看图" : "已核对支持 multipart 图片编辑及 b64_json 返回", isOn: $config.capabilityConfirmed)
                if kind == .vision {
                    Button("填入小米官方 MiMo 模板") { config = .mimoOfficial }
                    Toggle("使用 MiMo JSON 与 thinking 扩展", isOn: $config.mimoOptions)
                    if config.mimoOptions { Toggle("关闭深度思考（优先响应速度）", isOn: $config.disableThinking) }
                    Text("默认模板尚未启用。MiMo 看图输出建议和调色参数，不直接生成修图图片。更换服务后请按其文档核对扩展参数。")
                } else { Text("此适配器仅支持明确兼容的 images/edits multipart 接口；不会把聊天端点当作修图服务。") }
            }
            Section("密钥仅保存到本机 Keychain") {
                SecureField("输入新密钥（留空保留已存密钥）", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("保存配置与本机密钥") {
                    do {
                        if config.enabled { _ = try config.validate() }
                        if !key.isEmpty {
                            let endpoint = try CloudContract.endpoint(config.endpoint)
                            try SecretStore.save(key, for: kind, endpoint: endpoint); key = ""
                        }
                        try config.save(kind); message = "配置已保存，尚未请求服务"
                    } catch { message = error.localizedDescription }
                }.disabled(testing)
                if kind == .vision {
                    Button(testing ? "连接测试中…" : "连接测试（不含照片）") { confirmTest = true }.disabled(testing)
                    Text("只验证文本请求能否响应，不等于已验证看图、JSON 参数质量或编辑能力。")
                } else { Text("没有通用的免费无照片编辑测试；本地可校验配置，真实调用需照片确认与服务费用授权。") }
                if testing { Button("取消测试") { testTask?.cancel() } }
            }
        }.navigationTitle(kind.title)
        .alert("访问配置的模型服务？", isPresented: $confirmTest) {
            Button("取消", role: .cancel) {}
            Button("确认测试（可能计费）") { test() }
        } message: { Text("向 \((try? CloudContract.endpoint(config.endpoint).host) ?? "无效端点") 发送一条无照片文本请求。请先保存配置与密钥。") }
        .alert("配置状态", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("知道了") { message = nil }
        } message: { Text(message ?? "") }
        .onDisappear { testTask?.cancel(); key = "" }
        .onChange(of: config) { _, _ in testTask?.cancel() }
        .onChange(of: phase) { _, value in if value != .active { testTask?.cancel(); key = "" } }
    }
    private func test() {
        testing = true
        let saved = config // exact endpoint/model shown in the confirmation dialog
        testTask = Task {
            defer { testing = false }
            do {
                let result = try await RemoteClient.shared.testVision(saved)
                if !Task.isCancelled { message = result }
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
        }
    }
}

struct DiagnosticsScreen: View {
    @ObservedObject private var metrics = PerformanceMonitor.shared
    var body: some View {
        Form {
            LabeledContent("预览实际显示帧率", value: "待 Instruments 真机测量")
            LabeledContent("视频分析回调帧率", value: text(metrics.deliveredFPS, unit: "fps"))
            LabeledContent("单帧 Vision 耗时", value: text(metrics.analysisMS, unit: "ms"))
            LabeledContent("本地引导采样间隔", value: text(metrics.guidanceIntervalMS, unit: "ms"))
            LabeledContent("最近云端端到端等待", value: text(metrics.cloudMS, unit: "ms"))
            LabeledContent("丢弃过时响应", value: "\(metrics.discardedResponses)")
            LabeledContent("热状态", value: metrics.heat)
            Text("回调帧率不能代表实际显示帧率。这里没有预填跑分。读数仅保留在本次运行内，不记录照片、密钥或请求正文。")
                .font(.caption)
        }.navigationTitle("性能读数")
    }
    private func text(_ value: Double?, unit: String) -> String { value.map { String(format: "%.1f %@", $0, unit) } ?? "未采样" }
}
