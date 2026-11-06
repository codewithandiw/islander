import Combine
import SwiftUI

public struct ReminderTabView: View {
    @EnvironmentObject private var eventReminders: EventReminderStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.isSnapshot) private var isSnapshot

    @State private var filter: ReminderFilter = .upcoming
    @State private var editingReminder: EventReminder? = nil
    @State private var isCreatingNew = false
    @State private var selectedReminderId: UUID? = nil

    private enum ReminderFilter: String, CaseIterable {
        case upcoming = "Upcoming"
        case completed = "Done"
    }

    public init(initialCreatingNew: Bool = false) {
        _isCreatingNew = State(initialValue: initialCreatingNew)
    }

    /// The form needs the whole island width; the list hides while it is open.
    private var isFormOpen: Bool { isCreatingNew || editingReminder != nil }

    public var body: some View {
        HStack(spacing: 12) {
            // Left Column: List & Header
            if !isFormOpen {
            VStack(alignment: .leading, spacing: 8) {
                listHeader

                let filtered = filteredReminders
                if filtered.isEmpty {
                    emptyListView
                } else {
                    if isSnapshot {
                        reminderRows(filtered)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            reminderRows(filtered)
                                .padding(.vertical, 2)
                        }
                    }
                }
            }
            .frame(width: 240)
            .transition(.move(edge: .leading).combined(with: .opacity))

            Divider()
                .background(Color.white.opacity(0.12))
            }

            // Right Column: Editor or Hero / Next Up View
            VStack(alignment: .leading, spacing: 0) {
                if isCreatingNew {
                    ReminderFormView(
                        initial: nil,
                        onSave: { newReminder in
                            eventReminders.add(
                                title: newReminder.title,
                                notes: newReminder.notes,
                                dueDate: newReminder.dueDate,
                                repeatSchedule: newReminder.repeatSchedule,
                                sound: newReminder.sound,
                                leadTime: newReminder.leadTime
                            )
                            isCreatingNew = false
                        },
                        onCancel: {
                            isCreatingNew = false
                        }
                    )
                    .transition(.blurReplace)
                } else if let editing = editingReminder {
                    ReminderFormView(
                        initial: editing,
                        onSave: { updated in
                            eventReminders.update(updated)
                            editingReminder = nil
                        },
                        onCancel: {
                            editingReminder = nil
                        },
                        onDelete: {
                            eventReminders.delete(id: editing.id)
                            editingReminder = nil
                        }
                    )
                    .transition(.blurReplace)
                } else {
                    heroDetailView
                        .transition(.blurReplace)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isCreatingNew)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: editingReminder?.id)
        .animation(.smooth(duration: 0.25), value: filter)
    }

    // MARK: - Left List Components

    private var listHeader: some View {
        HStack(spacing: 5) {
            Text("Reminders")
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .fixedSize()

            let count = eventReminders.reminders.filter { !$0.isCompleted }.count
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .bold))
                    .padding(.horizontal, 4.5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange.opacity(0.85)))
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 2)

            // Filter pills
            HStack(spacing: 2) {
                ForEach(ReminderFilter.allCases, id: \.self) { item in
                    Button {
                        filter = item
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 9.5, weight: filter == item ? .semibold : .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule().fill(filter == item ? Color.white.opacity(0.2) : Color.clear)
                            )
                            .foregroundStyle(filter == item ? .white : .white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(1.5)
            .background(Capsule().fill(Color.white.opacity(0.06)))

            // Add button
            Button {
                editingReminder = nil
                isCreatingNew = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.orange))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .help("New reminder")
        }
    }

    private var filteredReminders: [EventReminder] {
        switch filter {
        case .upcoming:
            return eventReminders.reminders.filter { !$0.isCompleted }
        case .completed:
            return eventReminders.reminders.filter { $0.isCompleted }
        }
    }

    private func reminderRows(_ items: [EventReminder]) -> some View {
        VStack(spacing: 6) {
            ForEach(items) { item in
                ReminderRowCard(
                    reminder: item,
                    isSelected: (editingReminder?.id == item.id) || (selectedReminderId == item.id),
                    onToggle: {
                        eventReminders.toggleCompleted(id: item.id)
                    },
                    onSelect: {
                        selectedReminderId = item.id
                        if isCreatingNew { isCreatingNew = false }
                        editingReminder = item
                    },
                    onDelete: {
                        eventReminders.delete(id: item.id)
                        if editingReminder?.id == item.id {
                            editingReminder = nil
                        }
                    }
                )
            }
        }
    }

    private var emptyListView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: filter == .upcoming ? "bell.slash" : "checkmark.circle")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.3))
            Text(filter == .upcoming ? "No upcoming reminders" : "No completed reminders")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            if filter == .upcoming {
                Button("Add Reminder") {
                    isCreatingNew = true
                }
                .buttonStyle(IslandButtonStyle(prominent: true, tint: .orange))
                .padding(.top, 2)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Right Hero View

    private var heroDetailView: some View {
        let upcoming = eventReminders.reminders.first(where: { !$0.isCompleted })

        return Group {
            if let reminder = upcoming {
                HeroReminderCard(
                    reminder: reminder,
                    onEdit: {
                        editingReminder = reminder
                    },
                    onDone: {
                        eventReminders.toggleCompleted(id: reminder.id)
                    },
                    onNew: {
                        isCreatingNew = true
                    },
                    onTestAlert: {
                        eventReminders.triggerTestAlert(for: reminder.id)
                    }
                )
            } else {
                VStack(spacing: 10) {
                    Spacer()
                    if settings.showMascot {
                        DancingMascot(mood: .idle, size: 52)
                    } else {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(.orange)
                    }
                    Text("All Caught Up!")
                        .font(.system(size: 14, weight: .bold))
                    Text("Set one-time or repeating reminders with ringtones that approach your notch.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    Button("Create a Reminder") {
                        isCreatingNew = true
                    }
                    .buttonStyle(IslandButtonStyle(prominent: true, tint: .orange))
                    .padding(.top, 4)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Reminder Row Card

private struct ReminderRowCard: View {
    let reminder: EventReminder
    let isSelected: Bool
    let onToggle: () -> Void
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 9) {
            // Checkmark button
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(reminder.isCompleted ? Color.green : Color.white.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                    if reminder.isCompleted {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 16, height: 16)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
            }
            .buttonStyle(.plain)

            // Title & Time info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(reminder.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(reminder.isCompleted ? .white.opacity(0.4) : .white)
                        .strikethrough(reminder.isCompleted)
                        .lineLimit(1)

                    if reminder.repeatSchedule != .never {
                        Image(systemName: reminder.repeatSchedule.symbol)
                            .font(.system(size: 9))
                            .foregroundStyle(.cyan)
                            .help(reminder.repeatSchedule.title)
                    }
                }

                HStack(spacing: 5) {
                    Text(timeLabel)
                        .font(.system(size: 9.5))
                        .foregroundStyle(statusColor)

                    if reminder.isApproaching() {
                        HStack(spacing: 2) {
                            Circle().fill(Color.orange).frame(width: 4, height: 4)
                            Text("Approaching")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(.orange)
                        }
                    }

                    Spacer(minLength: 0)

                    // Sound icon
                    HStack(spacing: 2) {
                        Image(systemName: "speaker.wave.1.fill")
                            .font(.system(size: 8))
                        Text(reminder.sound.displayName)
                            .font(.system(size: 8.5))
                    }
                    .foregroundStyle(.white.opacity(0.4))
                }
            }

            // Edit / delete action on hover
            if isHovering {
                HStack(spacing: 4) {
                    Button(action: onSelect) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.red.opacity(0.25)))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.orange.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }

    private var cardBackground: Color {
        if reminder.isApproaching() {
            return Color.orange.opacity(0.12)
        }
        if isSelected {
            return Color.white.opacity(0.14)
        }
        return isHovering ? Color.white.opacity(0.09) : Color.white.opacity(0.04)
    }

    private var statusColor: Color {
        if reminder.isCompleted { return .white.opacity(0.35) }
        if reminder.isDue() { return .red }
        if reminder.isApproaching() { return .orange }
        return .white.opacity(0.6)
    }

    private var timeLabel: String {
        let calendar = Calendar.current
        let target = reminder.effectiveTargetDate
        let now = Date()

        if reminder.isCompleted {
            return "Completed"
        }
        if reminder.isDue(at: now) {
            return "Due now"
        }

        let diff = target.timeIntervalSince(now)
        if diff < 3600 {
            let mins = max(1, Int(diff / 60))
            return "in \(mins)m"
        }

        if calendar.isDateInToday(target) {
            return "Today \(target.formatted(date: .omitted, time: .shortened))"
        } else if calendar.isDateInTomorrow(target) {
            return "Tomorrow \(target.formatted(date: .omitted, time: .shortened))"
        } else {
            return target.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
    }
}

// MARK: - Hero Reminder Card

private struct HeroReminderCard: View {
    let reminder: EventReminder
    let onEdit: () -> Void
    let onDone: () -> Void
    let onNew: () -> Void
    let onTestAlert: () -> Void

    @State private var now = Date()
    private let ticker = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header tag
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: reminder.isApproaching(at: now) ? "bell.badge.fill" : "alarm.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(reminder.isApproaching(at: now) ? .orange : .cyan)
                    Text(reminder.isApproaching(at: now) ? "APPROACHING SOON" : "NEXT REMINDER")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(reminder.isApproaching(at: now) ? .orange : .white.opacity(0.7))
                }

                Spacer()

                Button(action: onTestAlert) {
                    HStack(spacing: 3) {
                        Image(systemName: "bell.and.waves.left.and.right")
                        Text("Simulate Ring")
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Test this reminder's ringtone and dynamic island banner")
            }

            // Big countdown
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(countdownString)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(reminder.isApproaching(at: now) ? .orange : .white)
                    .monospacedDigit()
                Text(countdownSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
            }

            // Title & Notes
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if !reminder.notes.isEmpty {
                    Text(reminder.notes)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                }
            }

            // Badges row
            HStack(spacing: 5) {
                badge(reminder.repeatSchedule.symbol, reminder.repeatSchedule.title, tint: .cyan)
                badge("speaker.wave.2.fill", reminder.sound.displayName, tint: .yellow)
                if reminder.leadTime != .atTime {
                    badge("bell.fill", reminder.leadTime.title, tint: .orange)
                }
            }

            Spacer(minLength: 2)

            // Quick actions
            HStack(spacing: 8) {
                Button("Done") {
                    onDone()
                }
                .buttonStyle(IslandButtonStyle(prominent: true, tint: .green))

                Button("Edit") {
                    onEdit()
                }
                .buttonStyle(IslandButtonStyle())

                Spacer()

                Button("+ New") {
                    onNew()
                }
                .buttonStyle(IslandButtonStyle(prominent: false))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(reminder.isApproaching(at: now) ? Color.orange.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
        )
        .onReceive(ticker) { now = $0 }
    }

    private func badge(_ icon: String, _ text: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(tint.opacity(0.12)))
    }

    private var countdownString: String {
        let diff = reminder.effectiveTargetDate.timeIntervalSince(now)
        if diff <= 0 { return "00:00:00" }

        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        let seconds = Int(diff) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private var countdownSubtitle: String {
        let diff = reminder.effectiveTargetDate.timeIntervalSince(now)
        if diff <= 0 { return "due right now" }
        if diff < 3600 { return "minutes remaining" }
        return "until notification"
    }
}

// MARK: - Reminder Form / Editor View

private struct ReminderFormView: View {
    @Environment(\.isSnapshot) private var isSnapshot

    let initial: EventReminder?
    let onSave: (EventReminder) -> Void
    let onCancel: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var title: String
    @State private var notes: String
    @State private var dueDate: Date
    @State private var repeatSchedule: EventReminderRepeat
    @State private var sound: EventReminderSound
    @State private var leadTime: EventReminderLeadTime

    init(
        initial: EventReminder?,
        onSave: @escaping (EventReminder) -> Void,
        onCancel: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.initial = initial
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete

        _title = State(initialValue: initial?.title ?? "")
        _notes = State(initialValue: initial?.notes ?? "")
        _dueDate = State(initialValue: initial?.dueDate ?? Date().addingTimeInterval(1800))
        _repeatSchedule = State(initialValue: initial?.repeatSchedule ?? .never)
        _sound = State(initialValue: initial?.sound ?? .amongUs)
        _leadTime = State(initialValue: initial?.leadTime ?? .min5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Form Header
            HStack {
                Text(initial == nil ? "New Reminder" : "Edit Reminder")
                    .font(.system(size: 12, weight: .bold))
                Spacer()

                // Quick presets
                HStack(spacing: 3) {
                    presetChip("+15m", seconds: 900)
                    presetChip("+1h", seconds: 3600)
                    presetChip("Tomorrow 9am") {
                        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                        comps.day = (comps.day ?? 0) + 1
                        comps.hour = 9
                        comps.minute = 0
                        if let d = Calendar.current.date(from: comps) { dueDate = d }
                    }
                }

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            // Input Fields
            VStack(spacing: 4) {
                if isSnapshot {
                    Text(title.isEmpty ? "Reminder title (e.g. Design review)…" : title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(title.isEmpty ? .white.opacity(0.4) : .white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
                    Text(notes.isEmpty ? "Notes / description (optional)" : notes)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                } else {
                    TextField("Reminder title (e.g. Design review)…", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15), lineWidth: 0.5))

                    TextField("Notes / description (optional)", text: $notes)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                }
            }

            // Date & Time Picker
            HStack(spacing: 8) {
                Label("When", systemImage: "clock")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))

                if isSnapshot {
                    // Placeholders use the real controls' widths, so snapshots show overflow.
                    Text(dueDate.formatted(date: .numeric, time: .shortened))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .frame(width: 170, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: repeatSchedule.symbol)
                        Text(repeatSchedule.title)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(width: 110, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.cyan.opacity(0.12)))
                } else {
                    DatePicker("", selection: $dueDate)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .colorScheme(.dark)

                    Spacer()

                    // Repeat Picker
                    Picker("Repeat", selection: $repeatSchedule) {
                        ForEach(EventReminderRepeat.allCases) { schedule in
                            Label(schedule.title, systemImage: schedule.symbol).tag(schedule)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 110)
                }
            }

            // Sound & Approaching Alert Selector
            HStack(spacing: 8) {
                if isSnapshot {
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.yellow)
                        Text(sound.displayName)
                        Spacer(minLength: 0)
                        Image(systemName: "play.circle.fill").foregroundStyle(.yellow)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 130 + 4 + 13)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))

                    HStack(spacing: 4) {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(.orange)
                        Text(leadTime.title)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 130 + 4 + 10)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                    Spacer()
                } else {
                    // Ringtone selector
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                        Picker("", selection: $sound) {
                            ForEach(EventReminderSound.allCases) { snd in
                                Text(snd.displayName).tag(snd)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 130)

                        // Sound preview button
                        Button {
                            sound.play()
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.yellow)
                        }
                        .buttonStyle(.plain)
                        .help("Listen to ringtone preview")
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))

                    // Lead Time (Approaching Alert)
                    HStack(spacing: 4) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        Picker("", selection: $leadTime) {
                            ForEach(EventReminderLeadTime.allCases) { lead in
                                Text(lead.title).tag(lead)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 130)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))

                    Spacer()
                }
            }

            // Action Buttons
            HStack {
                if let onDelete {
                    Button("Delete", role: .destructive, action: onDelete)
                        .buttonStyle(IslandButtonStyle(prominent: false, tint: .red.opacity(0.8)))
                }

                Spacer()

                Button("Cancel", action: onCancel)
                    .buttonStyle(IslandButtonStyle())

                Button(initial == nil ? "Add Reminder" : "Save Changes") {
                    let reminder = EventReminder(
                        id: initial?.id ?? UUID(),
                        title: title.isEmpty ? "Reminder" : title,
                        notes: notes,
                        dueDate: dueDate,
                        repeatSchedule: repeatSchedule,
                        sound: sound,
                        leadTime: leadTime,
                        isCompleted: initial?.isCompleted ?? false,
                        createdAt: initial?.createdAt ?? Date()
                    )
                    onSave(reminder)
                }
                .buttonStyle(IslandButtonStyle(prominent: true, tint: .orange))
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 2)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
    }

    private func presetChip(_ label: String, seconds: TimeInterval? = nil, action: (() -> Void)? = nil) -> some View {
        Button {
            if let action {
                action()
            } else if let seconds {
                dueDate = Date().addingTimeInterval(seconds)
            }
        } label: {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Event Reminder Alert Card (Dynamic Island Banner)

public struct EventReminderAlertCard: View {
    let alert: EventReminderAlert
    let onDone: () -> Void
    let onSnooze: () -> Void
    let onDismiss: () -> Void

    @EnvironmentObject private var settings: AppSettings

    public init(
        alert: EventReminderAlert,
        onDone: @escaping () -> Void,
        onSnooze: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.alert = alert
        self.onDone = onDone
        self.onSnooze = onSnooze
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 18) {
            // Mascot or animated bell
            if settings.showMascot {
                DancingMascot(mood: .shock, size: 70)
            } else {
                ZStack {
                    Circle()
                        .fill(alert.isApproachingWarning ? Color.orange.opacity(0.2) : Color.red.opacity(0.2))
                        .frame(width: 58, height: 58)
                    Image(systemName: alert.isApproachingWarning ? "bell.badge.fill" : "alarm.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(alert.isApproachingWarning ? .orange : .red)
                        .symbolEffect(.bounce, options: .repeating)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(alert.isApproachingWarning ? "APPROACHING" : "REMINDER DUE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(alert.isApproachingWarning ? .orange : .red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill((alert.isApproachingWarning ? Color.orange : Color.red).opacity(0.18)))

                    if alert.reminder.repeatSchedule != .never {
                        HStack(spacing: 3) {
                            Image(systemName: alert.reminder.repeatSchedule.symbol)
                                .font(.system(size: 9))
                            Text(alert.reminder.repeatSchedule.title)
                                .font(.system(size: 9.5))
                        }
                        .foregroundStyle(.cyan)
                    }

                    HStack(spacing: 2) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 8))
                        Text(alert.reminder.sound.displayName)
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }

                Text(alert.reminder.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if !alert.reminder.notes.isEmpty {
                    Text(alert.reminder.notes)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                } else {
                    Text(alert.isApproachingWarning ? "Approaching in \(alert.reminder.leadTime.title)" : "Scheduled for right now")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Spacer(minLength: 0)

            // Buttons
            VStack(spacing: 8) {
                Button("Done", action: onDone)
                    .buttonStyle(IslandButtonStyle(prominent: true, tint: .green))

                Button("Snooze 5m", action: onSnooze)
                    .buttonStyle(IslandButtonStyle())

                Button("Dismiss", action: onDismiss)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .buttonStyle(.plain)
            }
        }
        .frame(maxHeight: .infinity)
    }
}
