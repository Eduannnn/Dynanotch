import SwiftUI
import NotchCore

/// Presentation only. Timer creation lives in the application's Settings window.
struct TimerActivityView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var timer: TimerService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.cameraHeight)
            if timer.exists { countdown.padding(.top, 12) }
            Spacer(minLength: 12)
        }.padding(.horizontal, 20)
    }
    private var countdown: some View {
        VStack(spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timer.state.phase == .finished ? "Time’s up" : timer.state.phase == .paused ? "Paused" : "Timer")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.orange)
                    Text(timer.state.phase == .finished ? "00:00" : timer.displayTime)
                        .font(.system(size: 39, weight: .medium, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: timer.displayTime)
                }
                Spacer()
                ZStack {
                    Circle().stroke(.orange.opacity(0.16), lineWidth: 4)
                    Circle().trim(from: 0, to: timer.progress).stroke(.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: timer.state.phase == .finished ? "checkmark" : "timer").font(.system(size: 22)).foregroundStyle(.orange)
                }.frame(width: 49, height: 49).accessibilityHidden(true)
            }
            HStack(spacing: 10) {
                Button { timer.cancel(); model.close() } label: {
                    Label(timer.state.phase == .finished ? "Dismiss" : "Cancel", systemImage: "xmark")
                        .frame(maxWidth: .infinity).padding(.vertical, 10).background(.white.opacity(0.1), in: Capsule())
                }
                Button {
                    if timer.state.phase == .finished { timer.restart() } else { timer.togglePause() }
                } label: {
                    Label(timer.state.phase == .finished ? "Repeat" : timer.state.phase == .paused ? "Resume" : "Pause",
                          systemImage: timer.state.phase == .finished ? "arrow.clockwise" : timer.state.phase == .paused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 10).background(.orange.opacity(0.23), in: Capsule()).foregroundStyle(.orange)
                }
            }.font(.system(size: 12, weight: .semibold)).buttonStyle(.plain)
        }
    }
}


/// This editor is hosted in Settings, never in the notch.
struct TimerSetupView: View {
    @ObservedObject var model: NotchModel
    @State private var minutes = 5
    @State private var seconds = 0
    var body: some View { composer }
    private var composer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "timer").foregroundStyle(.orange)
                Text("New timer").font(.system(size: 13, weight: .medium))
                Spacer()
                Text("MIN : SEC").font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                DurationField(value: $minutes, range: 0...180, label: "minutes")
                Text(":").font(.system(size: 26)).foregroundStyle(.secondary)
                DurationField(value: $seconds, range: 0...59, label: "seconds")
            }
            HStack(spacing: 7) {
                ForEach([1, 5, 15, 25], id: \.self) { value in
                    Button("\(value)m") { minutes = value; seconds = 0 }
                        .font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity)
                        .padding(.vertical, 6).background(.white.opacity(0.08), in: Capsule())
                }
                Button("30s") { minutes = 0; seconds = 30 }
                    .font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity)
                    .padding(.vertical, 6).background(.white.opacity(0.08), in: Capsule())
            }
            Button { model.startTimer(seconds: Double(minutes * 60 + seconds)) } label: {
                Label("Start timer", systemImage: "play.fill").font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(.orange, in: Capsule()).foregroundStyle(.black)
            }.disabled(minutes == 0 && seconds == 0)
        }.buttonStyle(.plain)
    }
}

private struct DurationField: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var label: String
    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", value))
                .font(.system(size: 29, weight: .medium, design: .rounded)).monospacedDigit()
                .frame(minWidth: 52)
                .accessibilityLabel("\(value) \(label)")
            VStack(spacing: 3) {
                Button { value = min(range.upperBound, value + 1) } label: {
                    Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold)).frame(width: 30, height: 18)
                }.accessibilityLabel("Increase \(label)")
                Button { value = max(range.lowerBound, value - 1) } label: {
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).frame(width: 30, height: 18)
                }.accessibilityLabel("Decrease \(label)")
            }.foregroundStyle(.white.opacity(0.75))
        }.frame(width: 130, height: 44).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}
