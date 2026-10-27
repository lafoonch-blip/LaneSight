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

    // editable fields (DEC-087: all autosave — there is no Save button)
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var handedness = "right"
    @State private var delivery = "one_handed_thumb"
    @State private var steps = "5"
    @State private var location = ""
    @State private var email = ""          // current login email (display only; change starts a confirmation)
    @State private var dob = ""            // YYYY-MM-DD
    // grip + PAP, inches, as text so a blank means "unset" and the server validates the number
    @State private var midPitch = ""
    @State private var span = ""
    @State private var papOver = ""
    @State private var papUp = ""

    @FocusState private var focused: PField?
    @State private var savedField: PField?            // shows a brief "Saved" on the field that just saved
    @State private var fieldErrors: [PField: String] = [:]
    @State private var ready = false                  // suppresses autosave while load() seeds the fields

    // email change + DOB editor sheets
    @State private var showEmailEditor = false
    @State private var showDobEditor = false

    // Form baseline (swing timing the Form card compares against; PUT /me/profile `form_baseline`).
    @State private var baseline: FormBaseline?

    /// Autosaveable text/number fields, keyed for focus tracking + per-field "Saved"/error state.
    enum PField: Hashable { case first, last, phone, location, midPitch, span, papOver, papUp }

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
                    Text("Changes save automatically.")
                        .font(.system(size: 12)).foregroundStyle(LS.textFaint)
                        .frame(maxWidth: .infinity).padding(.top, 2)
                }
            }
            .padding(16)
        }
        .background(LSBackground())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .onChange(of: focused) { old, _ in if let old { commit(old) } }   // save a field when it loses focus
        .sheet(isPresented: $showEmailEditor) {
            EmailEditorSheet(current: email).environmentObject(model)
                .presentationDetents([.height(320)])
        }
        .sheet(isPresented: $showDobEditor) {
            DOBEditorSheet(onSaved: { iso in dob = iso }).environmentObject(model)
                .presentationDetents([.height(380)])
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

    /// An autosaving text/number row (DEC-087): edits save on Return or when focus leaves. A brief "Saved"
    /// or the server's validation error shows under the field, and the user's input is never reverted.
    private func fieldRow(_ label: String, _ field: PField, _ text: Binding<String>,
                          placeholder: String, keyboard: UIKeyboardType = .default,
                          unit: String? = nil, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 15)).foregroundStyle(LS.textPrimary)
                Spacer(minLength: 12)
                TextField(placeholder, text: text)
                    .keyboardType(keyboard).multilineTextAlignment(.trailing)
                    .font(.system(size: 15)).foregroundStyle(LS.textPrimary)
                    .focused($focused, equals: field)
                    .onSubmit { commit(field) }
                if let unit { Text(unit).font(.system(size: 13)).foregroundStyle(LS.textSecondary) }
            }
            if let hint, fieldErrors[field] == nil {
                Text(hint).font(.system(size: 11)).foregroundStyle(LS.textFaint)
            }
            if let err = fieldErrors[field] {
                Text(err).font(.system(size: 11)).foregroundStyle(LS.bestEffort)
            } else if savedField == field {
                Text("Saved").font(.system(size: 11)).foregroundStyle(LS.positive)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 54)
    }

    /// A read-only row with a label and a muted trailing value (for not-yet-wired fields).
    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(LS.textPrimary)
            Spacer(minLength: 12)
            Text(value).font(.system(size: 14)).foregroundStyle(LS.textSecondary)
        }
        .padding(.horizontal, 16).frame(height: 54)
    }

    /// A tappable row (Email / Date of birth) that opens a sheet. Shows the current value or "Add".
    private func tapRow(_ label: String, _ value: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack {
                Text(label).font(.system(size: 15)).foregroundStyle(LS.textPrimary)
                Spacer(minLength: 12)
                Text(value).font(.system(size: 14)).foregroundStyle(value == "Add" ? LS.link : LS.textSecondary)
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(LS.textFaint)
            }
            .padding(.horizontal, 16).frame(height: 54)
        }
        .buttonStyle(.plain)
    }

    private var contactCard: some View {
        card {
            fieldRow("First name", .first, $firstName, placeholder: "First")
            rowDivider
            fieldRow("Last name", .last, $lastName, placeholder: "Last")
            rowDivider
            tapRow("Email", email.isEmpty ? "Add" : email) { showEmailEditor = true }
            rowDivider
            fieldRow("Phone (optional)", .phone, $phone, placeholder: "Add", keyboard: .phonePad)
            rowDivider
            tapRow("Date of birth", dob.isEmpty ? "Add" : dob) { showDobEditor = true }
        }
    }

    private var bowlerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("Bowler Profile")
            SegToggle(options: [("Right-handed", "right"), ("Left-handed", "left")], selection: $handedness)
                .onChange(of: handedness) { _, v in
                    guard ready else { return }
                    model.handed = (v == "left") ? "L" : "R"
                    Task { await save(["handedness": v], field: nil) }
                }
            SegToggle(options: [("Thumb", "one_handed_thumb"), ("No thumb", "one_handed_no_thumb"), ("Two-handed", "two_handed")], selection: $delivery)
                .onChange(of: delivery) { _, v in if ready { Task { await save(["delivery_style": v], field: nil) } } }
            card {
                HStack {
                    Text("Approach steps").font(.system(size: 15)).foregroundStyle(LS.textPrimary)
                    Spacer()
                    Picker("", selection: $steps) { Text("4").tag("4"); Text("5").tag("5") }
                        .labelsHidden().tint(LS.textSecondary)
                        .onChange(of: steps) { _, v in if ready, let n = Int(v) { Task { await save(["approach_steps": n], field: nil) } } }
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
            card { fieldRow("Location", .location, $location, placeholder: "City, State") }
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
                fieldRow("Grip · middle pitch", .midPitch, $midPitch, placeholder: "—",
                         keyboard: .numbersAndPunctuation, unit: "in",
                         hint: "Finger pitch, signed: forward +, reverse −.")
                rowDivider
                fieldRow("Grip · span", .span, $span, placeholder: "—",
                         keyboard: .decimalPad, unit: "in",
                         hint: "Cut-to-cut, finger hole to thumb hole.")
                rowDivider
                fieldRow("PAP · over", .papOver, $papOver, placeholder: "—",
                         keyboard: .decimalPad, unit: "in",
                         hint: "Horizontal from grip center to your Positive Axis Point.")
                rowDivider
                fieldRow("PAP · up", .papUp, $papUp, placeholder: "—",
                         keyboard: .numbersAndPunctuation, unit: "in",
                         hint: "Vertical from the midline: up +, down −.")
            }
        }
    }

    // MARK: data

    private func load() async {
        profile = .loading
        ready = false
        do {
            let client = try model.makeClient()
            let p = try await client.getProfile()
            firstName = p.first_name ?? ""
            lastName = p.last_name ?? ""
            phone = p.phone ?? ""
            handedness = p.handedness ?? (model.handed == "L" ? "left" : "right")
            delivery = p.delivery_style ?? "one_handed_thumb"
            steps = (p.approach_steps?.value == "4") ? "4" : "5"       // fundamentals support 4- or 5-step
            location = p.location ?? ""
            email = p.email ?? ""
            dob = p.dob ?? ""
            midPitch = p.grip_middle_pitch_in.map(Self.inchStr) ?? ""
            span = p.grip_span_in.map(Self.inchStr) ?? ""
            papOver = p.pap_over_in.map(Self.inchStr) ?? ""
            papUp = p.pap_up_in.map(Self.inchStr) ?? ""
            baseline = p.form_baseline
            score = try? await client.score()
            await model.syncArsenal()
            await model.refreshAvatar()
            profile = .loaded(p)
            ready = true          // enable autosave only after the fields are seeded
        } catch { profile = .failed(error.localizedDescription) }
    }

    private static func inchStr(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }

    // MARK: autosave (DEC-087 — no Save button)

    /// The PUT payload for one autosaving field. A blank numeric field returns nil (nothing to save yet).
    private func payload(for f: PField) -> [String: Any]? {
        switch f {
        case .first:    return ["first_name": firstName.trimmingCharacters(in: .whitespaces)]
        case .last:     return ["last_name": lastName.trimmingCharacters(in: .whitespaces)]
        case .phone:    return ["phone": phone.trimmingCharacters(in: .whitespaces)]   // "" clears it
        case .location: return ["location": location.trimmingCharacters(in: .whitespaces)]
        case .midPitch: return numberPayload("grip_middle_pitch_in", midPitch)
        case .span:     return numberPayload("grip_span_in", span)
        case .papOver:  return numberPayload("pap_over_in", papOver)
        case .papUp:    return numberPayload("pap_up_in", papUp)
        }
    }

    /// A numeric field sends its raw trimmed text (the server validates + coerces); blank → nil (skip save).
    private func numberPayload(_ key: String, _ text: String) -> [String: Any]? {
        let t = text.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : [key: t]
    }

    private func commit(_ f: PField) {
        guard ready, let p = payload(for: f) else { return }
        Task { await save(p, field: f) }
    }

    private func save(_ fields: [String: Any], field: PField?) async {
        do {
            _ = try await model.makeClient().putProfile(fields)
            if let field {
                fieldErrors[field] = nil
                savedField = field
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                if savedField == field { savedField = nil }
            }
        } catch {
            // Keep the user's input; show the server's reason on the field (DEC-087).
            if let field {
                fieldErrors[field] = APIClient.fieldError(from: error)?.message ?? "Couldn't save — try again."
            }
        }
    }

}

/// Email change (DEC-087 §3). Sends the new address to Supabase Auth, which emails a confirmation link; the
/// login email doesn't change until the user confirms, so we keep showing the current one and never write it
/// to the profile. The sheet just reports that the confirmation was sent.
private struct EmailEditorSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let current: String
    @State private var draft = ""
    @State private var busy = false
    @State private var note: String?
    @State private var error: String?
    @State private var done = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Change email").font(.system(size: 18, weight: .bold)).foregroundStyle(LS.textPrimary)
            if !current.isEmpty {
                Text("Current: \(current)").font(.system(size: 12)).foregroundStyle(LS.textSecondary)
            }
            TextField("new@email.com", text: $draft)
                .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                .foregroundStyle(LS.textPrimary).padding(12)
                .background(LS.raised, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.borderStrong, lineWidth: 1))
            if let note { Text(note).font(.system(size: 12)).foregroundStyle(LS.positive) }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(LS.bestEffort) }
            Spacer(minLength: 0)
            Button {
                Task { await send() }
            } label: {
                HStack { Text(done ? "Done" : "Send confirmation"); if busy { ProgressView().tint(LS.onAction) } }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy || (!done && !draft.contains("@")))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LSBackground())
    }

    private func send() async {
        if done { dismiss(); return }
        busy = true; error = nil; note = nil
        do {
            note = try await model.makeClient().putEmail(draft.trimmingCharacters(in: .whitespaces))
            done = true
        } catch {
            self.error = APIClient.fieldError(from: error)?.message ?? "Couldn't start the email change."
        }
        busy = false
    }
}

/// Date-of-birth entry (DEC-087): typable MM/DD/YYYY with NO pre-selected value, matching onboarding. The
/// server enforces the real-date + 13+ gate; its message shows inline and the user's input is kept.
private struct DOBEditorSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var onSaved: (String) -> Void
    @State private var m = ""
    @State private var d = ""
    @State private var y = ""
    @State private var busy = false
    @State private var error: String?

    private var iso: String? {
        guard let mi = Int(m), let di = Int(d), let yi = Int(y),
              (1...12).contains(mi), (1...31).contains(di), yi >= 1900 else { return nil }
        return String(format: "%04d-%02d-%02d", yi, mi, di)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Date of birth").font(.system(size: 18, weight: .bold)).foregroundStyle(LS.textPrimary)
            Text("Used for the 13+ age check.").font(.system(size: 12)).foregroundStyle(LS.textSecondary)
            HStack(spacing: 10) {
                seg($m, "MM", 2); seg($d, "DD", 2); seg($y, "YYYY", 4)
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(LS.bestEffort) }
            Spacer(minLength: 0)
            Button { Task { await save() } } label: {
                HStack { Text("Save"); if busy { ProgressView().tint(LS.onAction) } }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy || iso == nil)
            .opacity(iso == nil ? 0.5 : 1)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LSBackground())
    }

    private func seg(_ text: Binding<String>, _ placeholder: String, _ maxLen: Int) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.numberPad).multilineTextAlignment(.center)
            .font(.system(size: 16)).foregroundStyle(LS.textPrimary)
            .frame(width: maxLen == 4 ? 86 : 60, height: 52)
            .background(LS.raised, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.borderStrong, lineWidth: 1))
            .onChange(of: text.wrappedValue) { _, v in
                let digits = String(v.filter(\.isNumber).prefix(maxLen))
                if digits != v { text.wrappedValue = digits }
            }
    }

    private func save() async {
        guard let iso else { return }
        busy = true; error = nil
        do {
            let p = try await model.makeClient().putProfile(["dob": iso])
            onSaved(p.dob ?? iso)
            dismiss()
        } catch {
            self.error = APIClient.fieldError(from: error)?.message ?? "Enter a valid date of birth."
        }
        busy = false
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
