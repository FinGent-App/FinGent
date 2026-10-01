// Common/Views/LoopingVideoPlayerView.swift

import SwiftUI
import AVFoundation

struct LoopingVideoPlayerView: UIViewRepresentable {
    let videoName: String
    let videoExtension: String
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(videoName: videoName, videoExtension: videoExtension, videoGravity: videoGravity)
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
        uiView.ensurePlaying()
    }
}

final class LoopingPlayerUIView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var playerLooper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?
    private var observers: [NSObjectProtocol] = []

    init(videoName: String, videoExtension: String, videoGravity: AVLayerVideoGravity = .resizeAspectFill) {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false

        playerLayer.videoGravity = videoGravity
        layer.addSublayer(playerLayer)

        setupPlayer(videoName: videoName, videoExtension: videoExtension)
        setupObservers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupPlayer(videoName: String, videoExtension: String) {
        guard let url = Bundle.main.url(forResource: videoName, withExtension: videoExtension) else {
            return
        }

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        // Disable audio completely so video playback never contends with or gets interrupted by the microphone
        Task {
            if let audioGroup = try? await asset.loadMediaSelectionGroup(for: .audible) {
                item.select(nil, in: audioGroup)
            }
        }

        // Initialize empty AVQueuePlayer: AVPlayerLooper requires the template item NOT be pre-enqueued
        let player = AVQueuePlayer()
        player.isMuted = true
        player.volume = 0.0
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .none

        self.playerLooper = AVPlayerLooper(player: player, templateItem: item)
        self.queuePlayer = player
        self.playerLayer.player = player

        player.play()
    }

    private func setupObservers() {
        let center = NotificationCenter.default

        // 1. Resume playback when entering foreground / becoming active
        observers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.ensurePlaying()
        })

        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.ensurePlaying()
        })

        // 2. Resume playback when audio session interrupts (e.g. microphone toggled)
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.ensurePlaying()
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.ensurePlaying()
        })

        // 3. Fallback: If an item ends and looper pauses, seamlessly rewind and resume
        observers.append(center.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.queuePlayer?.seek(to: .zero)
            self?.ensurePlaying()
        })

        // 4. Fallback: If playback stalled
        observers.append(center.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.ensurePlaying()
        })
    }

    func ensurePlaying() {
        guard let player = queuePlayer else { return }
        if player.timeControlStatus != .playing {
            player.play()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            ensurePlaying()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
