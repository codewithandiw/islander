import SwiftUI

struct FocusTabView: View {
    @EnvironmentObject private var activity: ActivityTracker
    @EnvironmentObject private var reminders: ReminderScheduler
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let goal = TimeInterval(max(settings.dailyGoalHours, 1) * 3600)

        HStack(alignment: .center, spacing: 22) {
            FocusRing(progress: activity.todayActive / goal, isActive: activity.isActive)
                .frame(width: 100, height: 100)
                .overlay {
                    VStack(spacing: 0) {
                        Text(Format.duration(activity.todayActive))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Text("of \(settings.dailyGoalHours)h")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

            VStack(alignment: .leading, spacing: 7) {
                Text("Focus today")
                    .font(.system(size: 15, weight: .semibold))
                stat("sunrise.fill", activity.firstActiveToday.map { "Started \(Format.time($0))" } ?? "Not started yet")
                stat("hourglass", "\(Format.duration(activity.sinceLastBreak)) since last break")
                stat(activity.isActive ? "circle.fill" : "moon.zzz.fill", activity.isActive ? "Working now" : "Away")
                WeekBars(history: activity.history(days: 7), goal: goal)
                    .frame(width: 150, height: 22)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Next reminders")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    if settings.playReminderSound {
                        Button {
                            settings.focusReminderSound.play()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "speaker.wave.2.fill")
                                Text(settings.focusReminderSound.displayName)
                            }
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .help("Preview \(settings.focusReminderSound.displayName) sound")
                    }
                }
                ForEach(ReminderKind.allCases) { kind in
                    HStack(spacing: 8) {
                        Image(systemName: kind.symbol)
                            .frame(width: 16)
                            .foregroundStyle(.cyan)
                        Text(kind.title)
                        Spacer(minLength: 6)
                        Text(reminders.remaining(for: kind).map { "in \(Format.duration(max($0, 60)))" } ?? "Off")
                            .foregroundStyle(.white.opacity(0.55))
                            .monospacedDigit()
                    }
                    .font(.system(size: 12))
                }
                Button("I took a break") { activity.takeBreakNow() }
                    .buttonStyle(IslandButtonStyle())
                    .padding(.top, 2)
            }
            .frame(width: 190)
        }
        .frame(maxHeight: .infinity)
    }

    private func stat(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .frame(width: 14)
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.7))
        .lineLimit(1)
    }
}

private struct FocusRing: View {
    let progress: Double
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 9)
            Circle()
                .trim(from: 0, to: min(max(progress, 0.001), 1))
                .stroke(
                    AngularGradient(colors: [.cyan, .mint, .green, .cyan], center: .center),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
        }
        .opacity(isActive ? 1 : 0.7)
    }
}

/// Seven small bars, one per day, today on the right.
private struct WeekBars: View {
    let history: [(date: Date, seconds: TimeInterval)]
    let goal: TimeInterval

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(history.enumerated()), id: \.offset) { index, day in
                VStack(spacing: 2) {
                    GeometryReader { geo in
                        let ratio = min(day.seconds / goal, 1)
                        VStack {
                            Spacer(minLength: 0)
                            Capsule()
                                .fill(index == history.count - 1 ? Color.cyan : Color.white.opacity(0.35))
                                .frame(height: max(geo.size.height * ratio, 2))
                        }
                    }
                }
                .help("\(day.date.formatted(.dateTime.weekday(.wide))): \(Format.duration(day.seconds))")
            }
        }
    }
}

struct ReminderCard: View {
    @EnvironmentObject private var reminders: ReminderScheduler
    @EnvironmentObject private var activity: ActivityTracker
    @EnvironmentObject private var settings: AppSettings

    let alert: ReminderAlert

    var body: some View {
        HStack(spacing: 20) {
            MascotView(mood: .shock, color: settings.mascotColor.color, energy: 0, size: 78)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ForEach(alert.kinds) { kind in
                        Image(systemName: kind.symbol).foregroundStyle(.cyan)
                    }
                    Text(alert.kinds.map(\.title).joined(separator: " · "))
                        .font(.system(size: 16, weight: .bold))
                }
                ForEach(alert.kinds) { kind in
                    Text(kind.message)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                }
                Text("You have been working for \(Format.duration(activity.sinceLastBreak)).")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Button("Done") { reminders.complete() }
                    .buttonStyle(IslandButtonStyle(prominent: true))
                Button("Snooze 10 min") { reminders.snooze() }
                    .buttonStyle(IslandButtonStyle())
            }
        }
        .frame(maxHeight: .infinity)
    }
}
