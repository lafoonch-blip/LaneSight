import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject var model: AppModel
    @State private var profile: Loadable<Profile> = .idle
    @State private var sensors: [Sensor] = []
    @State private var score: ScoreResponse?

    // profile photo (handoff G)
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoMenu = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var avatarBusy = false
    @State private var avatarError: String?

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

    // Form baseline (swing timing to compare against; PUT /me/profile `form_baseline`).
    @State private var baseline: FormBaseline?
    @State private var basePushaway = ""
    @State private var baseBackswing = ""
    @State private var baseDownswing = ""
    @State private var baseRelease = ""
    @State private var baselineSaving = false

    private let deliveryOptions: [(String, String)] = [
        ("one_handed_thumb", "One-handed, thumb"),
        ("one_handed_no_thumb", "One-handed, no thumb"),
        ("two_handed", "Two-handed"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LoadableView(state: profile, retry: { Task { await load() } }) { _ in
                    photoSection
                    headerCard
                    bowlerCard
                    baselineCard
                    sensorsCard
                    arsenalCard
                    if let saveNote { Text(saveNote).font(.lsCaption).foregroundStyle(LS.measured) }
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

    // MARK: profile photo (Profile.dc.html "Add photo (optional)")

    private var photoSection: some View {
        VStack(spacing: 8) {
            avatarCircle
            Text(model.avatarImage == nil ? "Add photo (optional)" : "Change photo")
                .font(.lsCaption).foregroundStyle(LS.cyan)
            if let avatarError {
                Text(avatarError).font(.lsCaption2).foregroundStyle(LS.bestEffort).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .confirmationDialog("Profile photo", isPresented: $showPhotoMenu, titleVisibility: .visible) {
            Button("Choose from Library") { showPhotoPicker = true }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") { showCamera = true }
            }
            if model.avatarImage != nil {
                Button("Remove Photo", role: .destructive) { Task { await removeAvatar() } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in Task { await handlePicked(item) } }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in Task { await uploadUIImage(image) } }.ignoresSafeArea()
        }
    }

    private var avatarCircle: some View {
        Button { showPhotoMenu = true } label: {
            ZStack {
                if let img = model.avatarImage {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Circle().fill(LS.selected)
                    Image(systemName: "plus").font(.system(size: 30, weight: .regular)).foregroundStyle(LS.cyan)
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(LS.action, lineWidth: 2))
            .overlay {
                if avatarBusy {
                    ZStack { Circle().fill(.black.opacity(0.45)); ProgressView().tint(.white) }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.avatarImage == nil ? "Add profile photo" : "Change profile photo")
        .disabled(avatarBusy)
    }

    private func handlePicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        avatarError = nil
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                await uploadData(data, mime: "image/jpeg")
            }
        } catch {
            avatarError = "Couldn't read that photo."
        }
        photoItem = nil
    }

    private func uploadUIImage(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            avatarError = "Couldn't process the photo."; return
        }
        await uploadData(data, mime: "image/jpeg")
    }

    private func uploadData(_ data: Data, mime: String) async {
        avatarBusy = true; avatarError = nil
        do {
            _ = try await model.makeClient().uploadAvatar(data, mime: mime)
            await model.refreshAvatar()
        } catch APIError.http(let status, _) where status == 413 {
            avatarError = "Image too large (max 10 MB)."
        } catch APIError.http(let status, _) where status == 415 {
            avatarError = "Use a HEIC, JPEG or PNG photo."
        } catch {
            avatarError = "Couldn't upload: \(error.localizedDescription)"
        }
        avatarBusy = false
    }

    private func removeAvatar() async {
        avatarBusy = true; avatarError = nil
        do {
            _ = try await model.makeClient().deleteAvatar()
            await model.refreshAvatar()
        } catch {
            avatarError = "Couldn't remove: \(error.localizedDescription)"
        }
        avatarBusy = false
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill").font(.system(size: 48)).foregroundStyle(LS.cyan)
            VStack(alignment: .leading, spacing: 3) {
                Text(name.isEmpty ? "Your profile" : name).font(.lsTitle3.bold()).foregroundStyle(LS.textPrimary)
                if let s = score, s.eligible == true, let v = s.score {
                    Text("\((s.tier ?? "").capitalized) · \(Int(v.rounded()))")
                        .font(.lsCaption).foregroundStyle(LS.cyan)
                } else {
                    Text("Score building").font(.lsCaption).foregroundStyle(LS.textSecondary)
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
                Text("Delivery style").font(.lsSubheadline).foregroundStyle(LS.textPrimary)
                Picker("Delivery style", selection: $delivery) {
                    ForEach(deliveryOptions, id: \.0) { Text($0.1).tag($0.0) }
                }.pickerStyle(.menu).tint(LS.cyan)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Approach steps").font(.lsSubheadline).foregroundStyle(LS.textPrimary)
                Picker("Approach steps", selection: $steps) {
                    Text("4 steps").tag("4"); Text("5 steps").tag("5")
                }.pickerStyle(.segmented)
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

    // MARK: form baseline (swing timing to compare against — Form results swing-timing bar)

    private var baselineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FORM BASELINE").lsEyebrow()
                Spacer()
                Text(baselineSummary).font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
            Text("Swing timing the Form card compares each delivery against. Enter your phase splits, or use your measured average.")
                .font(.lsCaption).foregroundStyle(LS.textSecondary)

            if baseline?.mode == "average" {
                Label("Using your measured average", systemImage: "checkmark.circle.fill")
                    .font(.lsCaption).foregroundStyle(LS.measured)
            }

            HStack(spacing: 10) {
                baselineField("Pushaway", text: $basePushaway)
                baselineField("Backswing", text: $baseBackswing)
            }
            HStack(spacing: 10) {
                baselineField("Downswing", text: $baseDownswing)
                baselineField("Release", text: $baseRelease)
            }

            HStack(spacing: 10) {
                Button { Task { await useAverageBaseline() } } label: {
                    Text("Use my average")
                }
                .buttonStyle(SecondaryButtonStyle()).disabled(baselineSaving)
                Button { Task { await saveEnteredBaseline() } } label: {
                    LoadingLabel("Save baseline", busy: baselineSaving)
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(baselineSaving)
            }
        }
        .lsCard()
    }

    private var baselineSummary: String {
        if let b = baseline {
            if b.mode == "average" { return "Your average" }
            if let t = b.total { return String(format: "%.2f s", t) }
            let entered = [b.pushaway_time, b.backswing_time, b.downswing_time, b.release_time].compactMap { $0 }
            if !entered.isEmpty { return String(format: "%.2f s", entered.reduce(0, +)) }
        }
        return "Not set"
    }

    private func baselineField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.lsCaption2).foregroundStyle(LS.textSecondary)
            HStack(spacing: 4) {
                TextField("0.00", text: text).keyboardType(.decimalPad)
                    .foregroundStyle(LS.textPrimary)
                Text("s").font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(LS.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(LS.borderStrong, lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }

    private var sensorsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SENSORS").lsEyebrow()
                Spacer()
                Button { newSensorName = ""; showAddSensor = true } label: {
                    Label("Add", systemImage: "plus").font(.lsCaption)
                }.tint(LS.blue)
            }
            if sensors.isEmpty {
                Text("No sensors added. Add one to compare shots with a sensor in the ball.")
                    .font(.lsCaption).foregroundStyle(LS.textSecondary)
            } else {
                ForEach(sensors) { s in
                    HStack {
                        Image(systemName: "sensor.tag.radiowaves.forward").foregroundStyle(LS.cyan)
                        Text(s.name ?? "Sensor").foregroundStyle(LS.textPrimary)
                        if s.`default` == true {
                            Text("DEFAULT").font(.lsCaption2.bold()).foregroundStyle(LS.measured)
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
                NavigationLink { AddBallView() } label: { Label("Add ball", systemImage: "plus").font(.lsCaption) }
                    .tint(LS.blue)
            }
            if balls.isEmpty {
                Text("No balls yet. Browse the catalog to add one — tap a ball to make it current.")
                    .font(.lsCaption).foregroundStyle(LS.textSecondary)
            } else {
                Text("Tap a ball to make it your current ball.")
                    .font(.lsCaption2).foregroundStyle(LS.textFaint)
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
                Text(ball.displayName).font(.lsSubheadline.bold()).foregroundStyle(LS.textPrimary)
                let specs = [ball.layout.map { "Layout \($0)" }, ball.surface,
                             ball.weight_lb.map { "\(Fmt.number($0)) lb" }].compactMap { $0 }
                if !specs.isEmpty {
                    Text(specs.joined(separator: " · ")).font(.lsCaption2).foregroundStyle(LS.textSecondary)
                }
            }
            Spacer()
            if isCurrent {
                Text("CURRENT").font(.lsCaption2.bold()).foregroundStyle(LS.cyan)
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
            Text(label).font(.lsSubheadline).foregroundStyle(LS.textPrimary)
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
            steps = (p.approach_steps?.value == "4") ? "4" : "5"       // fundamentals support 4- or 5-step
            location = p.location ?? ""
            loadBaseline(p.form_baseline)
            sensors = (try? await client.listSensors()) ?? []
            score = try? await client.score()
            await model.syncArsenal()
            await model.refreshAvatar()
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

    // MARK: form baseline persistence

    private func loadBaseline(_ b: FormBaseline?) {
        baseline = b
        func f(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "" }
        basePushaway = f(b?.pushaway_time)
        baseBackswing = f(b?.backswing_time)
        baseDownswing = f(b?.downswing_time)
        baseRelease = f(b?.release_time)
    }

    /// "Use my average": the engine fills the baseline from the bowler's measured per-phase medians.
    private func useAverageBaseline() async {
        baselineSaving = true
        saveNote = nil
        do {
            let p = try await model.makeClient().putProfile(["form_baseline": ["mode": "average"]])
            loadBaseline(p.form_baseline ?? FormBaseline(mode: "average"))
            saveNote = "Form baseline set to your average."
        } catch { saveNote = "Couldn't set baseline: \(error.localizedDescription)" }
        baselineSaving = false
    }

    /// Entered baseline: persist only the phases the bowler typed, plus their total. No fabricated values.
    private func saveEnteredBaseline() async {
        baselineSaving = true
        saveNote = nil
        var fb: [String: Any] = ["mode": "entered"]
        var total = 0.0
        var any = false
        func add(_ key: String, _ text: String) {
            if let v = Double(text.trimmingCharacters(in: .whitespaces)) { fb[key] = v; total += v; any = true }
        }
        add("pushaway_time", basePushaway)
        add("backswing_time", baseBackswing)
        add("downswing_time", baseDownswing)
        add("release_time", baseRelease)
        guard any else { saveNote = "Enter at least one phase time (seconds) to save a baseline."; baselineSaving = false; return }
        fb["total"] = total
        do {
            let p = try await model.makeClient().putProfile(["form_baseline": fb])
            loadBaseline(p.form_baseline)
            saveNote = "Form baseline saved."
        } catch { saveNote = "Couldn't save baseline: \(error.localizedDescription)" }
        baselineSaving = false
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

/// Camera capture for the profile photo. PhotosPicker covers the library; this covers "Take Photo".
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
