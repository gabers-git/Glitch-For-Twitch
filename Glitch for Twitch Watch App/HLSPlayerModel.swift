//
//  HLSPlayerModel.swift
//  Glitch for Twitch
//
//  Created by Lethbridge Safe Families- Director on 2026-09-30.
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class HLSPlayerModel: ObservableObject {
    enum PlayerState: Equatable {
        case idle
        case loading
        case ready
        case playing
        case paused
        case buffering
        case failed(String)

        var displayText: String {
            switch self {
            case .idle:
                return "Idle"
            case .loading:
                return "Loading"
            case .ready:
                return "Ready"
            case .playing:
                return "Playing"
            case .paused:
                return "Paused"
            case .buffering:
                return "Buffering"
            case .failed(let message):
                return "Error: \(message)"
            }
        }
    }

    private let backendClient = BackendClient(
        baseURL: URL(string: "http://192.168.0.2:3000")!
    )

    private let channelName = "test-channel"

    // Replace this with a real short-lived token when authentication is added.
    private let sessionToken: String? = nil

    private var loadTask: Task<Void, Never>?

    @Published private(set) var state: PlayerState = .idle
    @Published private(set) var isPlaying = false
    @Published private(set) var isLive = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    let player = AVPlayer()

    private var itemCancellables = Set<AnyCancellable>()
    private var playerCancellables = Set<AnyCancellable>()
    private var timeObserver: Any?

    init() {
        configurePlayerObservers()
        configurePeriodicTimeObserver()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }

        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    func loadAndPlay() {
        loadTask?.cancel()

        loadTask = Task { [weak self] in
            guard let self else { return }

            await self.loadFromBackend()
        }
    }


    func play() {
        guard player.currentItem != nil else {
            loadAndPlay()
            return
        }

        log("Play requested")
        player.play()
    }

    func pause() {
        log("Pause requested")
        player.pause()
    }

    func reconnect() {
        log("Reconnect requested")
        loadAndPlay()
    }

    func stopAndCleanUp() {
        log("Stopping and cleaning up")

        loadTask?.cancel()
        loadTask = nil

        player.pause()
        player.replaceCurrentItem(with: nil)

        resetSubscriptions()

        state = .idle
        isPlaying = false
        currentTime = 0
        duration = 0
        isLive = false
    }

    
    private func loadFromBackend() async {
        resetSubscriptions()

        player.pause()
        player.replaceCurrentItem(with: nil)

        state = .loading
        isPlaying = false
        currentTime = 0
        duration = 0
        isLive = false

        do {
            let playback = try await backendClient.requestPlaybackURL(
                channel: channelName,
                sessionToken: sessionToken
            )

            try Task.checkCancellation()

            let item = AVPlayerItem(url: playback.playbackURL)

            item.preferredForwardBufferDuration = 2
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = false

            observe(item: item)

            player.replaceCurrentItem(with: item)

            log("Received authorized playback URL")
            log("Expires at: \(playback.expiresAt)")

            player.play()
        } catch is CancellationError {
            log("Playback request cancelled")
        } catch {
            log("Backend playback request failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
            isPlaying = false
        }
    }


    private func configurePlayerObservers() {
        playerCancellables.removeAll()

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }

                switch status {
                case .paused:
                    self.isPlaying = false

                    if self.player.currentItem == nil {
                        self.state = .idle
                    } else if self.player.currentItem?.status == .readyToPlay {
                        self.state = .paused
                    }

                case .waitingToPlayAtSpecifiedRate:
                    self.isPlaying = false
                    self.state = .buffering

                case .playing:
                    self.isPlaying = true
                    self.state = .playing
                @unknown default:
                    break
                }
            }
            .store(in: &playerCancellables)

        NotificationCenter.default.publisher(
            for: .AVPlayerItemDidPlayToEndTime
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else { return }

            self.log("Playback reached the end")
            self.isPlaying = false
            self.state = .paused
        }
        .store(in: &playerCancellables)

        NotificationCenter.default.publisher(
            for: AVPlayerItem.failedToPlayToEndTimeNotification
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] notification in
            guard let self else { return }

            let error = notification.object as? AVPlayerItem
            let message = error?.error?.localizedDescription ?? "Playback failed"

            self.log("Playback failed: \(message)")
            self.isPlaying = false
            self.state = .failed(message)
        }
        .store(in: &playerCancellables)
    }

    private func observe(item: AVPlayerItem) {
        itemCancellables.removeAll()

        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }

                switch status {
                case .unknown:
                    self.state = .loading
                    self.log("AVPlayerItem status: unknown")

                case .readyToPlay:
                    self.state = self.player.timeControlStatus == .playing
                        ? .playing
                        : .ready

                    self.updateStreamMetadata(for: item)
                    self.log("AVPlayerItem status: readyToPlay")

                case .failed:
                    let message = item.error?.localizedDescription ?? "Unknown AVPlayerItem error"

                    self.log("AVPlayerItem status: failed: \(message)")
                    self.isPlaying = false
                    self.state = .failed(message)

                @unknown default:
                    self.state = .failed("Unknown player status")
                }
            }
            .store(in: &itemCancellables)

        item.publisher(for: \.duration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                guard let self else { return }

                let seconds = duration.seconds

                if seconds.isFinite, seconds > 0 {
                    self.duration = seconds
                } else {
                    self.duration = 0
                }
            }
            .store(in: &itemCancellables)

        item.publisher(for: \.status)
            .compactMap { status -> Error? in
                guard status == .failed else { return nil }
                return item.error
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.log("Item error: \(error.localizedDescription)")
            }
            .store(in: &itemCancellables)
    }

    private func configurePeriodicTimeObserver() {
        let interval = CMTime(
            seconds: 1,
            preferredTimescale: CMTimeScale(NSEC_PER_SEC)
        )

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self else { return }

            let seconds = time.seconds

            if seconds.isFinite {
                self.currentTime = seconds
            }

            if let item = self.player.currentItem {
                let itemDuration = item.duration.seconds

                if itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                    self.isLive = false
                } else {
                    self.isLive = true
                }
            }
        }
    }

    private func updateStreamMetadata(for item: AVPlayerItem) {
        let duration = item.duration.seconds

        if duration.isFinite, duration > 0 {
            self.duration = duration
            self.isLive = false
        } else {
            self.duration = 0
            self.isLive = true
        }
    }

    private func resetSubscriptions() {
        itemCancellables.removeAll()
    }

    private func redactedURL(_ url: URL) -> String {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return "<invalid URL>"
        }

        if components.query != nil {
            components.query = "<redacted>"
        }

        return components.string ?? "<invalid URL>"
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[WatchStream] \(message)")
        #endif
    }
}
