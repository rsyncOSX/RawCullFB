//
//  MemoryViewModel.swift
//  RawCull
//
//  Created by Thomas Evensen on 12/02/2026.
//

import Foundation
import Observation
import OSLog

enum MemoryPressureLevel {
    case normal, warning, critical

    var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }

    var systemImage: String {
        switch self {
        case .normal: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        }
    }
}

@Observable @MainActor
final class MemoryViewModel {
    var totalMemory: UInt64 = 0
    var usedMemory: UInt64 = 0
    var appMemory: UInt64 = 0
    var memoryPressureThreshold: UInt64 = 0
    var systemPressureLevel: MemoryPressureLevel = .normal

    private let pressureThresholdFactor: Double
    @ObservationIgnored private var memoryPressureSource: DispatchSourceMemoryPressure?

    init(
        pressureThresholdFactor: Double = 0.85,
    ) {
        self.pressureThresholdFactor = pressureThresholdFactor
        startMemoryPressureMonitoring()
    }

    deinit {
        memoryPressureSource?.cancel()
        // Logger.process.debugMessageOnly("MemoryViewModel: deinitialized")
    }

    // MARK: - Computed percentages

    var memoryPressurePercentage: Double {
        guard totalMemory > 0 else { return 0 }
        return Double(memoryPressureThreshold) / Double(totalMemory) * 100
    }

    var usedMemoryPercentage: Double {
        guard totalMemory > 0 else { return 0 }
        return Double(usedMemory) / Double(totalMemory) * 100
    }

    var appMemoryPercentage: Double {
        guard usedMemory > 0 else { return 0 }
        return Double(appMemory) / Double(usedMemory) * 100
    }

    // MARK: - Update

    func updateMemoryStats() async {
        // Move heavy mach calls off MainActor
        let (total, used, app, threshold) = await Task.detached {
            let total = ProcessInfo.processInfo.physicalMemory
            let used = self.getUsedSystemMemory()
            let app = self.getAppMemory()
            let threshold = self.calculateMemoryPressureThreshold(total: total)
            return (total, used, app, threshold)
        }.value

        // Update properties on MainActor
        await MainActor.run {
            self.totalMemory = total
            self.usedMemory = used
            self.appMemory = app
            self.memoryPressureThreshold = threshold
        }

        /*
         let message = "MemoryViewModel: updateMemoryStats() Total: \(formatBytes(total)), " +
             "Used: \(formatBytes(used)), App: \(formatBytes(app))"
         Logger.process.debugMessageOnly(message)
          */
    }

    // MARK: - Private helpers

    private nonisolated func getUsedSystemMemory() -> UInt64 {
        let total = ProcessInfo.processInfo.physicalMemory

        var stat = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size,
        )

        let result = withUnsafeMutablePointer(to: &stat) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = UInt64(getpagesize())
        let wired = UInt64(stat.wire_count)
        let active = UInt64(stat.active_count)
        let compressed = UInt64(stat.compressor_page_count)

        return min((wired + active + compressed) * pageSize, total)
    }

    private nonisolated func getAppMemory() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / 4)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }
        return info.phys_footprint
    }

    private nonisolated func calculateMemoryPressureThreshold(total: UInt64) -> UInt64 {
        UInt64(Double(total) * pressureThresholdFactor)
    }

    private func startMemoryPressureMonitoring() {
        guard memoryPressureSource == nil else { return }

        let source = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: .global(qos: .utility))
        source.setEventHandler { [weak self, weak source] in
            guard let source else { return }
            let event = source.data
            Task { @MainActor [weak self] in
                self?.handleMemoryPressureEvent(event)
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func handleMemoryPressureEvent(_ event: DispatchSource.MemoryPressureEvent) {
        if event.contains(.critical) {
            systemPressureLevel = .critical
        } else if event.contains(.warning) {
            systemPressureLevel = .warning
        } else if event.contains(.normal) {
            systemPressureLevel = .normal
        }
    }

    // MARK: - Formatting

    func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
