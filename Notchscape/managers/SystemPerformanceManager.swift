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
    @Published private(set) var cpuDataAvailable = false
    @Published private(set) var memoryDataAvailable = false
    @Published private(set) var diskDataAvailable = false
    @Published private(set) var networkDataAvailable = false
    private var pressureSource: DispatchSourceMemoryPressure?
    private var previousIO: (Date, UInt64, UInt64, UInt64?, UInt64?)?

    private var samplingTask: Task<Void, Never>?
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var previousNetworkCountersValid = false
    private var lastDiskSample: Date?
    private var demand = SystemSamplingDemand()

    private init() {}

    func startSampling() {
        demand.dashboardAppeared()
        reconcileSampling()
    }

    func stopSampling() {
        demand.dashboardDisappeared()
        reconcileSampling()
    }

    func setMenuBarSampling(_ requested: Bool) {
        guard demand.menuBarRequested != requested else { return }
        demand.setMenuBarRequested(requested)
        reconcileSampling()
    }

    /// The menu-bar lifecycle coordinator forwards lock/sleep/console/mode
    /// state even with no optional items selected. Demand survives suspension.
    func setSamplingSuspended(_ suspended: Bool) {
        guard demand.suspended != suspended else { return }
        demand.setSuspended(suspended)
        reconcileSampling()
    }

    private func reconcileSampling() {
        if demand.shouldSample { beginSampling() } else { endSampling() }
    }

    private func beginSampling() {
        guard samplingTask == nil else { return }
        previousIO = nil; previousCPUTicks = nil; previousNetworkCountersValid = false; lastDiskSample = nil
        memoryPressure = "No recent signal"
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

    private func endSampling() {
        guard samplingTask != nil else { return }
        samplingTask?.cancel()
        samplingTask = nil
        pressureSource?.cancel(); pressureSource = nil; previousIO = nil
        previousCPUTicks = nil; previousNetworkCountersValid = false; lastDiskSample = nil
        cpuDataAvailable = false; memoryDataAvailable = false
        diskDataAvailable = false; networkDataAvailable = false
    }

    func refresh() {
        guard demand.shouldSample else { return }
        updateCPU()
        updateMemory()
        // Filesystem capacity does not need a refresh on each CPU sample.
        if lastDiskSample.map({ Date().timeIntervalSince($0) >= 30 }) ?? true {
            lastDiskSample = Date(); updateDisk()
        }
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
        guard result == KERN_SUCCESS else { cpuDataAvailable = false; previousCPUTicks = nil; return }

        let ticks = (
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
        defer { previousCPUTicks = ticks }
        guard let previousCPUTicks,
              ticks.user >= previousCPUTicks.user, ticks.system >= previousCPUTicks.system,
              ticks.idle >= previousCPUTicks.idle, ticks.nice >= previousCPUTicks.nice else {
            cpuDataAvailable = false; return
        }

        let user = ticks.user &- previousCPUTicks.user
        let system = ticks.system &- previousCPUTicks.system
        let idle = ticks.idle &- previousCPUTicks.idle
        let nice = ticks.nice &- previousCPUTicks.nice
        let total = user + system + idle + nice
        guard total > 0 else { cpuDataAvailable = false; return }
        cpuUsage = Double(user + system + nice) / Double(total)
        cpuDataAvailable = true
    }

    private func updateMemory() {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { memoryDataAvailable = false; return }

        let pageSize = UInt64(vm_kernel_page_size)
        let pages = UInt64(info.active_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        usedMemory = min(totalMemory, pages * pageSize)
        memoryUsage = totalMemory > 0 ? Double(usedMemory) / Double(totalMemory) : 0
        memoryDataAvailable = totalMemory > 0
    }

    private func updateDisk() {
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else { diskDataAvailable = false; return }
        guard let total = values.volumeTotalCapacity, total > 0,
              let available = values.volumeAvailableCapacityForImportantUsage,
              available >= 0, available <= Int64(total) else { diskDataAvailable = false; return }
        totalDisk = Int64(total)
        usedDisk = max(0, totalDisk - available)
        diskUsage = totalDisk > 0 ? Double(usedDisk) / Double(totalDisk) : 0
        diskDataAvailable = totalDisk > 0
    }

    private func updateIO() {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        var received: UInt64 = 0, sent: UInt64 = 0
        var networkCountersValid = false
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
                networkCountersValid = true
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
        let now = Date()
        defer { previousIO = (now, received, sent, read, written); previousNetworkCountersValid = networkCountersValid }
        guard let prior = previousIO else { networkDataAvailable = false; diskReadRate = nil; diskWriteRate = nil; return }
        let seconds = now.timeIntervalSince(prior.0)
        guard seconds.isFinite, seconds > 0 else { networkDataAvailable = false; diskReadRate = nil; diskWriteRate = nil; return }
        networkDataAvailable = previousNetworkCountersValid && networkCountersValid && received >= prior.1 && sent >= prior.2
        if networkDataAvailable {
            networkReceived = Double(received-prior.1)/seconds
            networkSent = Double(sent-prior.2)/seconds
        }
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
