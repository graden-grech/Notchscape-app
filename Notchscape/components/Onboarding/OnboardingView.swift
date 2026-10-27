//
//  OnboardingView.swift
//  Notchscape
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI
import AVFoundation

enum OnboardingStep {
    case welcome, account, walkthrough, optionalAccess, finished
}

private let calendarService = CalendarService()

struct OnboardingView: View {
    @ObservedObject private var performance = AppPerformanceManager.shared
    @State var step: OnboardingStep = .welcome
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeView(onGetStarted: {
                    step = AccountFeaturePolicy.enabled ? .account : .walkthrough
                }, onSkip: finishSetup)
            case .account:
                if AccountFeaturePolicy.enabled {
                    AccountOnboardingView { step = .walkthrough }
                } else {
                    Color.clear.onAppear { step = .walkthrough }
                }
            case .walkthrough:
                SettingsTourView(onFinish: {
                    NotchscapeCoordinator.shared.firstLaunch = false
                    step = .finished
                }, onSkip: finishSetup, onOpenSection: openSettings)
            case .optionalAccess:
                OptionalAccessSetupView(
                    onCamera: { _ = await AVCaptureDevice.requestAccess(for: .video) },
                    onCalendar: { _ = try? await calendarService.requestAccess(to: .event) },
                    onReminders: { _ = try? await calendarService.requestAccess(to: .reminder) },
                    onAccessibility: { await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true) },
                    onMusic: { openSettings("Media") },
                    onFinish: finishSetup
                )
            case .finished:
                OnboardingFinishView(onFinish: finishSetup, onOpenSettings: {
                    NotchscapeCoordinator.shared.firstLaunch = false
                    onOpenSettings()
                }, onOptionalAccess: { step = .optionalAccess })
            }
        }
        .frame(width: 400, height: 600)
        .tint(.effectiveAccent)
        .toggleStyle(CompactSwitchToggleStyle())
        .controlSize(.regular)
        .transaction { if performance.suppressAnimations { $0.animation = nil; $0.disablesAnimations = true } }
    }

    private func finishSetup() {
        // Completing onboarding is the only persisted effect of skipping.
        // Existing feature choices and permissions are never changed here.
        NotchscapeCoordinator.shared.firstLaunch = false
        onFinish()
    }

    private func openSettings(_ section: String) {
        guard NotchSettingsDestination.all.contains(where: { $0.id == section && ($0.id != "Account" || AccountFeaturePolicy.enabled) }) else { return }
        finishSetup()
        DispatchQueue.main.async { SettingsWindowController.shared.showWindow(section: section) }
    }
}

/// Four optional connections on one page instead of a sequence of permission
/// walls. Requests happen only after the person clicks that connection button.
private struct OptionalAccessSetupView: View {
    let onCamera: () async -> Void
    let onCalendar: () async -> Void
    let onReminders: () async -> Void
    let onAccessibility: () async -> Void
    let onMusic: () -> Void
    let onFinish: () -> Void
    @State private var requesting: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Optional Access").font(.title2.weight(.semibold))
                Spacer()
                Button("Skip Setup", action: onFinish).disabled(requesting != nil)
                    .keyboardShortcut(.cancelAction)
            }.padding(24)
            Text("Connect only what you plan to use. You can do this later in Settings.")
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24)
            Form {
                Section {
                    accessRow("Camera", symbol: "camera", detail: "For the live mirror. Nothing is recorded.", request: onCamera)
                    accessRow("Calendar", symbol: "calendar", detail: "For events in your Home menu.", request: onCalendar)
                    accessRow("Reminders", symbol: "checklist", detail: "For reminders beside your events.", request: onReminders)
                    accessRow("Accessibility", symbol: "hand.raised", detail: "For volume and brightness HUD replacement.", request: onAccessibility)
                }
                Section {
                    Button("Choose a Music Source…", systemImage: "music.note", action: onMusic)
                        .disabled(requesting != nil)
                    Text("Select your player in Media settings. No music source is changed by opening this page.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden)
            Divider()
            HStack {
                Text("Every connection is optional.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: onFinish).buttonStyle(.borderedProminent)
                    .disabled(requesting != nil).keyboardShortcut(.defaultAction)
            }.padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func accessRow(_ title: String, symbol: String, detail: String,
                           request: @escaping () async -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Connect…") {
                    guard requesting == nil else { return }
                    requesting = title
                    Task { await request(); requesting = nil }
                }.disabled(requesting != nil)
                    .accessibilityLabel("Connect \(title)")
                if requesting == title { ProgressView().controlSize(.small).accessibilityLabel("Waiting for macOS") }
            }
        }.padding(.vertical, 3)
    }
}
