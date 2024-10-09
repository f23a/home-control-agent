//
//  ViewModel.swift
//  HomeControlAgent
//
//  Created by Christoph Pageler on 09.10.24.
//

import Combine
import HomeControlClient
import HomeControlKit
import SwiftUI

@Observable
@MainActor
final class ViewModel {
    var titleMode = TitleMode.solarPower {
        didSet { fireUpdateTimer() }
    }

    private var updateTimer: Timer?
    private var repairWebSocketTimer: Timer?

    private var client: HomeControlClient
    private var cancellables = Set<AnyCancellable>()
    private var webSocketID: UUID?
    private var webSocketStream: SocketStream?
    private var webSocketSettings = WebSocketSettings.default

    private(set) var latestInverterReading: StoredInverterReading?

    var menuBarImage: Image? {
        guard let latestInverterReading else { return nil }

        switch titleMode {
        case .solarPower:
            if latestInverterReading.reading.fromSolar > 4000 {
                return .init(systemName: "sun.max")
            } else {
                return .init(systemName: "sun.min")
            }
        case .loadPower:
            return .init(systemName: "house")
        case .batteryPower, .batteryLevel:
            if latestInverterReading.reading.isCharging {
                return .init(systemName: "battery.100percent.bolt")
            } else {
                switch latestInverterReading.reading.batteryLevel {
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
            return latestInverterReading.reading.formatted(\.fromSolar, options: .short)
        case .loadPower:
            return latestInverterReading.reading.formatted(\.toLoad, options: .short)
        case .batteryPower:
            return latestInverterReading.reading.formatted(\.fromBattery, options: .short)
        case .batteryLevel:
            return latestInverterReading.reading.formatted(\.batteryLevel, options: .short)
        case .gridPower:
            return latestInverterReading.reading.formatted(\.fromGrid, options: .short)
        }
    }

    var menuBarLoadPowerTitle: String? {
        guard let latestInverterReading else { return nil }

        return "Load: \(latestInverterReading.reading.formatted(\.toLoad))"
    }

    var menuBarSolarPowerTitle: String? {
        guard let latestInverterReading else { return nil }

        return "Solar: \(latestInverterReading.reading.formatted(\.fromSolar))"
    }

    var menuBarBatteryPowerTitle: String? {
        guard let latestInverterReading else { return nil }

        if latestInverterReading.reading.isCharging {
            return "To Battery: \(latestInverterReading.reading.formatted(\.toBattery))"
        } else {
            return "From Battery: \(latestInverterReading.reading.formatted(\.fromBattery))"
        }
    }

    var menuBarBatteryLevelTitle: String? {
        guard let latestInverterReading else { return nil }

        return "Battery Level: \(latestInverterReading.reading.formatted(\.batteryLevel))"
    }

    var menuBarGridPowerTitle: String? {
        guard let latestInverterReading else { return nil }

        if latestInverterReading.reading.toGrid > latestInverterReading.reading.fromGrid {
            return "To Grid: \(latestInverterReading.reading.formatted(\.toGrid))"
        } else {
            return "From Grid: \(latestInverterReading.reading.formatted(\.fromGrid))"
        }
    }

    var menuBarUpdateDate = Date()
    var menuBarUpdateTitle: String? {
        guard let latestInverterReading else {
            return "Updated: Never"
        }

        let age = Date().timeIntervalSince(latestInverterReading.reading.readingAt)
        if age < 3 {
            return "Updated: Now"
        } else {
            let formatter = RelativeDateTimeFormatter()
            formatter.formattingContext = .standalone
            formatter.dateTimeStyle = .named
            formatter.unitsStyle = .abbreviated
            let relativeString = formatter.localizedString(
                for: latestInverterReading.reading.readingAt,
                relativeTo: menuBarUpdateDate
            )
            return "Updated: \(relativeString)"
        }
    }

    init() {
        client = .localhost
        client.authToken = Environment.require("AUTH_TOKEN")

        updateTimer = .scheduledTimer(
            timeInterval: 2,
            target: self,
            selector: #selector(fireUpdateTimer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(updateTimer!, forMode: .common)
        fireUpdateTimer()

        repairWebSocketTimer = .scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(fireRepairWebSocketTimer),
            userInfo: nil,
            repeats: true
        )

        updateLatestInverterReading()
    }

    // MARK: - @objc private

    @objc private func fireUpdateTimer() {
        menuBarUpdateDate = Date()
    }

    @objc private func fireRepairWebSocketTimer() {
        guard webSocketStream == nil else { return }
        initializeWebSocket()
    }

    @objc private func closeApplication() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - WebSocket

    private func initializeWebSocket() {
        self.webSocketStream = client.webSocket.socketStream()
        if let webSocketStream {
            Task {
                do {
                    for try await message in webSocketStream {
                        guard let webSocketMessage = message.webSocketMessage else {
                            print("Unable to handle message \(message)")
                            continue
                        }

                        switch webSocketMessage {
                        case let didRegister as WebSocketDidRegisterMessage:
                            self.webSocketID = didRegister.content.id
                            self.sendWebSocketSettings(webSocketSettings)
                        case let didCreateInverterReading as WebSocketDidCreateInverterReadingMessage:
                            await MainActor.run {
                                latestInverterReading = didCreateInverterReading.content.inverterReading
                            }
                        case is WebSocketPingMessage:
                            break
                        default:
                            print("Unknown websocket message \(webSocketMessage.identifier)")
                        }
                    }
                } catch {
                    print("Failed message \(error)")
                }

                self.webSocketStream = nil
                self.webSocketID = nil
            }
        }
    }

    private func updateLatestInverterReading() {
        Task {
            let latest = try? await client.inverterReading.latest()
            await MainActor.run {
                latestInverterReading = latest
            }
        }
    }

    private func sendWebSocketSettings(_ settings: WebSocketSettings) {
        guard let webSocketID else { return }
        Task { @MainActor in
            do {
                try await client.webSocket.update(settings: settings, for: webSocketID)
            } catch {
                print("Failed to update settings")
            }
        }
    }
}
