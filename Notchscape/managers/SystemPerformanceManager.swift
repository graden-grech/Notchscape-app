import AppKit
import Darwin
import Foundation
import IOKit

@MainActor
final class SystemPerformanceManager: ObservableObject {
    static let shared = SystemPerformanceManager()

    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var memoryUsage: Double = 0
    @Published private(set) var usedMemory: UInt64 = 0
    @Published private(set) var totalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published private(set) var diskUsage: Double = 0
    @Published private(set) var usedDisk: Int64 = 0
    @Published private(set) var totalDisk: Int64 = 0
    @Published private(set) var thermalState = "Nominal"
    @Published private(set) var networkReceived: Double = 0
    @Published private(set) var networkSent: Double = 0
    @Published private(set) var diskReadRate: Double?
    @Published private(set) var diskWriteRate: Double?
    @Published private(set) var memoryPressure = "No recent signal"
    private var pressureSource: DispatchSourceMemoryPressure?
    private var previousIO: (Date, UInt64, UInt64, UInt64?, UInt64?)?

    private var samplingTask: Task<Void, Never>?
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    private init() {}

    func startSampling() {
        guard samplingTask == nil else { return }
        previousIO = nil
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        pressure.setEventHandler { [weak self] in
            guard let self, let flags = pressureSource?.data else { return }
            memoryPressure = flags.contains(.critical) ? "Critical" : flags.contains(.warning) ? "Warning" : "Normal"
        }
        pressureSource = pressure; pressure.resume()
        refresh()
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(AppPerformanceManager.shared.samplingInterval))
                guard !Task.isCancelled else { break }
                self?.refresh()
            }
        }
    }

    func stopSampling() {
        samplingTask?.cancel()
        samplingTask = nil
        pressureSource?.cancel(); pressureSource = nil; previousIO = nil
    }

    func refresh() {
        updateCPU()
        updateMemory()
        updateDisk()
        updateIO()
        thermalState = Self.thermalLabel(ProcessInfo.processInfo.thermalState)
    }

    func openActivityMonitor() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"),
            configuration: .init()
        )
    }

    func openSystemSettings() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/System Settings.app"),
            configuration: .init()
        )
    }

    func sleepDisplay() {
        run("/usr/bin/pmset", arguments: ["displaysleepnow"])
    }

    func lockMac() {
        run(
            "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession",
            arguments: ["-suspend"]
        )
    }

    private func run(_ executable: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try? process.run()
    }

    private func updateCPU() {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let ticks = (
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
        defer { previousCPUTicks = ticks }
        guard let previousCPUTicks else { return }

        let user = ticks.user &- previousCPUTicks.user
        let system = ticks.system &- previousCPUTicks.system
        let idle = ticks.idle &- previousCPUTicks.idle
        let nice = ticks.nice &- previousCPUTicks.nice
        let total = user + system + idle + nice
        guard total > 0 else { return }
        cpuUsage = Double(user + system + nice) / Double(total)
    }

    private func updateMemory() {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let pageSize = UInt64(vm_kernel_page_size)
        let pages = UInt64(info.active_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        usedMemory = min(totalMemory, pages * pageSize)
        memoryUsage = totalMemory > 0 ? Double(usedMemory) / Double(totalMemory) : 0
    }

    private func updateDisk() {
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else { return }
        totalDisk = Int64(values.volumeTotalCapacity ?? 0)
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        usedDisk = max(0, totalDisk - available)
        diskUsage = totalDisk > 0 ? Double(usedDisk) / Double(totalDisk) : 0
    }

    private func updateIO() {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        var received: UInt64 = 0, sent: UInt64 = 0
        if getifaddrs(&interfaces) == 0 {
            defer { freeifaddrs(interfaces) }
            var pointer = interfaces
            while let entry = pointer {
                defer { pointer = entry.pointee.ifa_next }
                guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                      let data = entry.pointee.ifa_data, let name = entry.pointee.ifa_name else { continue }
                // Physical en* interfaces only: avoid double-counting VPN, bridge
                // and loopback traffic. No packet content or connection history.
                guard String(cString: name).hasPrefix("en") else { continue }
                let counters = data.assumingMemoryBound(to: if_data.self).pointee
                received += UInt64(counters.ifi_ibytes); sent += UInt64(counters.ifi_obytes)
            }
        }
        var read: UInt64?, written: UInt64?
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }; var count = 0
            while count < 64 {
                let service = IOIteratorNext(iterator); guard service != 0 else { break }; count += 1
                defer { IOObjectRelease(service) }
                if let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
                   let r = stats["Bytes (Read)"] as? NSNumber, let w = stats["Bytes (Write)"] as? NSNumber {
                    read = (read ?? 0) &+ r.uint64Value; written = (written ?? 0) &+ w.uint64Value
                }
            }
        }
        let now = Date(); defer { previousIO = (now, received, sent, read, written) }
        guard let prior = previousIO else { networkReceived = 0; networkSent = 0; diskReadRate = nil; diskWriteRate = nil; return }
        let seconds = now.timeIntervalSince(prior.0); guard seconds > 0 else { return }
        networkReceived = received >= prior.1 ? Double(received-prior.1)/seconds : 0
        networkSent = sent >= prior.2 ? Double(sent-prior.2)/seconds : 0
        diskReadRate = read.flatMap { value in prior.3.flatMap { value >= $0 ? Double(value-$0)/seconds : nil } }
        diskWriteRate = written.flatMap { value in prior.4.flatMap { value >= $0 ? Double(value-$0)/seconds : nil } }
    }

    private static func thermalLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "Nominal"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}
