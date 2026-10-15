import SwiftUI

struct LiveAdvicePanel: View {
    @ObservedObject var live: LiveAdviceModel
    @AppStorage("cloud.uploadAllowed") private var uploadAllowed = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    live.prepare()
                } label: {
                    Label(live.phase == .sampling ? "正在取样…" : "分析当前画面", systemImage: "sparkle.magnifyingglass")
                }.buttonStyle(.bordered).disabled(!live.canPrepare)
                if live.phase != .idle || live.cloudText != nil {
                    Button("停止") { live.cancel() }.buttonStyle(.bordered)
                }
            }
            if live.phase == .requesting {
                HStack { ProgressView(); Text("云端等待中，快门照常可用").font(.caption) }
            }
            if let advice = live.cloudText {
                VStack(alignment: .leading, spacing: 4) {
                    Text("云端 · \(live.cloudModel)").font(.caption).foregroundStyle(.yellow)
                    Text(advice).font(.callout).textSelection(.enabled)
                    Text("仅对应确认时的画面；请自行判断").font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(live.availabilityText).font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .onAppear { live.setUploadsAllowed(uploadAllowed); live.tick() }
        .onChange(of: uploadAllowed) { _, allowed in live.setUploadsAllowed(allowed) }
        .onReceive(ticker) { _ in live.tick() }
        .sheet(item: $live.confirmation, onDismiss: { live.dismissedConfirmation() }) { item in
            LiveUploadSheet(item: item, live: live)
        }
        .alert("云端分析状态", isPresented: Binding(get: { live.message != nil }, set: { if !$0 { live.message = nil } })) {
            Button("知道了") { live.message = nil }
        } message: { Text(live.message ?? "") }
    }
}

private struct LiveUploadSheet: View {
    let item: LiveUploadConfirmation
    @ObservedObject var live: LiveAdviceModel
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let image = UIImage(data: item.sample.jpeg) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 360)
                            .accessibilityLabel("即将上传的冻结取景缩略图")
                    }
                    Text("确认发送这张冻结预览？").font(.headline)
                    Text("接收方：\((try? CloudContract.endpoint(item.config.endpoint).host) ?? "无效端点")\n模型：\(item.config.model)")
                        .font(.callout).multilineTextAlignment(.center)
                    Text("只发送最长边1024px、无EXIF/GPS的缩略图；服务可能计费。若移动、换镜头、旋转或确认超时，将取消而不会改发另一张图。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("确认上传这一帧并请求建议") { live.confirm(item) }
                        .buttonStyle(.borderedProminent).disabled(live.phase != .confirming)
                    Button("取消，不上传", role: .cancel) { live.cancel() }
                }.padding()
            }.navigationTitle("上传前确认").navigationBarTitleDisplayMode(.inline)
        }.interactiveDismissDisabled(live.phase == .requesting)
    }
}
