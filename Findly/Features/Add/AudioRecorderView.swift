import SwiftUI
import AVFoundation

struct AudioRecorderView: View {
    var onResult: (Data) -> Void
    var onCancel: () -> Void

    // Recording
    @State private var recorder: AVAudioRecorder?
    @State private var isRecording = false
    @State private var recordingTimer: Timer?
    @State private var meterLevels: [Float] = Array(repeating: 0, count: 7)
    @State private var permissionDenied = false
    @State private var hasStopped = false
    @State private var tempURL: URL?
    @State private var recordedDuration: TimeInterval = 0

    // Playback
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var playbackTime: TimeInterval = 0
    @State private var playbackTimer: Timer?

    // Displayed time: recording time while recording, playback position while playing, total otherwise
    private var displayTime: TimeInterval {
        if isRecording { return recordedDuration }
        if isPlaying   { return playbackTime }
        return recordedDuration
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                if permissionDenied {
                    permissionDeniedView
                } else {
                    timerLabel
                        .padding(.bottom, AppTheme.Spacing.xLarge)

                    waveformView
                        .padding(.bottom, AppTheme.Spacing.xLarge)

                    if hasStopped {
                        scrubBar
                            .padding(.horizontal, AppTheme.Spacing.xLarge)
                            .padding(.bottom, AppTheme.Spacing.xLarge)
                    }

                    controlButtons
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(AppTheme.Colors.groupedBG)
            .navigationTitle("Record Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        stopAndCleanUp()
                        onCancel()
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var timerLabel: some View {
        Text(formatTime(displayTime))
            .font(.system(size: 56, weight: .thin, design: .monospaced))
            .foregroundStyle(
                isRecording ? Color.red :
                isPlaying   ? FileType.audio.tintColor :
                              AppTheme.Colors.label
            )
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.1), value: displayTime)
    }

    private var waveformView: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        isRecording ? Color.red :
                        isPlaying   ? FileType.audio.tintColor :
                                      FileType.audio.tintColor.opacity(0.35)
                    )
                    .frame(width: 6, height: barHeight(index: i))
                    .animation(.easeInOut(duration: 0.05), value: meterLevels[i])
            }
        }
        .frame(height: 60)
    }

    /// Scrub bar shown in review state.
    private var scrubBar: some View {
        Slider(
            value: Binding(
                get: { recordedDuration > 0 ? playbackTime / recordedDuration : 0 },
                set: { fraction in
                    let target = fraction * recordedDuration
                    playbackTime = target
                    player?.currentTime = target
                }
            ),
            in: 0...1
        )
        .tint(FileType.audio.tintColor)
        .disabled(recordedDuration == 0)
    }

    private var controlButtons: some View {
        Group {
            if hasStopped {
                reviewControls
            } else {
                recordingControl
            }
        }
    }

    /// Record / stop button shown while recording (or before first recording).
    private var recordingControl: some View {
        Button(action: toggleRecording) {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red : FileType.audio.tintColor)
                    .frame(width: 72, height: 72)
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .animation(.spring(response: 0.3), value: isRecording)
    }

    /// Review controls: re-record | play/pause | save.
    private var reviewControls: some View {
        HStack(spacing: AppTheme.Spacing.xLarge) {
            // Re-record
            Button(action: reRecord) {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    Text("Re-record")
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                }
            }
            .buttonStyle(.plain)

            // Play / Pause
            Button(action: togglePlayback) {
                ZStack {
                    Circle()
                        .fill(FileType.audio.tintColor)
                        .frame(width: 72, height: 72)
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .animation(.spring(response: 0.3), value: isPlaying)

            // Save
            Button(action: saveRecording) {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(FileType.audio.tintColor)
                    Text("Save")
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                }
            }
            .buttonStyle(.plain)
        }
        .transition(.scale.combined(with: .opacity))
    }

    private var permissionDeniedView: some View {
        VStack(spacing: AppTheme.Spacing.base) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.Colors.tertiaryLabel)
            Text("Microphone Access Required")
                .font(AppTheme.Typography.headline)
            Text("Findly needs microphone access to record audio. Please enable it in Settings.")
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.Spacing.xLarge)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(FileType.audio.tintColor)
        }
    }

    // MARK: - Recording

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        Task {
            let granted = await requestMicrophonePermission()
            guard granted else {
                await MainActor.run { permissionDenied = true }
                return
            }
            await MainActor.run { beginRecordingSession() }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func beginRecordingSession() {
        stopPlayback()

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .default)
        try? session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        guard let rec = try? AVAudioRecorder(url: url, settings: settings) else { return }
        rec.isMeteringEnabled = true
        rec.record()
        recorder = rec
        tempURL = url
        isRecording = true
        hasStopped = false
        recordedDuration = 0
        playbackTime = 0

        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            rec.updateMeters()
            let power = rec.averagePower(forChannel: 0)
            let normalized = max(0, min(1, (power + 60) / 60))
            let updated = generateMeterLevels(normalized: normalized)
            DispatchQueue.main.async {
                recordedDuration = rec.currentTime
                meterLevels = updated
            }
        }
    }

    private func stopRecording() {
        let duration = recorder?.currentTime ?? recordedDuration  // capture before stop() resets it to 0
        recorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        hasStopped = true
        recordedDuration = duration
        meterLevels = Array(repeating: 0, count: 7)
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func reRecord() {
        stopPlayback()
        if let url = tempURL {
            try? FileManager.default.removeItem(at: url)
            tempURL = nil
        }
        hasStopped = false
        recordedDuration = 0
        playbackTime = 0
        startRecording()
    }

    // MARK: - Playback

    private func togglePlayback() {
        if isPlaying { pausePlayback() } else { startPlayback() }
    }

    private func startPlayback() {
        guard let url = tempURL else { return }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)

        if player == nil || player?.url != url {
            player = try? AVAudioPlayer(contentsOf: url)
            // Use the player's duration as the authoritative length (recorder.currentTime
            // after stop() returns 0, so recordedDuration may still be slightly off)
            if let d = player?.duration, d > 0 { recordedDuration = d }
            player?.currentTime = playbackTime
        }
        guard let p = player else { return }
        p.currentTime = playbackTime
        p.play()
        isPlaying = true

        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            DispatchQueue.main.async {
                if p.isPlaying {
                    playbackTime = p.currentTime
                } else {
                    // Reached end naturally
                    playbackTime = 0
                    isPlaying = false
                    playbackTimer?.invalidate()
                    playbackTimer = nil
                    try? AVAudioSession.sharedInstance().setActive(false)
                }
            }
        }
    }

    private func pausePlayback() {
        player?.pause()
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        playbackTime = 0
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    // MARK: - Save / cleanup

    private func saveRecording() {
        stopPlayback()
        guard let url = tempURL,
              let data = try? Data(contentsOf: url) else { return }
        try? FileManager.default.removeItem(at: url)
        tempURL = nil
        onResult(data)
    }

    private func stopAndCleanUp() {
        recorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        stopPlayback()
        if let url = tempURL {
            try? FileManager.default.removeItem(at: url)
            tempURL = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: - Helpers

    private func formatTime(_ t: TimeInterval) -> String {
        let mins = Int(t) / 60
        let secs = Int(t) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func barHeight(index: Int) -> CGFloat {
        8 + CGFloat(meterLevels[index]) * 52
    }

    private func generateMeterLevels(normalized: Float) -> [Float] {
        (0..<7).map { _ in
            let jitter = Float.random(in: -0.15...0.15)
            return max(0, min(1, normalized + jitter))
        }
    }
}
