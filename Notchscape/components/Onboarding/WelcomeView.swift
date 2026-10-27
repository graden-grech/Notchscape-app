//
//  WelcomeView.swift
//  Notchscape
//
//  Created by Richard Kunkli on 2024. 09. 26..
//

import SwiftUI
import Defaults

struct WelcomeView: View {
    @Default(.appIconVariant) private var appIconVariant
    var onGetStarted: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(appIconVariant.assetName)
                .resizable().scaledToFit().frame(width: 88, height: 88)
            Text("Notchscape").font(.largeTitle.weight(.semibold))
            Text("A quick tour helps you choose what belongs in your notch. Everything can be changed later.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !AccountFeaturePolicy.enabled {
                Text("No account needed. Your settings are saved on this Mac.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Take a Quick Tour") { onGetStarted?() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            if let onSkip {
                Button("Skip Setup", action: onSkip)
                    .keyboardShortcut(.cancelAction)
            }
            Text("You can replay the tour from General settings or Help.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Text("By Notchscape")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        }
    }
}

#Preview {
    WelcomeView()
}
