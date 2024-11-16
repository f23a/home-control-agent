//
//  ViewModel.swift
//  HomeControlAgent
//
//  Created by Christoph Pageler on 09.10.24.
//

import Combine
import HomeControlClient
import HomeControlKit
import HomeControlLogging
import Logging
import SwiftUI

@Observable
@MainActor
final class ViewModel {
    private let logger = Logger(homeControl: "agent.view-model")

    var titleMode = TitleMode.solarPower {
        didSet { fireUpdateTimer() }
    }

    private var updateTimer: Timer?

    private var client: HomeControlClient
    private var websocket: HomeControlWebSocket

    private(set) var latestInverterReading: Stored<InverterReading>?

    var menuBarImage: Image? {
        guard let latestInverterReading else { return nil }

        switch titleMode {
        case .solarPower:
            if latestInverterReading.value.fromSolar > 4000 {
                return .init(systemName: "sun.max")
            } else {
                return .init(systemName: "sun.min")
            }
        case .loadPower:
            return .init(systemName: "house")
        case .batteryPower, .batteryLevel:
            if latestInverterReading.value.isCharging {
                return .init(systemName: "battery.100percent.bolt")
            } else {
                switch latestInverterReading.value.batteryLevel {
                case 0..<0.125:
                    return .init(systemName: "battery.0percent")
                case 0.125..<0.375:
                    return .init(systemName: "battery.25percent")
                case 0.375..<0.625:
                    return .init(systemName: "battery.50percent")
                case 0.625..<0.875:
                    return .init(systemName: "battery.75percent")
                default:
                    return .init(systemName: "battery.100percent")
                }
            }
        case .gridPower:
            return .init(systemName: "powercord")
        }
    }

    var menuBarTitle: String {
        guard let latestInverterReading else {
            return "Home Control"
        }

        switch titleMode {
        case .solarPower:
            return latestInverterReading.value.formatted(\.fromSolar, options: .short)
        case .loadPower:
            return latestInverterReading.value.formatted(\.toLoad, options: .short)
        case .batteryPower:
            return latestInverterReading.value.formatted(\.fromBattery, options: .short)
        case .batteryLevel:
            return latestInverterReading.value.formatted(\.batteryLevel, options: .short)
        case .gridPower:
            return latestInverterReading.value.formatted(\.fromGrid, options: .short)
        }
    }

    var menuBarLoadPowerTitle: String? {
        guard let latestInverterReading else { return nil }

        return "Load: \(latestInverterReading.value.formatted(\.toLoad))"
    }

    var menuBarSolarPowerTitle: String? {
        guard let latestInverterReading else { return nil }

        return "Solar: \(latestInverterReading.value.formatted(\.fromSolar))"
    }

    var menuBarBatteryPowerTitle: String? {
        guard let latestInverterReading else { return nil }

        if latestInverterReading.value.isCharging {
            return "To Battery: \(latestInverterReading.value.formatted(\.toBattery))"
        } else {
            return "From Battery: \(latestInverterReading.value.formatted(\.fromBattery))"
        }
    }

    var menuBarBatteryLevelTitle: String? {
        guard let latestInverterReading else { return nil }

        return "Battery Level: \(latestInverterReading.value.formatted(\.batteryLevel))"
    }

    var menuBarGridPowerTitle: String? {
        guard let latestInverterReading else { return nil }

        if latestInverterReading.value.toGrid > latestInverterReading.value.fromGrid {
            return "To Grid: \(latestInverterReading.value.formatted(\.toGrid))"
        } else {
            return "From Grid: \(latestInverterReading.value.formatted(\.fromGrid))"
        }
    }

    var menuBarUpdateTitle: String?

    init() {
        LoggingSystem.bootstrapHomeControl()

        // swiftlint:disable:next force_try
        let ip = try! DotEnv.fromMainBundle().require("MAC_MINI_IP")
        var client = HomeControlClient(host: ip, port: 8080)!
        client.authToken = try? DotEnv.fromMainBundle().require("PROD_AUTH_TOKEN")
        self.client = client
        self.websocket = .init(client: client)
        self.websocket.delegate = self

        updateTimer = .scheduledTimer(
            timeInterval: 2,
            target: self,
            selector: #selector(fireUpdateTimer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(updateTimer!, forMode: .common)
        fireUpdateTimer()

        updateLatestInverterReading()
    }

    // MARK: - @objc private

    @objc private func fireUpdateTimer() {
        guard let latestInverterReading else {
            menuBarUpdateTitle = "Updated: Never"
            return
        }

        let age = Date().timeIntervalSince(latestInverterReading.value.readingAt)
        if age < 3 {
            menuBarUpdateTitle = "Updated: Now"
        } else {
            let formatter = RelativeDateTimeFormatter()
            formatter.formattingContext = .standalone
            formatter.dateTimeStyle = .named
            formatter.unitsStyle = .abbreviated
            let relativeString = formatter.localizedString(
                for: latestInverterReading.value.readingAt,
                relativeTo: Date()
            )
            menuBarUpdateTitle = "Updated: \(relativeString)"
        }
    }

    @objc private func closeApplication() {
        NSApplication.shared.terminate(nil)
    }

    private func updateLatestInverterReading() {
        Task {
            let latest = try? await client.inverterReading.latest()
            await MainActor.run {
                latestInverterReading = latest
            }
        }
    }
}

extension ViewModel: @preconcurrency HomeControlWebSocketDelegate {
    func homeControlWebSocket(
        _ homeControlWebSocket: HomeControlWebSocket,
        didCreateInverterReading inverterReading: Stored<InverterReading>
    ) {
        latestInverterReading = inverterReading
    }

    func homeControlWebSocket(
        _ homeControlWebSocket: HomeControlWebSocket,
        didSaveSetting setting: HomeControlKit.Setting
    ) {
        logger.info("Did save setting \(setting)")
    }
}
