//
//  APIModels.swift
//  Glitch for Twitch
//
//  Created by Lethbridge Safe Families- Director on 2026-09-30.
//

import Foundation

struct PlaybackRequest: Encodable {
    let channel: String
}

struct PlaybackResponse: Decodable {
    let isLive: Bool
    let playbackURL: URL
    let expiresAt: Date
    let contentType: String
}

struct StreamStatusResponse: Decodable {
    let channel: String
    let isLive: Bool
    let title: String?
    let category: String?
    let viewerCount: Int?
    let checkedAt: Date
}

