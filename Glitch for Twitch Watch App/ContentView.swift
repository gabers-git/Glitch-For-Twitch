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
    @FocusState private var isChannelFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    header

                    VideoPlayer(player: model.player)
                    .frame(height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                    )

                    statusRow

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
                        model.loadAndPlay()
                        isChannelFocused = false
                    }

                    HStack(spacing: 8) {
                        Button {
                            model.loadAndPlay()
                            isChannelFocused = false
                        } label: {
                            Label("Watch", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)

                        Button {
                            model.reconnect()
                        } label: {
                            Label("↻", systemImage: "arrow.clockwise")
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
                        } label: {
                            Image(systemName: "pause.fill")
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.isPlaying)
                    }

                    details
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("WatchStream")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .background(
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(red: 0.07, green: 0.07, blue: 0.10)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .onDisappear { model.stopAndCleanUp() }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                    case .active:
                        break
                    default:
                        model.pause()
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("Live Stream")
            .font(.headline)
            .foregroundStyle(.primary)

            Text(model.state.displayText)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private var statusRow: some View {
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
        .padding(.horizontal, 2)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
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
        .padding(.top, 2)
    }

    private var statusColor: Color {
        switch model.state {
            case .playing: return .green
            case .buffering, .loading: return .yellow
            case .failed: return .red
            default: return .gray
        }
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
