/*
 * Atoll (DynamicIsland) / NotchFree
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import Foundation
import NotchFreeCore

/// Bridges `PhoneDropServer` (QR Web Drop for Android & iPhone) and
/// `LocalSendReceiveCoordinator` (Android Share Sheet via LocalSend) with
/// NotchFree's Shelf and Clipboard.
@MainActor
final class PhoneDropBridge {
    static let shared = PhoneDropBridge()
    private var isConfigured = false

    private init() {}

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true

        // 1. Smart routing for incoming drops (files -> Shelf, text/links -> Clipboard)
        PhoneDropServer.shared.onItemReceived = { [weak self] payload in
            self?.routeDropToMac(payload)
        }

        // 2. Provide Mac Shelf files for Mac -> Phone browser downloads
        PhoneDropServer.shared.shelfFilesProvider = {
            ShelfStateViewModel.shared.items.compactMap { item -> ShelfShareableFile? in
                guard case .file(let bookmarkData) = item.kind else { return nil }
                let resolvedURL: URL?
                if let cachedPath = item.cachedPath {
                    resolvedURL = URL(fileURLWithPath: cachedPath)
                } else {
                    resolvedURL = Bookmark(data: bookmarkData).resolveWithoutMounting()
                }
                guard let url = resolvedURL, FileManager.default.fileExists(atPath: url.path) else {
                    return nil
                }
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                return ShelfShareableFile(
                    id: item.id.uuidString,
                    name: url.lastPathComponent,
                    url: url,
                    byteCount: size
                )
            }
        }

        // 3. Provide current Mac clipboard text for Mac -> Phone pull
        PhoneDropServer.shared.macClipboardProvider = {
            NSPasteboard.general.string(forType: .string)
        }

        // 4. Start LocalSend listener/discovery so Android Share Sheet can discover NotchFree
        LocalSendService.shared.startDiscovery()
    }

    private func routeDropToMac(_ payload: DroppedItemPayload) {
        switch payload.kind {
        case .file:
            guard let fileURL = payload.fileURL else { return }
            Task { @MainActor in
                let shelfItems = await ShelfDropService.items(from: [fileURL])
                if !shelfItems.isEmpty {
                    ShelfStateViewModel.shared.add(shelfItems)
                }
            }
        case .text:
            guard let text = payload.text, !text.isEmpty else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }
}
