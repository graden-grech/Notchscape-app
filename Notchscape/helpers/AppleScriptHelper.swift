//
//  AppleScriptHelper.swift
//  Notchscape
//
//  Created by Alexander on 2025-03-29.
//

import Foundation

class AppleScriptHelper {
    // Apple recommends serializing script execution off the main thread.
    // Media controls and optional Notes sync share the same executor.
    static let executionQueue = DispatchQueue(label: "notch.apple-events", qos: .userInitiated)
    @discardableResult
    class func execute(_ scriptText: String) async throws -> NSAppleEventDescriptor? {
        try await withCheckedThrowingContinuation { continuation in
            executionQueue.async {
                let script = NSAppleScript(source: scriptText)
                var error: NSDictionary?
                if let descriptor = script?.executeAndReturnError(&error) {
                    continuation.resume(returning: descriptor)
                } else if let error = error {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: error as? [String: Any]))
                } else {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"]))
                }
            }
        }
    }
    
    class func executeVoid(_ scriptText: String) async throws {
        _ = try await execute(scriptText)
    }
}
