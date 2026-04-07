import SwiftUI
import AVKit

public struct VideoBlock: Codable {
    public let video_url: String
    public let video_thumbnail_url: String?
    public let video_height: Double
    public let video_corner_radius: Double?
    public let autoplay: Bool?
    public let loop: Bool?
    public let muted: Bool?
    public let controls: Bool?
    public let inline_playback: Bool?
}

public struct VideoBlockView: View {
    let block: VideoBlock
    @State private var player: AVPlayer?
    @State private var showThumbnail: Bool

    init(block: VideoBlock) {
        self.block = block
        self._showThumbnail = State(initialValue: !(block.autoplay ?? false))
    }

    public var body: some View {
        ZStack {
            if let player = player, !showThumbnail {
                VideoPlayer(player: player)
                    .frame(height: CGFloat(block.video_height))
                    .clipShape(RoundedRectangle(cornerRadius: CGFloat(block.video_corner_radius ?? 0)))
                    .onAppear {
                        player.isMuted = block.muted ?? true
                        if block.autoplay ?? false { player.play() }
                    }
            } else {
                // Thumbnail with play button overlay
                ZStack {
                    if let thumb = block.video_thumbnail_url, let url = URL(string: thumb) {
                        BundledAsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.black.opacity(0.3)
                        }
                    } else {
                        LinearGradient(colors: [Color(white: 0.15), Color(white: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }

                    // Play button
                    Circle()
                        .fill(.white.opacity(0.9))
                        .frame(width: 48, height: 48)
                        .shadow(radius: 4)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.black)
                                .offset(x: 2)
                        )
                }
                .frame(height: CGFloat(block.video_height))
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(block.video_corner_radius ?? 0)))
                .onTapGesture {
                    if let url = URL(string: block.video_url) {
                        player = AVPlayer(url: url)
                        showThumbnail = false
                    }
                }
            }
        }
    }
}
