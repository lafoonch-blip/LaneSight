import SwiftUI

// MARK: - Auth flow (real email/password)
//
// Welcome → Sign in OR Create account. Both hit the Mac API's /auth/* endpoints (server-mediated
// Supabase); tokens are stored in the Keychain by AppModel. There is no dev stub and no memory/dev
// default on this path — a real session is required. Bad credentials / taken email / network errors
// are shown inline. After auth the app root re-evaluates `model.gate` (profile setup or Home).
struct AuthFlow: View {
    var body: some View {
        NavigationStack {
            WelcomeStep()
        }
        .preferredColorScheme(.dark)
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 16) {
            // Official stacked logo (DEC-054). No LS monogram.
            Image("LaneSightLogo")
                .resizable().scaledToFit()
                .frame(maxWidth: 240)
                .accessibilityLabel("LaneSight")

            Text("SEE MORE. BOWL SMARTER.")
                .font(.lsSubheadline).tracking(3)
                .foregroundStyle(LS.textSecondary)

            // Hero photo placeholder — the real image comes from Figma and isn't bundled in this build.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LS.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(LS.border, lineWidth: 1)
                )
                .overlay(Text("Hero photo").font(.lsFootnote).foregroundStyle(LS.textSecondary))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement()
                .accessibilityLabel("Photo of a bowler releasing the ball (placeholder)")

            NavigationLink { CreateAccountStep() } label: {
                HStack(spacing: 8) {
                    Text("Get Started")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            NavigationLink { SignInStep() } label: { Text("Sign In") }
                .buttonStyle(SecondaryButtonStyle())

            Text("Track your stats · Improve your game · Coaching insights")
                .font(.lsFootnote).foregroundStyle(LS.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 64).padding(.horizontal, 24).padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LSBackground(auth: true))
        .navigationBarHidden(true)
    }
}

// MARK: - Sign in

private struct SignInStep: View {
    @EnvironmentObject var model: AppModel
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorText: String?
    @FocusState private var focus: Field?
    private enum Field { case email, password }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !busy
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Official stacked logo (DEC-054), centered.
                Image("LaneSightLogo")
                    .resizable().scaledToFit()
                    .frame(maxWidth: 180)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
                    .accessibilityLabel("LaneSight")

                Text("Welcome back").font(.lsTitle.bold()).foregroundStyle(LS.textPrimary)
                Text("Sign in to your account to continue")
                    .font(.lsSubheadline).foregroundStyle(LS.textSecondary)

                // Apple / Google are disabled until the paid team is active (changelog 2.0). Shown
                // honestly disabled, not fake-working.
                DisabledSocialButton(title: "Continue with Apple", systemImage: "apple.logo")
                DisabledSocialButton(title: "Continue with Google", glyph: "G")

                OrDivider()

                AuthField("Email address", text: $email, keyboard: .emailAddress, secure: false)
                    .focused($focus, equals: .email)
                AuthField("Password", text: $password, keyboard: .default, secure: true)
                    .focused($focus, equals: .password)

                if let errorText {
                    // No error color in v1 — neutral surface + plain text (3.0).
                    Label(errorText, systemImage: "exclamationmark.circle")
                        .font(.lsFootnote).foregroundStyle(LS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(LS.card, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Sign in error: \(errorText)")
                }

                Button {
                    Task { await submit() }
                } label: {
                    LoadingLabel("Sign In", busy: busy)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.5)

                HStack(spacing: 4) {
                    Text("Don't have an account?").foregroundStyle(LS.textSecondary)
                    NavigationLink("Create one") { CreateAccountStep() }
                        .foregroundStyle(LS.action)
                }
                .font(.lsSubheadline)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
            .padding(.top, 24).padding(.horizontal, 24).padding(.bottom, 40)
        }
        .background(LSBackground(auth: true))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { focus = .email }
    }

    private func submit() async {
        busy = true; errorText = nil
        do { try await model.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password) }
        catch { errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        busy = false
    }
}

// MARK: - Create account

private struct CreateAccountStep: View {
    @EnvironmentObject var model: AppModel
    @State private var email = ""
    @State private var password = ""
    @State private var agree = false
    @State private var busy = false
    @State private var errorText: String?
    @State private var showLegal = false
    @FocusState private var focus: Field?
    private enum Field { case email, password }

    private var emailOK: Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.contains("@") && e.contains(".") && e.count >= 5
    }
    private var canSubmit: Bool { emailOK && password.count >= 6 && agree && !busy }

    private var hintText: String {
        if !emailOK { return "Enter a valid email address." }
        if password.count < 6 { return "Password must be at least 6 characters." }
        if !agree { return "Accept the Terms of Service and Privacy Policy to continue." }
        return ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Create your account").font(.lsTitle2.bold()).foregroundStyle(LS.textPrimary)
                Text("Use a real email and a password of at least 6 characters.")
                    .font(.lsCaption).foregroundStyle(LS.textSecondary)

                AuthField("Email address", text: $email, keyboard: .emailAddress, secure: false)
                    .focused($focus, equals: .email)
                AuthField("Password (min 6 characters)", text: $password, keyboard: .default, secure: true)
                    .focused($focus, equals: .password)

                Toggle(isOn: $agree) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("I agree to the Terms of Service and Privacy Policy")
                            .font(.lsCaption).foregroundStyle(LS.textPrimary)
                        Button("Read the Terms of Service & Privacy Policy") { showLegal = true }
                            .font(.lsCaption2).tint(LS.cyan)
                    }
                }.tint(LS.blue)
                .accessibilityHint("Required before you can create an account")

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.lsCaption).foregroundStyle(LS.bestEffort)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Create account error: \(errorText)")
                }

                Button {
                    Task { await submit() }
                } label: {
                    LoadingLabel("Create Account", busy: busy)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.5)

                if !canSubmit && !busy {
                    Text(hintText)
                        .font(.lsCaption2).foregroundStyle(LS.textFaint)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showLegal) { LegalNoticeSheet() }
        .background(LSBackground(auth: true))
        .navigationTitle("Create account")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focus = .email }
    }

    private func submit() async {
        busy = true; errorText = nil
        do { try await model.signUp(email: email.trimmingCharacters(in: .whitespaces), password: password) }
        catch { errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        busy = false
    }
}

/// Shared labeled auth text field (44pt target, Dynamic Type, no autocorrect/autocap on email).
private struct AuthField: View {
    let label: String
    @Binding var text: String
    let keyboard: UIKeyboardType
    let secure: Bool

    init(_ label: String, text: Binding<String>, keyboard: UIKeyboardType, secure: Bool) {
        self.label = label; self._text = text; self.keyboard = keyboard; self.secure = secure
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.lsCaption).foregroundStyle(LS.textSecondary)
            Group {
                if secure {
                    SecureField("", text: $text).textContentType(.password)
                } else {
                    TextField("", text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                        .textContentType(keyboard == .emailAddress ? .emailAddress : .none)
                }
            }
            .foregroundStyle(LS.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(LS.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(LS.borderStrong, lineWidth: 1))
            .autocorrectionDisabled()
        }
    }
}

/// A disabled social sign-in button (Apple / Google). Honestly non-interactive until the paid team
/// is active — matches SignIn.dc.html's dimmed buttons.
private struct DisabledSocialButton: View {
    let title: String
    var systemImage: String? = nil
    var glyph: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage { Image(systemName: systemImage) }
            if let glyph { Text(glyph).fontWeight(.bold) }
            Text(title).fontWeight(.semibold)
        }
        .font(.lsBody)
        .foregroundStyle(LS.onAction)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(LS.textPrimary, in: RoundedRectangle(cornerRadius: 8))
        .opacity(0.45)
        .accessibilityLabel("\(title) (not available in this build)")
        .accessibilityAddTraits(.isButton)
    }
}

/// The "or" divider between social and email sign-in (SignIn.dc.html).
private struct OrDivider: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(LS.border).frame(height: 1)
            Text("or").font(.lsFootnote).foregroundStyle(LS.textSecondary)
            Rectangle().fill(LS.border).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

/// Honest interim notice for the ToS / Privacy links. The full legal documents aren't written yet
/// for this dev build, so we say so plainly rather than show fabricated terms.
private struct LegalNoticeSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Terms of Service & Privacy Policy")
                        .font(.lsTitle3.bold()).foregroundStyle(LS.textPrimary)
                    Text("LaneSight is a development build. The full Terms of Service and Privacy Policy will be published before public release. By creating an account now you agree to take part in testing and to the handling of your account data, shot videos and stats for the purpose of running and improving the app.")
                        .font(.lsCallout).foregroundStyle(LS.textSecondary)
                    Text("You can delete your account and all associated data at any time from Settings → Delete account.")
                        .font(.lsCallout).foregroundStyle(LS.textSecondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(LSBackground(auth: true))
            .navigationTitle("Legal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Profile setup flow (shown once signed in, until the profile is complete)

struct ProfileSetupFlow: View {
    var body: some View {
        NavigationStack {
            ProfileSetupStep()
        }
        .preferredColorScheme(.dark)
    }
}

private struct ProfileSetupStep: View {
    @EnvironmentObject var model: AppModel

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var dob = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var handedness = "right"
    @State private var delivery = "one_handed_thumb"
    @State private var saving = false
    @State private var saveError: String?

    private var age: Int {
        Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 0
    }
    private var ageOK: Bool { age >= 13 }

    private let deliveryOptions: [(String, String)] = [
        ("one_handed_thumb", "One-handed, thumb"),
        ("one_handed_no_thumb", "One-handed, no thumb"),
        ("two_handed", "Two-handed"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Step 1 of 2").font(.lsCaption).foregroundStyle(LS.cyan)
                Text("Set up your bowler profile").font(.lsTitle2.bold()).foregroundStyle(LS.textPrimary)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("First name").font(.lsSubheadline).foregroundStyle(LS.textPrimary)
                        TextField("First", text: $firstName)
                            .textContentType(.givenName)
                            .foregroundStyle(LS.textPrimary)
                            .padding(12).frame(minHeight: 44)
                            .background(LS.card, in: RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last name").font(.lsSubheadline).foregroundStyle(LS.textPrimary)
                        TextField("Last", text: $lastName)
                            .textContentType(.familyName)
                            .foregroundStyle(LS.textPrimary)
                            .padding(12).frame(minHeight: 44)
                            .background(LS.card, in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Date of birth").font(.lsSubheadline).foregroundStyle(LS.textPrimary)
                    DatePicker("", selection: $dob, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.compact).labelsHidden().tint(LS.cyan)
                    if !ageOK {
                        Label("You must be 13 or older to use LaneSight.", systemImage: "exclamationmark.triangle.fill")
                            .font(.lsCaption).foregroundStyle(LS.bestEffort)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Which hand do you bowl with?").font(.lsSubheadline).foregroundStyle(LS.textPrimary)
                    Picker("Handedness", selection: $handedness) {
                        Text("Right").tag("right"); Text("Left").tag("left")
                    }.pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Delivery style").font(.lsSubheadline).foregroundStyle(LS.textPrimary)
                    Picker("Delivery", selection: $delivery) {
                        ForEach(deliveryOptions, id: \.0) { Text($0.1).tag($0.0) }
                    }.pickerStyle(.menu).tint(LS.cyan)
                }

                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .font(.lsCaption).foregroundStyle(LS.bestEffort)
                        .fixedSize(horizontal: false, vertical: true)
                }

                NavigationLink {
                    AddBallStep()
                } label: {
                    LoadingLabel("Next: add your ball", busy: saving)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!ageOK || saving)
                .opacity(ageOK ? 1 : 0.5)
                .simultaneousGesture(TapGesture().onEnded { Task { await saveProfile() } })
            }
            .padding(20)
        }
        .background(LSBackground(auth: true))
        .navigationTitle("Bowler profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveProfile() async {
        saving = true
        saveError = nil
        let fullName = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let fields: [String: Any] = [
            "name": fullName, "handedness": handedness, "delivery_style": delivery,
            "dob": ISO8601DateFormatter().string(from: dob),
        ]
        model.handed = (handedness == "left") ? "L" : "R"
        do { _ = try await model.makeClient().putProfile(fields) }
        catch { saveError = "Couldn't save profile (you can still continue): \(error.localizedDescription)" }
        saving = false
    }
}

private struct AddBallStep: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Step 2 of 2 · Optional").font(.lsCaption).foregroundStyle(LS.cyan)
                Text("Add your first ball").font(.lsTitle2.bold()).foregroundStyle(LS.textPrimary)
                Text("Optional — you can skip this and add a ball later from your Profile at any time.")
                    .font(.lsCaption).foregroundStyle(LS.textSecondary)

                NavigationLink { AddBallView() } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text(model.currentBallName ?? "Browse the ball catalog")
                        Spacer()
                        Image(systemName: "chevron.right").font(.lsFootnote)
                    }
                    .foregroundStyle(model.currentBallName == nil ? LS.textSecondary : LS.cyan)
                    .lsCard()
                }
                .buttonStyle(.plain)

                // Primary action adapts: continue if a ball was added, otherwise an explicit Skip.
                Button(model.currentBallName == nil ? "Skip for now — go to Home" : "Finish — go to Home") {
                    model.finishProfileSetup()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LSBackground(auth: true))
        .navigationTitle("Add ball")
        .navigationBarTitleDisplayMode(.inline)
    }
}
