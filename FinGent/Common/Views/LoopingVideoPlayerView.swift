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

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {}
}

final class LoopingPlayerUIView: UIView {
    private var playerLayer = AVPlayerLayer()
    private var playerLooper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?

    init(videoName: String, videoExtension: String, videoGravity: AVLayerVideoGravity = .resizeAspectFill) {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false

        playerLayer.videoGravity = videoGravity
        layer.addSublayer(playerLayer)

        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)

        if let url = Bundle.main.url(forResource: videoName, withExtension: videoExtension) {
            let asset = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            let player = AVQueuePlayer(playerItem: item)
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            self.playerLooper = AVPlayerLooper(player: player, templateItem: item)
            self.queuePlayer = player
            self.playerLayer.player = player
            player.play()
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.queuePlayer?.play()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
