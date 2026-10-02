//
//  ContentView.swift
//  Glitch for Twitch Watch App
//
//  Created by Lethbridge Safe Families- Director on 2026-09-30.
//

import SwiftUI
import AVKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = HLSPlayerModel()

    @State private var showControls = true
    @State private var videoOnlyMode = false
    @State private var isLoading = false
    @FocusState private var isChannelFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                background

                ScrollView {
                    VStack(spacing: 10) {
                        if !videoOnlyMode {
                            header
                        }

                        playerSection

                        if !videoOnlyMode && showControls {
                            controlsSection
                            detailsSection
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("WatchStream")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onTapGesture {
                if model.isPlaying {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls.toggle()
                    }
                }
            }
            .onDisappear {
                model.stopAndCleanUp()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                    case .active:
                        break
                    default:
                        model.pause()
                        showControls = true
                }
            }
            .onChange(of: model.state) { _, newState in
                isLoading = (newState == .loading || newState == .buffering)
                if newState == .playing {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showControls = false
                    }
                } else {
                    showControls = true
                }
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color(red: 0.06, green: 0.06, blue: 0.09)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("Live Stream")
            .font(.headline)

            Text(model.state.displayText)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private var playerSection: some View {
        ZStack(alignment: .topTrailing) {
            VideoPlayer(player: model.player)
            .frame(height: videoOnlyMode ? 190 : 132)
            .clipShape(RoundedRectangle(cornerRadius: videoOnlyMode ? 0 : 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: videoOnlyMode ? 0 : 14, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: videoOnlyMode ? 0 : 1)
            )
            .ignoresSafeArea(videoOnlyMode ? .all : [], edges: videoOnlyMode ? .all : [])

            if isLoading {
                loadingOverlay
            }

            if !videoOnlyMode {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showControls.toggle()
                    }
                } label: {
                    Image(systemName: showControls ? "chevron.down" : "chevron.up")
                    .font(.caption.bold())
                    .padding(8)
                    .background(.black.opacity(0.55))
                    .clipShape(Circle())
                }
                .padding(8)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        videoOnlyMode.toggle()
                        showControls = true
                    }
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.caption.bold())
                    .padding(8)
                    .background(.black.opacity(0.55))
                    .clipShape(Circle())
                }
                .padding(8)
            }
        }
        .onTapGesture {
            if model.isPlaying {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showControls.toggle()
                }
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                withAnimation(.easeInOut(duration: 0.25)) {
                    videoOnlyMode.toggle()
                    showControls = true
                }
            }
        )
        .overlay(alignment: .bottomTrailing) {
            if !videoOnlyMode {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        videoOnlyMode = true
                        showControls = false
                    }
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.caption.bold())
                    .padding(8)
                    .background(.black.opacity(0.55))
                    .clipShape(Circle())
                }
                .padding(8)
            }
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: videoOnlyMode ? 0 : 14, style: .continuous)
            .fill(.black.opacity(0.25))

            ProgressView()
            .progressViewStyle(.circular)
            .tint(.white)
            .scaleEffect(1.1)
        }
    }

    private var controlsSection: some View {
        VStack(spacing: 10) {
            if !videoOnlyMode {
                TextField("Channel", text: $model.channelName)
                .focused($isChannelFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onSubmit {
                    startWatching()
                }
            }

            HStack(spacing: 8) {
                Button {
                    startWatching()
                } label: {
                    Label("Watch", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)

                Button {
                    model.reconnect()
                    showControls = true
                } label: {
                    Image(systemName: "arrow.clockwise")
                    .frame(width: 34)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button {
                    model.play()
                } label: {
                    Image(systemName: "play.fill")
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isPlaying)

                Button {
                    model.pause()
                    showControls = true
                } label: {
                    Image(systemName: "pause.fill")
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!model.isPlaying)
            }
        }
        .padding(12)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

                Text(model.isLive ? "Live" : "HLS")
                .font(.caption2)
                .foregroundStyle(.secondary)

                Spacer()

                Text(model.isPlaying ? "Playing" : "Paused")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if model.duration > 0 {
                Text("\(format(seconds: model.currentTime)) / \(format(seconds: model.duration))")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            } else {
                Text("Position \(format(seconds: model.currentTime))")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var statusColor: Color {
        switch model.state {
            case .playing: return .green
            case .buffering, .loading: return .yellow
            case .failed: return .red
            default: return .gray
        }
    }

    private func startWatching() {
        model.loadAndPlay()
        isChannelFocused = false
        showControls = false
    }

    private func format(seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        let totalSeconds = max(0, Int(seconds))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

#Preview {
ContentView()
}
