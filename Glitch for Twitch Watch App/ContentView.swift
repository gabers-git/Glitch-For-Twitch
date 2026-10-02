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

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                TextField("Twitch channel", text: $model.channelName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit {
                        model.loadAndPlay()
                    }

                Button {
                    model.loadAndPlay()
                } label: {
                    Label("Watch", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)

                VideoPlayer(player: model.player)
                    .frame(height: 145)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                statusView

                HStack(spacing: 8) {
                    Button {
                        model.play()
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isPlaying)

                    Button {
                        model.pause()
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.isPlaying)
                }

                Button {
                    model.reconnect()
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                streamDetails
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .navigationTitle("WatchStream")
        .onDisappear {
            model.stopAndCleanUp()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                break

            case .inactive, .background:
                model.pause()
            @unknown default:
                model.pause()
            }
        }
    }

    private var statusView: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(model.state.displayText)
                .font(.caption2)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }

    private var streamDetails: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.isLive ? "Stream type: Live" : "Stream type: HLS")
                .font(.caption2)

            if model.duration > 0 {
                Text("Time: \(format(seconds: model.currentTime)) / \(format(seconds: model.duration))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Position: \(format(seconds: model.currentTime))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusColor: Color {
        switch model.state {
        case .playing:
            return .green
        case .buffering, .loading:
            return .yellow
        case .failed:
            return .red
        default:
            return .gray
        }
    }

    private func format(seconds: Double) -> String {
        guard seconds.isFinite else {
            return "--:--"
        }

        let totalSeconds = max(0, Int(seconds))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60

        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

#Preview {
    ContentView()
}

