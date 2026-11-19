import Foundation
import AetherEngine
import AVKit
import Combine
import MediaPlayer
import Observation
import SwiftUI

struct PlaybackAlternative {
    let channel: Channel
    let url: URL
}

@MainActor @Observable final class PlaybackController {
    /// What the video views show: the app's own player, or the engine's
    /// while it plays a file the system player can't open.
    private(set) var player: AVPlayer
    private let systemPlayer = AVPlayer()
    private(set) var channel: Channel?
    private(set) var previous: Channel?
    private(set) var currentURL: URL?
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var hasVideoFrame = false
    private(set) var videoUnavailable = false
    private(set) var playbackNotice: String?
    var errorMessage: String?
    var onFailure: (() -> Void)?
    var quality: StreamQuality = .automatic { didSet { applyQuality() } }
    var supportsQualityPreference: Bool { currentURL?.pathExtension.lowercased() == "m3u8" }
    private var itemObservation: NSKeyValueObservation?
    private var bufferObservation: NSKeyValueObservation?
    private var timeObservation: NSKeyValueObservation?
    private var failedObserver: NSObjectProtocol?
    private var stalledObserver: NSObjectProtocol?
    private var retryTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var stallTask: Task<Void, Never>?
    private var videoTask: Task<Void, Never>?
    private var alternatives: [PlaybackAlternative] = []
    private var wantsPlayback = false
    private var audioReady = false
    private var startedImmediately = false
    private var sessionID = UUID()
    private var attempts = 0
    private var preferredLanguage = "en"
    private var title: String?
    private var remoteTargets: [Any] = []
    /// The second game in two-up viewing: no lock-screen controls or Now Playing.
    let secondary: Bool
    /// Whether this player's sound is off (two-up viewing plays one at a time).
    private(set) var muted = false
    /// Live channels vs. movies and episodes, which seek, resume and end.
    private(set) var isLive = true
    private(set) var reachedEnd = false
    /// Position and duration of a movie or episode, every 15 s and on pause, stop and end.
    var onProgress: ((_ position: Double, _ duration: Double, _ final: Bool) -> Void)?
    private var pendingStart: Double?
    private var endObserver: NSObjectProtocol?
    private var progressObserver: Any?
    private var startTimeout: Task<Void, Never>?
    /// Plays MKV and other files the system player can't open: it reads the
    /// file itself and serves it to its own AVPlayer as local HLS. Made on
    /// first use, then kept, as its documentation asks.
    private var engine: AetherEngine?
    private var engineSinks: Set<AnyCancellable> = []
    /// The engine keeps a paused title alive in the background only while it's in Picture in Picture.
    var inPictureInPicture = false { didSet { engine?.pictureInPictureActive = inPictureInPicture } }
    private var usesEngine: Bool { !isLive && currentURL.map { !VODFormat.isNative($0.pathExtension) } == true }
    func setMuted(_ on: Bool) { muted = on; player.isMuted = on }

    init(secondary: Bool = false) {
        self.secondary = secondary
        player = systemPlayer
        observe(systemPlayer)
        guard !secondary else { return }
        let commands = MPRemoteCommandCenter.shared()
        remoteTargets.append(commands.playCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.resume() }; return .success })
        remoteTargets.append(commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.pause() }; return .success })
        remoteTargets.append(commands.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.toggle() }; return .success })
    }
    private func observe(_ player: AVPlayer) {
        // The engine's player can already be playing by the time it's shown.
        timeObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player === player else { return }
                self.isPlaying = player.timeControlStatus == .playing
                if player.timeControlStatus == .paused, self.audioReady, self.preparationTask == nil, player.currentItem?.status == .readyToPlay {
                    self.wantsPlayback = false
                }
                self.isLoading = self.wantsPlayback && (!self.audioReady || self.preparationTask != nil || player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
                if self.isPlaying { self.stallTask?.cancel(); self.stallTask = nil; self.startTimeout?.cancel(); self.startTimeout = nil }
                self.updateNowPlaying()
            }
        }
        progressObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 15, preferredTimescale: 1), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reportProgress(final: false) }
        }
    }
    /// Moves the views and the observers to another player.
    private func show(_ next: AVPlayer) {
        guard next !== player else { return }
        if let progressObserver { player.removeTimeObserver(progressObserver) }
        player = next; next.isMuted = muted
        observe(next)
    }

    func play(_ channel: Channel, url: URL, title: String?, preferredLanguage: String, alternates: [PlaybackAlternative] = [], live: Bool = true, startAt: Double? = nil) {
        if self.channel?.id != channel.id { previous = self.channel }
        reportProgress()
        cancelPending(); stopEngine()
        isLive = live; pendingStart = startAt; reachedEnd = false
        self.channel = channel; currentURL = url; self.title = title; self.preferredLanguage = preferredLanguage
        if !live { watchStart() }
        alternatives = Array(alternates.filter { $0.channel.id != channel.id }.prefix(2))
        videoUnavailable = false; playbackNotice = nil
        attempts = 0; errorMessage = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        wantsPlayback = true
        preparePlayback()
    }
    private func preparePlayback() {
        let token = sessionID
        isLoading = true; audioReady = false; hasVideoFrame = false
        if usesEngine { loadEngine(token: token); return }
        // Loading the asset and setting up audio are independent. Start the
        // single player item now so network startup overlaps audio activation.
        replaceItem()
        preparationTask = Task {
            do {
                try await PlaybackAudioSession.shared.activate()
                guard !Task.isCancelled, sessionID == token else { return }
                preparationTask = nil
                audioReady = true
                if wantsPlayback { player.play(); startAvailableMedia() }
            } catch {
                guard !Task.isCancelled, sessionID == token else { return }
                preparationTask = nil; isLoading = false
                errorMessage = "Audio output could not be activated. Try again after other audio activity finishes."
            }
        }
    }
    private func loadEngine(token: UUID) {
        guard let url = currentURL else { return }
        preparationTask = Task {
            do {
                try await PlaybackAudioSession.shared.activate()
                guard !Task.isCancelled, sessionID == token else { return }
                audioReady = true
            } catch {
                guard !Task.isCancelled, sessionID == token else { return }
                preparationTask = nil; isLoading = false
                errorMessage = "Audio output could not be activated. Try again after other audio activity finishes."
                return
            }
            do {
                let engine = try engine ?? makeEngine()
                var options = LoadOptions()
                // Providers commonly allow one connection per account.
                options.maxConcurrentSourceRequests = 1
                options.preferredAudioLanguages = [preferredLanguage]
                // The system player's own audio and subtitle menus, in Picture in Picture and AirPlay too.
                options.nativeAudioTrackMenu = true; options.prepareNativeSubtitles = true
                // Its software decoder draws into a view of its own, which this player doesn't show.
                options.escalatesToSoftwarePath = false
                options.generatesBackgroundScrubPreviews = false
                try await engine.load(url: url, startPosition: pendingStart, options: options)
                guard sessionID == token else { return }
                preparationTask = nil; pendingStart = nil
                if let player = engine.currentAVPlayer { show(player) }
                isLoading = wantsPlayback && player.timeControlStatus != .playing
                if !wantsPlayback { engine.pause() }
            } catch is CancellationError {
                // A newer title, a retry or a stop replaced this load.
            } catch {
                guard sessionID == token else { return }
                preparationTask = nil
                engineFailed(engine?.errorInfo)
            }
        }
    }
    private func makeEngine() throws -> AetherEngine {
        let engine = try AetherEngine()
        // Publishers fire while the engine is changing; act once it has.
        engine.$currentAVPlayer.sink { [weak self] player in
            Task { @MainActor [weak self] in
                guard let self, self.usesEngine, let player, self.errorMessage == nil else { return }
                self.show(player)
            }
        }.store(in: &engineSinks)
        engine.$state.sink { [weak self, weak engine] state in
            // The engine sets the failure's details just before the state, and clears them after it.
            let token = self?.sessionID, info = engine?.errorInfo
            Task { @MainActor [weak self] in
                guard let self, self.usesEngine, self.sessionID == token else { return }
                if state == .ended { self.reachedEnd = true; self.reportProgress() }
                if case .error = state { self.engineFailed(info) }
            }
        }.store(in: &engineSinks)
        engine.$videoRoute.sink { [weak self] route in
            let token = self?.sessionID
            Task { @MainActor [weak self] in
                guard let self, self.usesEngine, self.sessionID == token, route == .software else { return }
                self.fail("This title’s video is in a format iPhone can’t decode in this app.")
            }
        }.store(in: &engineSinks)
        engine.pictureInPictureActive = inPictureInPicture
        self.engine = engine
        return engine
    }
    /// A failed load reports twice, as a thrown error and as a state; the first one wins.
    private func engineFailed(_ info: PlaybackErrorInfo?) {
        guard usesEngine, errorMessage == nil else { return }
        let message = switch info?.kind {
        case .sourceRefused?, .sourceRateLimited?: PlaybackFailure(httpStatus: info?.underlyingCode).message
        case .sourceOpenFailed?, .vodSourceFailed?, .reloadFailed?, .sourceFabricatesRanges?, .sourceCertificateRejected?:
            "This title couldn’t be read from your provider. It may not be sending it right now; try again later."
        case .storageExhausted?: "There isn’t enough free space on this iPhone to play this title."
        default: "This title’s video or audio is in a format iPhone can’t play in this app."
        }
        fail(message)
    }
    /// Ends the engine's session, and with it the connection to the provider.
    private func stopEngine() {
        engine?.stop()
        show(systemPlayer)
    }
    private func replaceItem() {
        guard let url = currentURL else { return }
        clearItemObservers()
        let item = AVPlayerItem(url: url)
        applyQuality(to: item)
        startedImmediately = false; hasVideoFrame = false
        let token = sessionID
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.sessionID == token, self.player.currentItem === item else { return }
                if item.status == .failed { self.recover() }
                if item.status == .readyToPlay {
                    if let start = self.pendingStart {
                        await self.player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                        self.pendingStart = nil
                    }
                    self.startAvailableMedia()
                    self.watchForVideo(on: item, token: token)
                    await self.selectAudio(on: item, token: token)
                }
            }
        }
        bufferObservation = item.observe(\.loadedTimeRanges, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.sessionID == token, self.player.currentItem === item else { return }
                self.startAvailableMedia()
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.sessionID == token, self.player.currentItem === item, !self.isLive else { return }
                self.reachedEnd = true; self.reportProgress()
            }
        }
        failedObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in if self?.sessionID == token, self?.player.currentItem === item { self?.recover() } } }
        stalledObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.playbackStalledNotification, object: item, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in if self?.sessionID == token, self?.player.currentItem === item { self?.waitForStallRecovery() } } }
        player.replaceCurrentItem(with: item); isLoading = wantsPlayback
        if audioReady && wantsPlayback { player.play() }
        updateNowPlaying()
    }
    private func applyQuality(to item: AVPlayerItem? = nil) {
        guard let item = item ?? player.currentItem else { return }
        let preference: StreamQuality = supportsQualityPreference ? quality : .automatic
        item.preferredPeakBitRate = preference.bitRate
        item.preferredMaximumResolution = preference.resolution
    }
    private func startAvailableMedia() {
        guard wantsPlayback, audioReady, !startedImmediately, pendingStart == nil, let item = player.currentItem,
              item.status == .readyToPlay, !item.isPlaybackBufferEmpty,
              item.loadedTimeRanges.contains(where: { $0.timeRangeValue.duration.seconds > 0 }) else { return }
        startedImmediately = true
        bufferObservation = nil
        // Start the first buffered media without waiting for AVPlayer's initial
        // throughput estimate. Keep automatic buffering enabled for later stalls.
        player.playImmediately(atRate: 1)
    }
    func videoDisplayChanged(_ ready: Bool, item: AVPlayerItem?) {
        guard let item, player.currentItem === item else { return }
        hasVideoFrame = ready
        if ready { videoUnavailable = false; videoTask?.cancel(); videoTask = nil }
    }
    private func watchForVideo(on item: AVPlayerItem, token: UUID) {
        guard videoTask == nil, !hasVideoFrame, !videoUnavailable else { return }
        videoTask = Task {
            var audibleSeconds = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard sessionID == token, player.currentItem === item, wantsPlayback else { videoTask = nil; return }
                if hasVideoFrame || item.presentationSize.width > 0 || player.isExternalPlaybackActive { videoTask = nil; return }
                if player.timeControlStatus == .playing { audibleSeconds += 1 }
                guard audibleSeconds >= 8 else { continue }
                videoTask = nil
                if !alternatives.isEmpty {
                    let next = alternatives.removeFirst()
                    let remaining = alternatives
                    let originalPrevious = previous
                    // Replace the old item before opening the next feed. Never
                    // preflight several streams against a one-connection account.
                    player.pause(); player.replaceCurrentItem(with: nil)
                    play(next.channel, url: next.url, title: title, preferredLanguage: preferredLanguage, alternates: remaining)
                    previous = originalPrevious
                    playbackNotice = "Switched to another feed because the first supplied no video."
                } else {
                    videoUnavailable = true
                    playbackNotice = "This feed has audio but no playable video. Choose another stream below."
                }
                return
            }
        }
    }
    private func waitForStallRecovery() {
        guard wantsPlayback, stallTask == nil else { return }
        isLoading = true
        let token = sessionID, item = player.currentItem
        stallTask = Task {
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard sessionID == token, wantsPlayback, player.currentItem === item else { return }
            stallTask = nil
            if player.timeControlStatus != .playing { recover() }
        }
    }
    private func selectAudio(on item: AVPlayerItem, token: UUID) async {
        guard let group = try? await item.asset.loadMediaSelectionGroup(for: .audible), sessionID == token, player.currentItem === item else { return }
        if let option = group.options.first(where: { $0.extendedLanguageTag?.hasPrefix(preferredLanguage) == true || $0.locale?.language.languageCode?.identifier == preferredLanguage }) { item.select(option, in: group) }
    }
    /// A movie or episode that hasn't started after 30 s won't: say so
    /// instead of showing "Connecting…" indefinitely.
    private func watchStart() {
        let token = sessionID
        // Reading a file's index over the network takes the engine longer.
        let limit = usesEngine ? 90 : 30
        startTimeout = Task {
            do { try await Task.sleep(for: .seconds(limit)) } catch { return }
            guard sessionID == token, wantsPlayback, !isLive, !isPlaying else { return }
            fail("This title didn’t start. Your provider may not be sending it right now; try again later or choose another title.")
        }
    }
    private func fail(_ message: String) {
        wantsPlayback = false; isLoading = false; isPlaying = false
        retryTask?.cancel(); retryTask = nil
        if usesEngine {
            reportProgress()
            // Try Again picks up where it stopped.
            if pendingStart == nil, let position = engine?.currentTime, position > 0 { pendingStart = position }
            preparationTask?.cancel(); preparationTask = nil
            stopEngine()
        }
        player.pause()
        errorMessage = message; onFailure?()
    }
    /// Network trouble is worth retrying; a file the player can't read isn't.
    private func isNetworkFailure(_ error: Error?) -> Bool {
        var current = error as NSError?
        for _ in 0..<8 {
            guard let error = current else { return false }
            if error.domain == NSURLErrorDomain { return true }
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
    private func recover() {
        guard wantsPlayback, retryTask == nil, currentURL != nil else { return }
        let failure = PlaybackFailure(error: player.currentItem?.error)
        if !isLive, failure.httpStatus == nil, !isNetworkFailure(player.currentItem?.error) { fail(failure.message); return }
        guard failure.shouldRetry, attempts < 3 else {
            wantsPlayback = false; isLoading = false; isPlaying = false
            player.pause()
            errorMessage = failure.message; onFailure?(); return
        }
        isLoading = true
        // Movies and episodes reconnect where they were.
        if !isLive, pendingStart == nil, player.currentTime().seconds.isFinite, player.currentTime().seconds > 0 { pendingStart = player.currentTime().seconds }
        attempts += 1; let token = sessionID; let delay = attempts * 2
        retryTask = Task {
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled, sessionID == token, wantsPlayback else { return }
            retryTask = nil; replaceItem()
        }
    }
    func retry() {
        cancelPending(); attempts = 0; errorMessage = nil; videoUnavailable = false; playbackNotice = nil; wantsPlayback = true
        if !isLive { watchStart() }
        preparePlayback()
    }
    func toggle() { isPlaying ? pause() : resume() }
    func pause() {
        reportProgress()
        wantsPlayback = false
        retryTask?.cancel(); retryTask = nil; stallTask?.cancel(); stallTask = nil
        videoTask?.cancel(); videoTask = nil
        if usesEngine { engine?.pause() } else { player.pause() }
        isPlaying = false; isLoading = false; updateNowPlaying()
    }
    func resume() {
        guard currentURL != nil else { return }
        wantsPlayback = true
        if usesEngine {
            // A failed or finished session can't be revived; it is loaded again.
            if errorMessage != nil || reachedEnd || engine?.state == .idle { reachedEnd = false; if preparationTask == nil { retry() } }
            else { engine?.play() }
            updateNowPlaying(); return
        }
        if player.currentItem?.status == .failed { retry(); return }
        if audioReady { player.play(); startAvailableMedia(); if let item = player.currentItem { watchForVideo(on: item, token: sessionID) } }
        else if preparationTask == nil { preparePlayback() }
        updateNowPlaying()
    }
    func stop() {
        reportProgress()
        cancelPending(); clearItemObservers(); stopEngine(); player.replaceCurrentItem(with: nil)
        channel = nil; currentURL = nil; isPlaying = false; isLoading = false; hasVideoFrame = false; wantsPlayback = false; audioReady = false; errorMessage = nil
        alternatives = []; playbackNotice = nil; videoUnavailable = false; isLive = true; pendingStart = nil; reachedEnd = false
        if !secondary { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
    }
    private func cancelPending() { sessionID = UUID(); startTimeout?.cancel(); startTimeout = nil; retryTask?.cancel(); retryTask = nil; preparationTask?.cancel(); preparationTask = nil; stallTask?.cancel(); stallTask = nil; videoTask?.cancel(); videoTask = nil }
    private func clearItemObservers() {
        videoTask?.cancel(); videoTask = nil
        itemObservation = nil
        bufferObservation = nil
        if let failedObserver { NotificationCenter.default.removeObserver(failedObserver) }
        if let stalledObserver { NotificationCenter.default.removeObserver(stalledObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        failedObserver = nil; stalledObserver = nil; endObserver = nil
    }
    private func updateNowPlaying() {
        guard !secondary, let channel else { return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: title ?? channel.name,
            MPMediaItemPropertyArtist: channel.name, MPNowPlayingInfoPropertyIsLiveStream: isLive,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0]
        if usesEngine, let engine, engine.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = engine.duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = engine.currentTime
        } else if !isLive, let item = player.currentItem, item.duration.seconds.isFinite {
            info[MPMediaItemPropertyPlaybackDuration] = item.duration.seconds
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime().seconds
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    /// Reports where a movie or episode is, for resume.
    func reportProgress(final: Bool = true) {
        if usesEngine {
            // The engine's clock is the file's own timeline, whatever its player is showing.
            guard channel != nil, pendingStart == nil, let engine, engine.duration > 0 else { return }
            onProgress?(reachedEnd ? engine.duration : engine.currentTime, engine.duration, final)
            return
        }
        guard !isLive, channel != nil, pendingStart == nil, let item = player.currentItem, item.status == .readyToPlay else { return }
        let duration = item.duration.seconds, position = reachedEnd ? duration : player.currentTime().seconds
        guard duration.isFinite, duration > 0, position.isFinite else { return }
        onProgress?(position, duration, final)
    }
}

/// Audio routing can block. Serialize activation away from the UI thread.
actor PlaybackAudioSession {
    static let shared = PlaybackAudioSession()
    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        // Playback already supports AirPlay. Explicit allowAirPlay is only valid
        // for the play-and-record category and causes an invalid-parameter error here.
        if session.category != .playback || session.mode != .moviePlayback {
            try session.setCategory(.playback, mode: .moviePlayback)
        }
        try session.setActive(true)
    }
}

struct NativePlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    var controls = true
    var pictureInPicture = true
    var onDisplayChange: ((Bool, AVPlayerItem?) -> Void)?
    var onPictureInPicture: ((Bool) -> Void)?
    /// Taps on the video, alongside the player's own show/hide controls.
    var onTap: (() -> Void)?
    /// Shown over the system full-screen player, which has no public slot for
    /// custom controls on iPhone: bottom right in portrait, top center in landscape.
    var fullScreenAccessory: AnyView?
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player; controller.showsPlaybackControls = controls
        controller.allowsPictureInPicturePlayback = pictureInPicture
        controller.canStartPictureInPictureAutomaticallyFromInline = pictureInPicture
        context.coordinator.onDisplayChange = onDisplayChange
        context.coordinator.onPictureInPicture = onPictureInPicture
        context.coordinator.onTap = onTap
        context.coordinator.accessory = fullScreenAccessory
        controller.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.cancelsTouchesInView = false; tap.delegate = context.coordinator
        controller.view.addGestureRecognizer(tap)
        context.coordinator.observation = controller.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak coordinator = context.coordinator] controller, _ in
            Task { @MainActor [weak coordinator, weak controller] in
                guard let controller else { return }
                coordinator?.onDisplayChange?(controller.isReadyForDisplay, controller.player?.currentItem)
            }
        }
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        controller.showsPlaybackControls = controls
        context.coordinator.onDisplayChange = onDisplayChange
        context.coordinator.onPictureInPicture = onPictureInPicture
        context.coordinator.onTap = onTap
        context.coordinator.accessory = fullScreenAccessory
    }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.observation = nil; coordinator.onDisplayChange = nil; coordinator.onPictureInPicture = nil; coordinator.onTap = nil
        coordinator.detach(); controller.delegate = nil; controller.player = nil
    }
    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate, AVPlayerViewControllerDelegate {
        var observation: NSKeyValueObservation?
        var onDisplayChange: ((Bool, AVPlayerItem?) -> Void)?
        var onPictureInPicture: ((Bool) -> Void)?
        var onTap: (() -> Void)?
        var accessory: AnyView?
        private var host: UIHostingController<AnyView>?
        private var hostTap: UITapGestureRecognizer?
        private var placement: [NSLayoutConstraint] = []

        @objc func tapped() { onTap?() }
        func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) { onPictureInPicture?(true) }
        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) { onPictureInPicture?(false) }
        func playerViewController(_ playerViewController: AVPlayerViewController, failedToStartPictureInPictureWithError error: Error) { onPictureInPicture?(false) }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        func playerViewController(_ playerViewController: AVPlayerViewController, willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            coordinator.animate(alongsideTransition: nil) { [weak self, weak playerViewController] context in
                guard !context.isCancelled, let self, let window = playerViewController?.viewIfLoaded?.window else { return }
                self.attach(in: window)
            }
        }
        func playerViewController(_ playerViewController: AVPlayerViewController, willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) { detach() }

        /// Puts the accessory over the topmost presented controller: the
        /// system's full-screen player.
        private func attach(in window: UIWindow) {
            guard let accessory, host == nil else { return }
            var top = window.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            guard let top else { return }
            let host = UIHostingController(rootView: accessory)
            host.sizingOptions = .intrinsicContentSize
            host.view.backgroundColor = .clear
            host.view.translatesAutoresizingMaskIntoConstraints = false
            top.addChild(host); top.view.addSubview(host.view); host.didMove(toParent: top)
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.cancelsTouchesInView = false; tap.delegate = self
            top.view.addGestureRecognizer(tap)
            self.host = host; hostTap = tap
            place(in: top.view)
            host.view.registerForTraitChanges([UITraitVerticalSizeClass.self]) { [weak self] (_: UIView, _: UITraitCollection) in
                guard let self, let container = self.host?.view.superview else { return }
                self.place(in: container)
            }
            onTap?()
        }
        private func place(in container: UIView) {
            guard let view = host?.view else { return }
            NSLayoutConstraint.deactivate(placement)
            let guide = container.safeAreaLayoutGuide
            placement = container.traitCollection.verticalSizeClass == .compact
                ? [view.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8), view.centerXAnchor.constraint(equalTo: guide.centerXAnchor)]
                : [view.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16), view.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16)]
            NSLayoutConstraint.activate(placement)
        }
        func detach() {
            if let hostTap { hostTap.view?.removeGestureRecognizer(hostTap) }
            host?.willMove(toParent: nil); host?.view.removeFromSuperview(); host?.removeFromParent()
            host = nil; hostTap = nil; placement = []
        }
    }
}

/// A bare video surface for the mini player: no controls and no Picture in
/// Picture, so it never competes with the full player for them.
struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> LayerView { let view = LayerView(); view.playerLayer.player = player; view.playerLayer.videoGravity = .resizeAspectFill; return view }
    func updateUIView(_ view: LayerView, context: Context) { if view.playerLayer.player !== player { view.playerLayer.player = player } }
    static func dismantleUIView(_ view: LayerView, coordinator: ()) { view.playerLayer.player = nil }
    final class LayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
