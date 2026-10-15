import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool
    let subject: Subject?
    let onRotation: (CGFloat, Int) -> Void
    let onFocus: (CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        view.onRotation = onRotation; view.onFocus = onFocus
        return view
    }
    func updateUIView(_ view: PreviewView, context: Context) {
        view.mirrored = mirrored; view.subject = subject
        view.setNeedsLayout()
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var mirrored = false
    var subject: Subject?
    var onRotation: ((CGFloat, Int) -> Void)?
    var onFocus: ((CGPoint) -> Void)?
    private let box = CAShapeLayer()
    private let grid = CAShapeLayer()
    private var lastAngle: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        preview.videoGravity = .resizeAspect // entire sensor frame, no misleading crop overlay
        backgroundColor = .black
        box.fillColor = UIColor.clear.cgColor; box.strokeColor = UIColor.systemYellow.cgColor
        box.lineWidth = 1.5
        grid.fillColor = UIColor.clear.cgColor; grid.strokeColor = UIColor.white.withAlphaComponent(0.22).cgColor
        grid.lineWidth = 0.5
        layer.addSublayer(grid); layer.addSublayer(box)
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
        if let s = subject, s.isValid {
            // Vision coordinates refer to the physically rotated, displayed image.
            let rect = CGRect(x: imageRect.minX + s.x * imageRect.width, y: imageRect.minY + s.y * imageRect.height,
                              width: s.width * imageRect.width, height: s.height * imageRect.height)
            box.path = UIBezierPath(roundedRect: rect, cornerRadius: 8).cgPath
        } else { box.path = nil }
        CATransaction.commit()
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        onFocus?(preview.captureDevicePointConverted(fromLayerPoint: gesture.location(in: self)))
    }
}
