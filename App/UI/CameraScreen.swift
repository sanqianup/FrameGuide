import SwiftUI

struct CameraScreen: View {
    @StateObject private var model = CameraModel()
    @Environment(\.scenePhase) private var phase
    @State private var sheet: Destination?
    enum Destination: String, Identifiable { case library, settings; var id: String { rawValue } }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            Group {
                if landscape {
                    HStack(spacing: 0) { preview; ScrollView { controls }.frame(width: 260) }
                } else { VStack(spacing: 0) { preview; controls } }
            }.background(.black)
        }
        .sheet(item: $sheet, onDismiss: { if phase == .active { model.active(true) } }) { route in
            if route == .library { LibraryScreen(model: model) }
            else { SettingsScreen(motion: model.motion) }
        }
        .onChange(of: sheet) { _, value in if value != nil { model.active(false) } }
        .onChange(of: phase) { _, value in model.active(value == .active && sheet == nil) }
        .task { model.active(phase == .active && sheet == nil); await model.loadRecords() }
        .onDisappear { model.active(false) }
        .alert("取景", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("知道了") { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
    private var preview: some View {
        ZStack(alignment: .top) {
            CameraPreview(session: model.engine.session, mirrored: model.front, subject: model.analysis?.subject,
                onRotation: { angle, quarter in model.setRotation(angle, quarter: quarter) },
                onFocus: { model.engine.focus(at: $0) })
            VStack(spacing: 10) {
                HStack {
                    Text("取景").font(.headline)
                    Spacer()
                    Text("本机 Vision + 构图规则").font(.caption)
                }
                LevelIndicator(motion: model.motion)
                Spacer()
                VStack(spacing: 5) {
                    Text(model.analysis?.guidance.text ?? "稳住手机，观察主体")
                        .font(.headline).multilineTextAlignment(.center)
                    Text(model.analysis?.source ?? "分析在后台限频执行")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(12).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            }.padding().allowsHitTesting(false)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
    }
    private var controls: some View {
        VStack(spacing: 12) {
            Text(model.saving ? "正在保存原图…" : model.status).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.lenses) { lens in
                        Button(lens.title) { model.switchLens(lens.id) }
                            .buttonStyle(.bordered).tint(lens.id == model.selectedLens ? .yellow : .gray)
                            .disabled(!model.canCapture)
                    }
                }
            }.fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { sheet = .library } label: { Label("照片", systemImage: "photo.on.rectangle") }
                    .disabled(model.saving || model.hasUnsavedOriginal)
                Spacer(minLength: 8)
                Button { model.capture() } label: {
                    Circle().fill(model.canCapture ? .white : .gray).frame(width: 64, height: 64)
                        .padding(5).overlay(Circle().stroke(.white, lineWidth: 2))
                }.accessibilityLabel("拍摄并保留原图").disabled(!model.canCapture)
                Spacer(minLength: 8)
                Button { sheet = .settings } label: { Label("设置", systemImage: "slider.horizontal.3") }
            }.labelStyle(.iconOnly).font(.title2)
            if model.hasUnsavedOriginal { Button("重试保存原图") { model.retrySave() }.tint(.yellow) }
            if !model.ready && !model.saving {
                HStack {
                    Button("重试") { model.active(true) }
                    Button("系统设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }.font(.caption)
            }
            Text("HEIC / JPEG 原始文件 · 云端默认关闭").font(.caption2).foregroundStyle(.secondary)
            LiveAdvicePanel(live: model.live)
        }.padding().background(Color(white: 0.07))
    }
}

struct LevelIndicator: View {
    @ObservedObject var motion: MotionMonitor
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "level")
                .rotationEffect(.degrees(-(motion.angle ?? 0)))
                .foregroundStyle(abs(motion.angle ?? 90) < 1 ? .green : .white)
            Text(motion.angle.map { String(format: "%+.1f°", $0) } ?? "水平不可用")
                .monospacedDigit()
            Text(motion.available ? (motion.stable ? "稳定" : "移动中") : "姿态传感器不可用")
                .foregroundStyle(.secondary)
        }.font(.caption).padding(8).background(.black.opacity(0.6), in: Capsule())
    }
}
