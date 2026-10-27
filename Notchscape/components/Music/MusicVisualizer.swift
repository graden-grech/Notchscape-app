//
//  MusicVisualizer.swift
//  Notchscape
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//
import AppKit
import Cocoa
import SwiftUI

class AudioSpectrum: NSView {
    private var barLayers: [CAShapeLayer] = []
    private var barScales: [CGFloat] = []
    private var isPlaying: Bool = true
    private var animationTimer: Timer?
    private let barWidth: CGFloat = 3
    private let totalHeight: CGFloat = 14
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupBars()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupBars()
    }

    private func setupBars() {
        let barCount = 4
        let spacing: CGFloat = 1.25
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        frame.size = CGSize(width: totalWidth, height: totalHeight)

        for i in 0 ..< barCount {
            let xPosition = CGFloat(i) * (barWidth + spacing)
            let barLayer = CAShapeLayer()
            barLayer.frame = CGRect(x: xPosition, y: 0, width: barWidth, height: totalHeight)
            barLayer.fillColor = NSColor.clear.cgColor
            barLayer.strokeColor = NSColor.white.cgColor
            barLayer.lineWidth = barWidth
            barLayer.lineCap = .round
            barLayer.allowsGroupOpacity = false
            barLayer.path = barPath(scale: 0.35)
            barLayers.append(barLayer)
            barScales.append(0.35)
            layer?.addSublayer(barLayer)
        }
    }

    private func barPath(scale: CGFloat) -> CGPath {
        let visibleHeight = max(barWidth, totalHeight * scale)
        let centerY = totalHeight / 2
        let halfLine = max(0, (visibleHeight - barWidth) / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: barWidth / 2, y: centerY - halfLine))
        path.addLine(to: CGPoint(x: barWidth / 2, y: centerY + halfLine))
        return path
    }
    
    private func startAnimating() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.updateBars()
        }
    }
    
    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        resetBars()
    }
    
    private func updateBars() {
        for (i, barLayer) in barLayers.enumerated() {
            let currentScale = barScales[i]
            let targetScale = CGFloat.random(in: 0.35 ... 1.0)
            barScales[i] = targetScale
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = barPath(scale: currentScale)
            animation.toValue = barPath(scale: targetScale)
            animation.duration = 0.28
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            if #available(macOS 13.0, *) {
                animation.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 24, preferred: 24)
            }
            barLayer.path = barPath(scale: targetScale)
            barLayer.add(animation, forKey: "roundedHeight")
        }
    }
    
    private func resetBars() {
        for (i, barLayer) in barLayers.enumerated() {
            barLayer.removeAllAnimations()
            barLayer.path = barPath(scale: 0.35)
            barScales[i] = 0.35
        }
    }
    
    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        if isPlaying {
            startAnimating()
        } else {
            stopAnimating()
        }
    }
}

struct AudioSpectrumView: NSViewRepresentable {
    @Binding var isPlaying: Bool
    
    func makeNSView(context: Context) -> AudioSpectrum {
        let spectrum = AudioSpectrum()
        spectrum.setPlaying(isPlaying)
        return spectrum
    }
    
    func updateNSView(_ nsView: AudioSpectrum, context: Context) {
        nsView.setPlaying(isPlaying)
    }
}

#Preview {
    AudioSpectrumView(isPlaying: .constant(true))
        .frame(width: 16, height: 20)
        .padding()
}
