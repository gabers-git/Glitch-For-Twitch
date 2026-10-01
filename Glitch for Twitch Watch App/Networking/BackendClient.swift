//
//  BackendClient.swift
//  Glitch for Twitch
//
//  Created by Lethbridge Safe Families- Director on 2026-09-30.
//

import Foundation

enum BackendError: LocalizedError {
    case invalidResponse
    case server(statusCode: Int)
    case decodingFailed
    case invalidPlaybackURL

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid response."
        case .server(let statusCode):
            return "The server returned HTTP \(statusCode)."
        case .decodingFailed:
            return "The server response could not be read."
        case .invalidPlaybackURL:
            return "The server returned an invalid playback URL."
        }
    }
}

final class BackendClient {
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func requestPlaybackURL(
        channel: String,
        sessionToken: String?
    ) async throws -> PlaybackResponse {
        let endpoint = baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("playback")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        if let sessionToken {
            request.setValue(
                "Bearer \(sessionToken)",
                forHTTPHeaderField: "Authorization"
            )
        }

        let body = PlaybackRequest(channel: channel)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BackendError.server(
                statusCode: httpResponse.statusCode
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let result = try decoder.decode(
                PlaybackResponse.self,
                from: data
            )

            guard result.playbackURL.scheme == "https" else {
                throw BackendError.invalidPlaybackURL
            }

            return result
        } catch let error as BackendError {
            throw error
        } catch {
            throw BackendError.decodingFailed
        }
    }
}
