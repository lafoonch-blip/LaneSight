import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var model: AppModel
    @State private var profile: Loadable<Profile> = .idle
    @State private var sensors: [Sensor] = []
    @State private var score: ScoreResponse?

    // editable fields
    @State private var name = ""
    @State private var handedness = "right"
    @State private var delivery = "one_handed_thumb"
    @State private var steps = "5"
    @State private var location = ""
    @State private var saving = false
    @State private var saveNote: String?

    @State private var showAddSensor = false
    @State private var newSensorName = ""

    private let deliveryOptions: [(String, String)] = [
        ("one_handed_thumb", "One-handed, thumb"),
        ("one_handed_no_thumb", "One-handed, no thumb"),
        ("two_handed", "Two-handed"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LoadableView(state: profile, retry: { Task { await load() } }) { _ in
                    headerCard
                    bowlerCard
                    sensorsCard
                    arsenalCard
                    if let saveNote { Text(saveNote).font(.caption).foregroundStyle(LS.measured) }
                }
            }
            .padding(16)
        }
        .background(LSBackground())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .alert("Add sensor", isPresented: $showAddSensor) {
            TextField("Sensor name", text: $newSensorName)
            Button("Add") { Task { await addSensor() } }
            Button("Cancel", role: .cancel) { newSensorName = "" }
        } message: {
            Text("Enter a name for your sensor (your own label — no brand names needed).")
        }
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill").font(.system(size: 48)).foregroundStyle(LS.cyan)
            VStack(alignment: .leading, spacing: 3) {
                Text(name.isEmpty ? "Your profile" : name).font(.title3.bold()).foregroundStyle(LS.textPrimary)
                if let s = score, s.eligible == true, let v = s.score {
                    Text("\((s.tier ?? "").capitalized) · \(Int(v.rounded()))")
                        .font(.caption).foregroundStyle(LS.cyan)
                } else {
                    Text("Score building").font(.caption).foregroundStyle(LS.textSecondary)
                }
            }
            Spacer()
            NavigationLink { AchievementsView() } label: {
                Image(systemName: "rosette").foregroundStyle(LS.bestEffort)
            }
            .accessibilityLabel("Achievements")
        }
        .lsCard()
    }

    private var bowlerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BOWLER PROFILE").lsEyebrow()
            labeledField("Name") {
                TextField("Your name", text: $name).foregroundStyle(LS.textPrimary).multilineTextAlignment(.trailing)
            }
            Picker("Handedness", selection: $handedness) {
                Text("Right").tag("right"); Text("Left").tag("left")
            }.pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 4) {
                Text("Delivery style").font(.subheadline).foregroundStyle(LS.textPrimary)
                Picker("Delivery style", selection: $delivery) {
                    ForEach(deliveryOptions, id: \.0) { Text($0.1).tag($0.0) }
                }.pickerStyle(.menu).tint(LS.cyan)
            }
            labeledField("Approach steps") {
                TextField("5", text: $steps).keyboardType(.numberPad)
                    .foregroundStyle(LS.textPrimary).multilineTextAlignment(.trailing)
            }
            labeledField("Location (optional)") {
                TextField("City", text: $location).foregroundStyle(LS.textPrimary).multilineTextAlignment(.trailing)
            }
            Button {
                Task { await save() }
            } label: {
                HStack { Text("Save profile"); if saving { ProgressView().tint(.white) } }
            }
            .buttonStyle(PrimaryButtonStyle()).disabled(saving)
        }
        .lsCard()
    }

    private var sensorsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SENSORS").lsEyebrow()
                Spacer()
                Button { newSensorName = ""; showAddSensor = true } label: {
                    Label("Add", systemImage: "plus").font(.caption)
                }.tint(LS.blue)
            }
            if sensors.isEmpty {
                Text("No sensors added. Add one to compare shots with a sensor in the ball.")
                    .font(.caption).foregroundStyle(LS.textSecondary)
            } else {
                ForEach(sensors) { s in
                    HStack {
                        Image(systemName: "sensor.tag.radiowaves.forward").foregroundStyle(LS.cyan)
                        Text(s.name ?? "Sensor").foregroundStyle(LS.textPrimary)
                        if s.`default` == true {
                            Text("DEFAULT").font(.caption2.bold()).foregroundStyle(LS.measured)
                        }
                        Spacer()
                        Button(role: .destructive) { Task { await deleteSensor(s) } } label: {
                            Image(systemName: "trash").foregroundStyle(LS.bestEffort)
                        }
                    }
                }
            }
        }
        .lsCard()
    }

    private var arsenalCard: some View {
        let balls = model.arsenal.filter { $0.retired != true }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ARSENAL").lsEyebrow()
                Spacer()
                NavigationLink { AddBallView() } label: { Label("Add ball", systemImage: "plus").font(.caption) }
                    .tint(LS.blue)
            }
            if balls.isEmpty {
                Text("No balls yet. Browse the catalog to add one — tap a ball to make it current.")
                    .font(.caption).foregroundStyle(LS.textSecondary)
            } else {
                Text("Tap a ball to make it your current ball.")
                    .font(.caption2).foregroundStyle(LS.textFaint)
                ForEach(balls) { ball in
                    Button { Task { await setCurrent(ball) } } label: { arsenalRow(ball) }
                        .buttonStyle(.plain)
                }
            }
        }
        .lsCard()
    }

    private func arsenalRow(_ ball: ArsenalBall) -> some View {
        let isCurrent = ball.is_current == true
        return HStack(spacing: 10) {
            Image(systemName: isCurrent ? "circle.circle.fill" : "circle.circle")
                .foregroundStyle(isCurrent ? LS.blue : LS.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(ball.displayName).font(.subheadline.bold()).foregroundStyle(LS.textPrimary)
                let specs = [ball.layout.map { "Layout \($0)" }, ball.surface,
                             ball.weight_lb.map { "\(Fmt.number($0)) lb" }].compactMap { $0 }
                if !specs.isEmpty {
                    Text(specs.joined(separator: " · ")).font(.caption2).foregroundStyle(LS.textSecondary)
                }
            }
            Spacer()
            if isCurrent {
                Text("CURRENT").font(.caption2.bold()).foregroundStyle(LS.cyan)
            }
        }
        .contentShape(Rectangle())
    }

    private func setCurrent(_ ball: ArsenalBall) async {
        guard ball.is_current != true else { return }
        do { try await model.setCurrentBall(id: ball.id) }
        catch { saveNote = "Couldn't set current ball: \(error.localizedDescription)" }
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(LS.textPrimary)
            Spacer()
            content()
        }
    }

    // MARK: data

    private func load() async {
        profile = .loading
        do {
            let client = try model.makeClient()
            let p = try await client.getProfile()
            name = p.name ?? ""
            handedness = p.handedness ?? (model.handed == "L" ? "left" : "right")
            delivery = p.delivery_style ?? "one_handed_thumb"
            steps = p.approach_steps?.value ?? "5"
            location = p.location ?? ""
            sensors = (try? await client.listSensors()) ?? []
            score = try? await client.score()
            await model.syncArsenal()
            profile = .loaded(p)
        } catch { profile = .failed(error.localizedDescription) }
    }

    private func save() async {
        saving = true
        saveNote = nil
        var fields: [String: Any] = [
            "name": name, "handedness": handedness, "delivery_style": delivery, "location": location,
        ]
        if let n = Int(steps) { fields["approach_steps"] = n }
        do {
            _ = try await model.makeClient().putProfile(fields)
            model.handed = (handedness == "left") ? "L" : "R"
            saveNote = "Profile saved."
        } catch { saveNote = "Couldn't save: \(error.localizedDescription)" }
        saving = false
    }

    private func addSensor() async {
        let trimmed = newSensorName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            let client = try model.makeClient()
            _ = try await client.addSensor(name: trimmed, isDefault: sensors.isEmpty)
            sensors = try await client.listSensors()
        } catch { saveNote = "Couldn't add sensor: \(error.localizedDescription)" }
        newSensorName = ""
    }

    private func deleteSensor(_ s: Sensor) async {
        do {
            let client = try model.makeClient()
            try await client.deleteSensor(s.id)
            sensors = try await client.listSensors()
        } catch { saveNote = "Couldn't delete sensor: \(error.localizedDescription)" }
    }
}
