import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool
    let subject: Subject?
    let guided: GuidedSnapshot?
    let selecting: Bool
    let onRotation: (CGFloat, Int) -> Void
    let onFocus: (CGPoint) -> Void
    let onSelect: (CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        view.onRotation = onRotation; view.onFocus = onFocus
        view.onSelect = onSelect
        return view
    }
    func updateUIView(_ view: PreviewView, context: Context) {
        view.mirrored = mirrored; view.subject = subject
        view.guided = guided; view.selecting = selecting
        view.setNeedsLayout()
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var mirrored = false
    var subject: Subject?
    var guided: GuidedSnapshot?
    var selecting = false
    var onRotation: ((CGFloat, Int) -> Void)?
    var onFocus: ((CGPoint) -> Void)?
    var onSelect: ((CGPoint) -> Void)?
    private let box = CAShapeLayer()
    private let grid = CAShapeLayer()
    private let target = CAShapeLayer()
    private var lastAngle: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        preview.videoGravity = .resizeAspect // entire sensor frame, no misleading crop overlay
        backgroundColor = .black
        box.fillColor = UIColor.clear.cgColor; box.strokeColor = UIColor.systemYellow.cgColor
        box.lineWidth = 1.5
        grid.fillColor = UIColor.clear.cgColor; grid.strokeColor = UIColor.white.withAlphaComponent(0.22).cgColor
        grid.lineWidth = 0.5
        target.fillColor = UIColor.clear.cgColor; target.strokeColor = UIColor.systemCyan.cgColor
        target.lineWidth = 2; target.lineDashPattern = [6, 4]
        layer.addSublayer(grid); layer.addSublayer(target); layer.addSublayer(box)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        isAccessibilityElement = true; accessibilityLabel = "相机取景，轻点对焦"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layoutSubviews() {
        super.layoutSubviews()
        let orientation = window?.windowScene?.interfaceOrientation ?? .portrait
        let angle: CGFloat
        let quarter: Int
        switch orientation {
        case .landscapeLeft: angle = 0; quarter = 1
        case .landscapeRight: angle = 180; quarter = 3
        case .portraitUpsideDown: angle = 270; quarter = 2
        default: angle = 90; quarter = 0
        }
        if let c = preview.connection {
            if c.isVideoRotationAngleSupported(angle) { c.videoRotationAngle = angle }
            if c.isVideoMirroringSupported {
                c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = mirrored
            }
        }
        if angle != lastAngle { lastAngle = angle; onRotation?(angle, quarter) }
        // AVFoundation converts normalized unmirrored metadata coordinates into layer coordinates.
        let imageRect = preview.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        let path = UIBezierPath()
        for fraction in [CGFloat(1.0 / 3), CGFloat(2.0 / 3)] {
            path.move(to: CGPoint(x: imageRect.minX + imageRect.width * fraction, y: imageRect.minY))
            path.addLine(to: CGPoint(x: imageRect.minX + imageRect.width * fraction, y: imageRect.maxY))
            path.move(to: CGPoint(x: imageRect.minX, y: imageRect.minY + imageRect.height * fraction))
            path.addLine(to: CGPoint(x: imageRect.maxX, y: imageRect.minY + imageRect.height * fraction))
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        grid.path = path.cgPath
        if let guided {
            let t = guided.target
            let rect = CGRect(x: imageRect.minX + t.x * imageRect.width, y: imageRect.minY + t.y * imageRect.height,
                              width: t.width * imageRect.width, height: t.height * imageRect.height)
            target.path = UIBezierPath(roundedRect: rect, cornerRadius: 14).cgPath
            target.strokeColor = (guided.aligned ? UIColor.systemGreen : UIColor.systemCyan).cgColor
            target.lineDashPattern = guided.aligned ? nil : [6, 4]
        } else { target.path = nil }
        if let s = subject, s.isValid {
            // Vision coordinates refer to the physically rotated, displayed image.
            let rect = CGRect(x: imageRect.minX + s.x * imageRect.width, y: imageRect.minY + s.y * imageRect.height,
                              width: s.width * imageRect.width, height: s.height * imageRect.height)
            box.path = UIBezierPath(roundedRect: rect, cornerRadius: 8).cgPath
        } else { box.path = nil }
        CATransaction.commit()
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        let imageRect = preview.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard imageRect.width > 0, imageRect.height > 0, imageRect.contains(point) else { return }
        onFocus?(preview.captureDevicePointConverted(fromLayerPoint: point))
        if selecting {
            onSelect?(CGPoint(x: (point.x - imageRect.minX) / imageRect.width,
                              y: (point.y - imageRect.minY) / imageRect.height))
        }
    }
}
