import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject var model: AppModel
    @State private var profile: Loadable<Profile> = .idle
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
    @State private var email = ""
    @State private var dob = ""
    @State private var saving = false
    @State private var saveNote: String?

    // Form baseline (swing timing the Form card compares against; PUT /me/profile `form_baseline`).
    @State private var baseline: FormBaseline?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LoadableView(state: profile, retry: { Task { await load() } }) { _ in
                    photoSection
                    contactCard
                    bowlerSection
                    locationSection
                    arsenalSection
                    advancedSection
                    saveButton
                    if let saveNote { Text(saveNote).font(.system(size: 12)).foregroundStyle(LS.positive) }
                }
            }
            .padding(16)
        }
        .background(LSBackground())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
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

    private var baselineSummary: String {
        if let b = baseline {
            if b.mode == "average" { return "Your average" }
            if let t = b.total { return String(format: "%.2f s", t) }
            let entered = [b.pushaway_time, b.backswing_time, b.downswing_time, b.release_time].compactMap { $0 }
            if !entered.isEmpty { return String(format: "%.2f s", entered.reduce(0, +)) }
        }
        return "Not set"
    }

    // MARK: v3.7 sections (Figma 434:5981)

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }
    private var rowDivider: some View { Divider().overlay(LS.border).padding(.leading, 16) }

    private func heading(_ t: String) -> some View {
        Text(t).font(.system(size: 20, weight: .bold)).foregroundStyle(LS.textPrimary)
    }
    private func caption(_ t: String) -> some View {
        Text(t).font(.system(size: 12)).foregroundStyle(LS.textSecondary).fixedSize(horizontal: false, vertical: true)
    }

    /// A row with a label and an editable trailing text field.
    private func editRow(_ label: String, _ text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(LS.textPrimary)
            Spacer(minLength: 12)
            TextField(placeholder, text: text)
                .keyboardType(keyboard).multilineTextAlignment(.trailing)
                .font(.system(size: 15)).foregroundStyle(LS.textPrimary)
        }
        .padding(.horizontal, 16).frame(height: 54)
    }
    /// A read-only row with a label and a muted trailing value (for optional / not-yet-wired fields).
    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(LS.textPrimary)
            Spacer(minLength: 12)
            Text(value).font(.system(size: 14)).foregroundStyle(LS.textSecondary)
        }
        .padding(.horizontal, 16).frame(height: 54)
    }

    private var contactCard: some View {
        card {
            editRow("Name", $name, placeholder: "First Last")
            rowDivider
            valueRow("Email", email.isEmpty ? "—" : email)
            rowDivider
            valueRow("Phone (optional)", "Add")
            rowDivider
            valueRow("Date of birth", dob.isEmpty ? "Add" : dob)
        }
    }

    private var bowlerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("Bowler Profile")
            SegToggle(options: [("Right-handed", "right"), ("Left-handed", "left")], selection: $handedness)
            SegToggle(options: [("Thumb", "one_handed_thumb"), ("No thumb", "one_handed_no_thumb"), ("Two-handed", "two_handed")], selection: $delivery)
            card {
                HStack {
                    Text("Approach steps").font(.system(size: 15)).foregroundStyle(LS.textPrimary)
                    Spacer()
                    Picker("", selection: $steps) { Text("4").tag("4"); Text("5").tag("5") }
                        .labelsHidden().tint(LS.textSecondary)
                }
                .padding(.horizontal, 16).frame(height: 54)
                rowDivider
                valueRow("Form baseline", baselineSummary)
            }
        }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            caption("Location (optional)")
            card { editRow("Location", $location, placeholder: "City, State") }
            caption("Home center (optional)")
            card { valueRow("Home center", "Coming later") }
            caption("USBC Member ID")
            card { valueRow("USBC Member ID", "Coming later") }
        }
    }

    private var arsenalSection: some View {
        let balls = model.arsenal.filter { $0.retired != true }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                heading("Arsenal")
                Spacer()
                NavigationLink { AddBallView() } label: {
                    Text("+ Add ball").font(.system(size: 13, weight: .medium)).foregroundStyle(LS.link)
                }
            }
            if balls.isEmpty {
                card { valueRow("No balls yet", "Add one") }
            } else {
                ForEach(balls) { ball in
                    // Tap → Ball setup view/edit (Figma 437:6083): specs, drilling, performance, Save.
                    NavigationLink { BallSetupView(arsenalBall: ball) } label: { arsenalCardRow(ball) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func arsenalCardRow(_ ball: ArsenalBall) -> some View {
        let isCurrent = ball.is_current == true
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(LS.raised).frame(width: 44, height: 44)
                Image(systemName: "circle.circle.fill").font(.system(size: 22)).foregroundStyle(isCurrent ? LS.action : LS.textSecondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ball.displayName).font(.system(size: 15, weight: .semibold)).foregroundStyle(LS.textPrimary)
                    if isCurrent {
                        Text("Current ball").font(.system(size: 10, weight: .semibold)).foregroundStyle(LS.positive)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(LS.positive.opacity(0.14), in: Capsule())
                    }
                }
                let specs = [ball.surface, ball.weight_lb.map { "\(Int($0.rounded())) lb" }].compactMap { $0 }
                if !specs.isEmpty {
                    Text(specs.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(LS.textSecondary)
                }
            }
            Spacer()
            Text("›").font(.system(size: 18)).foregroundStyle(LS.textSecondary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isCurrent ? LS.heroStroke : LS.cardStrokeBright, lineWidth: 1))
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("Advanced (optional)")
            caption("Only needed for layout-aware ball stats. Skip it if you just want to bowl.")
            card {
                valueRow("Grip · middle pitch", "Coming later")
                rowDivider
                valueRow("Grip · span", "Coming later")
                rowDivider
                valueRow("PAP · over", "Coming later")
                rowDivider
                valueRow("PAP · up", "Coming later")
            }
        }
    }

    private var saveButton: some View {
        Button { Task { await save() } } label: {
            HStack { Text("Save profile"); if saving { ProgressView().tint(LS.onAction) } }
        }
        .buttonStyle(PrimaryButtonStyle()).disabled(saving).padding(.top, 4)
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
            email = p.email ?? ""
            dob = p.dob ?? ""
            baseline = p.form_baseline
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
