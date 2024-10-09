//
//  HomeControlAgentApp.swift
//  HomeControlAgent
//
//  Created by Christoph Pageler on 02.10.24.
//

import SwiftUI

@main
struct HomeControlAgentApp: App {
    let viewModel = ViewModel()

    var body: some Scene {
        MenuBarExtra(
            content: {
                button(keyPath: \.menuBarLoadPowerTitle, titleMode: .loadPower)
                button(keyPath: \.menuBarSolarPowerTitle, titleMode: .solarPower)
                button(keyPath: \.menuBarBatteryPowerTitle, titleMode: .batteryPower)
                button(keyPath: \.menuBarBatteryLevelTitle, titleMode: .batteryLevel)
                button(keyPath: \.menuBarGridPowerTitle, titleMode: .gridPower)
                button(keyPath: \.menuBarUpdateTitle, titleMode: nil)
                Divider()
                Button("Exit") { NSApplication.shared.terminate(self) }
            },
            label: {
                if let menuBarImage = viewModel.menuBarImage {
                    menuBarImage
                }
                Text(viewModel.menuBarTitle)
            }
        )
    }

    @ViewBuilder private func button(keyPath: KeyPath<ViewModel, String?>, titleMode: TitleMode?) -> some View {
        if let title = viewModel[keyPath: keyPath] {
            Button(title) {
                if let titleMode {
                    viewModel.titleMode = titleMode
                }
            }
        } else {
            EmptyView()
        }
    }
}
