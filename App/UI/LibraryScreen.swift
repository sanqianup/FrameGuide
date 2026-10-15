import SwiftUI

struct LibraryScreen: View {
    @ObservedObject var model: CameraModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(model.records) { record in
                NavigationLink {
                    PhotoReviewScreen(record: record)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(record.created, format: .dateTime.year().month().day().hour().minute().second())
                        Text("原图 · \(record.filename.pathExtension.uppercased()) · 本机保存")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            }
            .overlay { if model.records.isEmpty { ContentUnavailableView("还没有照片", systemImage: "camera", description: Text("拍摄的原图会保存在这里")) } }
            .navigationTitle("本机照片")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.task { await model.loadRecords() }
    }
}

private extension String { var pathExtension: String { (self as NSString).pathExtension } }

struct PhotoReviewScreen: View {
    @StateObject private var model: PhotoReviewModel
    @State private var comparing = false
    @State private var showGenerated = false
    @State private var confirmation: RemoteKind?
    @AppStorage("cloud.uploadAllowed") private var uploadAllowed = false
    @Environment(\.scenePhase) private var phase
    init(record: PhotoRecord) { _model = StateObject(wrappedValue: PhotoReviewModel(record: record)) }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let image = comparing ? model.original : (showGenerated ? model.generatedPreview : model.preview) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 520)
                        .accessibilityLabel(comparing ? "原图" : (showGenerated ? "生成式编辑结果" : "本地调色预览"))
                } else { ProgressView().frame(height: 220) }
                Toggle("对比原图", isOn: $comparing)
                HStack {
                    Button("自然调色") { showGenerated = false; model.apply(.natural) }
                    Button("撤销") { showGenerated = false; model.undo() }.disabled(!model.canUndo)
                    Button("恢复原色") { showGenerated = false; model.apply(ToneRecipe()) }
                }.buttonStyle(.bordered).disabled(model.rendering || model.busy || model.original == nil)
                Text("本地调色仅调整曝光、饱和度、色温和对比度；编辑历史在本次页面有效，原图永久独立保存。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("原图存相册") { model.saveOriginal() }
                    Button("调色副本存相册") { model.saveColorCopy() }
                }.buttonStyle(.bordered).disabled(model.busy || model.rendering || model.original == nil)
                Divider()
                Text(model.advice).frame(maxWidth: .infinity, alignment: .leading)
                if model.busy { HStack { ProgressView(); Button("取消请求") { model.cancelRemote() } } }
                Button("向已配置模型请求看图建议") { confirmation = .vision }
                    .buttonStyle(.borderedProminent)
                    .disabled(!uploadAllowed || model.busy || model.rendering || model.original == nil)
                Text("\(cloudStatus(.vision))。每次手动确认后，仅发送最长边 1024px、已移除 EXIF 的此照片预览。")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("可选生成式编辑（可能改变细节）") {
                    VStack(spacing: 12) {
                        TextField("编辑要求", text: $model.editPrompt, axis: .vertical).textFieldStyle(.roundedBorder)
                        Button("发送到独立图像编辑服务") { confirmation = .editing }
                            .disabled(!uploadAllowed || model.busy || model.rendering || model.original == nil)
                        Text(cloudStatus(.editing)).font(.caption).foregroundStyle(.secondary)
                        if model.generatedPreview != nil {
                            Toggle("显示生成式结果", isOn: $showGenerated)
                            Button("生成式副本存相册") { model.saveGeneratedCopy() }.disabled(model.rendering || model.busy)
                        }
                    }.padding(.top)
                }
            }.padding()
        }.navigationTitle("照片与调色").navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onDisappear { model.close() }
        .onChange(of: phase) { _, value in if value != .active { model.cancelRemote() } }
        .onChange(of: uploadAllowed) { _, value in if !value { model.cancelRemote() } }
        .alert("上传此照片预览？", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
            Button("取消", role: .cancel) { confirmation = nil }
            Button("确认上传并请求") {
                if let kind = confirmation { model.request(kind, uploadAllowed: uploadAllowed) }
                confirmation = nil
            }
        } message: {
            let config = RemoteConfiguration.load(confirmation ?? .vision)
            Text("将发送给 \((try? CloudContract.endpoint(config.endpoint).host) ?? "未配置服务")，模型 \(config.model)。服务可能计费；原图不会上传。生成式编辑可能改变画面细节。")
        }
        .alert("处理状态", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("知道了") { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
    private func cloudStatus(_ kind: RemoteKind) -> String {
        guard uploadAllowed else { return "照片上传已关闭" }
        let config = RemoteConfiguration.load(kind)
        guard let url = try? config.validate(), SecretStore.hasKey(kind, endpoint: url) else { return "\(kind.title)不可用：请先在设置中配置并确认能力" }
        return "\(kind.title)：\(config.model) · 尚需实际请求验证"
    }
}
