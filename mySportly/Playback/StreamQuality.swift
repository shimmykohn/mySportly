import AVFoundation

enum StreamQuality: String, CaseIterable {
    case automatic = "Auto", dataSaver = "Data Saver", hd = "Up to 720p", fullHD = "Up to 1080p", ultraHD = "Up to 4K"
    var bitRate: Double {
        switch self { case .automatic: 0; case .dataSaver: 1_000_000; case .hd: 3_000_000; case .fullHD: 6_000_000; case .ultraHD: 20_000_000 }
    }
    var resolution: CGSize {
        switch self { case .automatic: .zero; case .dataSaver: CGSize(width: 854, height: 480); case .hd: CGSize(width: 1280, height: 720); case .fullHD: CGSize(width: 1920, height: 1080); case .ultraHD: CGSize(width: 3840, height: 2160) }
    }
}
