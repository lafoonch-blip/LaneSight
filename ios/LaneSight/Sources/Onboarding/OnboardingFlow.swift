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

            Text("SEE MORE. BOWL SMARTER.")   // brand tagline — kept over the Figma copy (Shayne, 2026-10-26)
                .font(.lsSubheadline).tracking(3)
                .foregroundStyle(LS.textSecondary)

            // Hero photograph (Figma 442:6462) — the real bowler image; its top/bottom fade into the
            // canvas is baked into the export, so it blends seamlessly without an extra overlay.
            Image("WelcomeHero")
                .resizable().scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .accessibilityElement()
                .accessibilityLabel("A bowler releasing the ball")

            NavigationLink { CreateAccountStep() } label: {
                HStack(spacing: 8) {
                    Text("Get Started")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            NavigationLink { SignInStep() } label: { Text("Sign In") }
                .buttonStyle(SecondaryButtonStyle())

            Text("Track your shots · Improve your game · AI Coaching")
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

struct SignInStep: View {
    @EnvironmentObject var model: AppModel
    @State private var email = ""
    @State private var password = ""
    @State private var rememberMe = true
    @State private var busy = false
    @State private var errorText: String?
    @State private var showForgot = false
    @FocusState private var focus: Field?
    private enum Field { case email, password }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !busy
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Official stacked logo (DEC-054) + brand tagline, centered.
                VStack(spacing: 6) {
                    Image("LaneSightLogo")
                        .resizable().scaledToFit().frame(maxWidth: 180)
                        .accessibilityLabel("LaneSight")
                    Text("SEE MORE. BOWL SMARTER.").font(.lsCaption2).tracking(2).foregroundStyle(LS.textSecondary)
                }
                .frame(maxWidth: .infinity).padding(.bottom, 8)

                Text("Welcome Back").font(.lsTitle.bold()).foregroundStyle(LS.textPrimary)
                Text("Sign in to your account to continue")
                    .font(.lsSubheadline).foregroundStyle(LS.textSecondary)

                // Apple / Google: OAuth is not wired on the Mac API — honestly disabled, not fake-working.
                DisabledSocialButton(title: "Continue with Apple", systemImage: "apple.logo")
                DisabledSocialButton(title: "Continue with Google", glyph: "G")

                OrDivider()

                AuthIconField(icon: "envelope", placeholder: "Email address", text: $email, keyboard: .emailAddress)
                    .focused($focus, equals: .email)
                AuthIconField(icon: "lock", placeholder: "Password", text: $password, secure: true)
                    .focused($focus, equals: .password)

                HStack {
                    AuthCheckbox(checked: $rememberMe, label: "Remember me")
                    Spacer()
                    Button("Forgot password?") { showForgot = true }
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(LS.action)
                }
                .padding(.top, 2)

                if let errorText {
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
        .sheet(isPresented: $showForgot) { ForgotPasswordSheet(email: email) }
        .onAppear { focus = .email }
    }

    private func submit() async {
        busy = true; errorText = nil
        // "Remember me" controls refresh-token persistence: on → stay signed in; off → session only.
        model.persistSession = rememberMe
        do { try await model.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password) }
        catch { errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        busy = false
    }
}

/// Honest password-reset notice. The Mac API has no reset endpoint yet (email/password + refresh only),
/// so rather than a fake "email sent" we explain how to recover access in this dev build.
private struct ForgotPasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    let email: String
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Password reset").font(.lsTitle3.bold()).foregroundStyle(LS.textPrimary)
                    Text("Self-serve password reset isn't available in this development build yet. If you're locked out of \(email.isEmpty ? "your account" : email), message the LaneSight team and we'll reset it for you.")
                        .font(.lsCallout).foregroundStyle(LS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(LSBackground(auth: true))
            .navigationTitle("Forgot password").navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Create account

struct CreateAccountStep: View {
    @EnvironmentObject var model: AppModel
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var agree = false
    @State private var busy = false
    @State private var errorText: String?
    @State private var showLegal = false
    @FocusState private var focus: Field?
    private enum Field { case email, password, confirm }

    private var emailOK: Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.contains("@") && e.contains(".") && e.count >= 5
    }
    private var passwordsMatch: Bool { !confirm.isEmpty && password == confirm }
    private var canSubmit: Bool { emailOK && password.count >= 6 && passwordsMatch && agree && !busy }

    private var hintText: String {
        if !emailOK { return "Enter a valid email address." }
        if password.count < 6 { return "Password must be at least 6 characters." }
        if !passwordsMatch { return "Passwords don't match." }
        if !agree { return "Accept the Terms of Service and Privacy Policy to continue." }
        return ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Logo + brand tagline, centered (Figma 434:5758).
                VStack(spacing: 6) {
                    Image("LaneSightLogo")
                        .resizable().scaledToFit().frame(maxWidth: 160)
                        .accessibilityLabel("LaneSight")
                    Text("SEE MORE. BOWL SMARTER.").font(.lsCaption2).tracking(2).foregroundStyle(LS.textSecondary)
                }
                .frame(maxWidth: .infinity).padding(.bottom, 4)

                Text("Create Your Account").font(.lsTitle.bold()).foregroundStyle(LS.textPrimary)
                Text("Get started with LaneSight. Your name and bowler details come next.")
                    .font(.lsSubheadline).foregroundStyle(LS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // OAuth isn't wired on the Mac API — honestly disabled, not fake-working.
                DisabledSocialButton(title: "Continue with Apple", systemImage: "apple.logo")
                DisabledSocialButton(title: "Continue with Google", glyph: "G")

                OrDivider()

                AuthIconField(icon: "envelope", placeholder: "Email address", text: $email, keyboard: .emailAddress)
                    .focused($focus, equals: .email)
                AuthIconField(icon: "lock", placeholder: "Password", text: $password, secure: true)
                    .focused($focus, equals: .password)
                AuthIconField(icon: "lock", placeholder: "Confirm password", text: $confirm, secure: true)
                    .focused($focus, equals: .confirm)

                AuthCheckbox(checked: $agree, label: "I agree to the Terms of Service and Privacy Policy")
                Button("Read the Terms of Service & Privacy Policy") { showLegal = true }
                    .font(.lsCaption2).tint(LS.cyan).padding(.leading, 32)

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
            .padding(.top, 20).padding(.horizontal, 24).padding(.bottom, 40)
        }
        .sheet(isPresented: $showLegal) { LegalNoticeSheet() }
        .background(LSBackground(auth: true))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { focus = .email }
    }

    private func submit() async {
        busy = true; errorText = nil
        do { try await model.signUp(email: email.trimmingCharacters(in: .whitespaces), password: password) }
        catch { errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        busy = false
    }
}

/// Shared v3.7 auth text field (Figma 442:6465 / 434:5758): a raised-surface pill with a leading icon,
/// the label as placeholder, and an eye toggle for secure fields. 48pt target, no autocorrect on email.
private struct AuthIconField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var secure: Bool = false
    @State private var reveal = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(LS.textSecondary).frame(width: 18)
            Group {
                if secure && !reveal {
                    SecureField(placeholder, text: $text).textContentType(.password)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
                        .textContentType(keyboard == .emailAddress ? .emailAddress : .none)
                }
            }
            .font(.system(size: 15)).foregroundStyle(LS.textPrimary)
            .autocorrectionDisabled()
            if secure {
                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye").font(.system(size: 15)).foregroundStyle(LS.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(reveal ? "Hide password" : "Show password")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(LS.raised, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.borderStrong, lineWidth: 1))
    }
}

/// Apple / Google button styled to the v3.7 design (white pill + brand glyph). OAuth is not wired on the
/// Mac API (only email/password), so these stay honestly disabled — not fake-working (DEC, changelog 2.0).
private struct DisabledSocialButton: View {
    let title: String
    var systemImage: String? = nil
    var glyph: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage { Image(systemName: systemImage).foregroundStyle(.black) }
            if let glyph {
                Text(glyph).fontWeight(.bold)
                    .foregroundStyle(LinearGradient(colors: [Color(hex: 0x4285F4), Color(hex: 0xEA4335)], startPoint: .leading, endPoint: .trailing))
            }
            Text(title).fontWeight(.semibold).foregroundStyle(.black)
        }
        .font(.system(size: 15))
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(LS.textPrimary, in: RoundedRectangle(cornerRadius: 12))
        .opacity(0.5)
        .accessibilityLabel("\(title) (not available in this build)")
        .accessibilityAddTraits(.isButton)
    }
}

/// A square checkbox + label (v3.7 auth screens): cyan fill + white check when on.
private struct AuthCheckbox: View {
    @Binding var checked: Bool
    let label: String
    var body: some View {
        Button { checked.toggle() } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(checked ? LS.action : Color.clear)
                        .frame(width: 22, height: 22)
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(checked ? LS.action : LS.borderStrong, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if checked { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(LS.onAction) }
                }
                Text(label).font(.system(size: 13)).foregroundStyle(LS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
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
    @State private var showUnder13 = false

    private var age: Int {
        Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 0
    }
    private var ageOK: Bool { age >= 13 }

    // Short labels per the v3.7 design — the section header already says "one-handed: thumb or no thumb".
    private let deliveryOptions: [(String, String)] = [
        ("one_handed_thumb", "Thumb"),
        ("one_handed_no_thumb", "No thumb"),
        ("two_handed", "Two-handed"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("STEP 1 OF 2").font(.system(size: 12, weight: .semibold)).tracking(1).foregroundStyle(LS.action)

                fieldLabel("First name")
                profileField("[First]", text: $firstName, content: .givenName)
                fieldLabel("Last name")
                profileField("[Last]", text: $lastName, content: .familyName)

                fieldLabel("Date of birth")
                HStack {
                    DatePicker("", selection: $dob, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.compact).labelsHidden().tint(LS.action)
                    Spacer()
                }
                .padding(.horizontal, 14).frame(minHeight: 50)
                .background(LS.raised, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.borderStrong, lineWidth: 1))
                if !ageOK {
                    Label("You must be 13 or older to use LaneSight.", systemImage: "exclamationmark.triangle.fill")
                        .font(.lsCaption).foregroundStyle(LS.bestEffort)
                }

                Text("Bowling hand").font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary).padding(.top, 2)
                HStack(spacing: 10) {
                    selectPill("Right-handed", selected: handedness == "right") { handedness = "right" }
                    selectPill("Left-handed", selected: handedness == "left") { handedness = "left" }
                }

                Text("Delivery style (one-handed: thumb or no thumb)")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                HStack(spacing: 10) {
                    ForEach(deliveryOptions, id: \.0) { opt in
                        selectPill(opt.1, selected: delivery == opt.0) { delivery = opt.0 }
                    }
                }

                Text("Date of birth is used for the 13+ age check. Hand and style pick your form templates.")
                    .font(.system(size: 12)).foregroundStyle(LS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .font(.lsCaption).foregroundStyle(LS.bestEffort)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Under-13 gate (design 18a): a DOB under 13 blocks onboarding and saves NOTHING — the
                // save only runs on the age-OK path, and the under-13 path routes to the Under13 screen.
                if ageOK {
                    NavigationLink {
                        AddBallStep()
                    } label: {
                        HStack(spacing: 8) { Text(saving ? "Saving…" : "Continue"); if !saving { Image(systemName: "arrow.right") } }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(saving)
                    .simultaneousGesture(TapGesture().onEnded { Task { await saveProfile() } })
                } else {
                    Button { showUnder13 = true } label: {
                        HStack(spacing: 8) { Text("Continue"); Image(systemName: "arrow.right") }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(.top, 16).padding(.horizontal, 20).padding(.bottom, 40)
        }
        .background(LSBackground(auth: true))
        .navigationTitle("Your bowler profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .fullScreenCover(isPresented: $showUnder13) {
            Under13View().environmentObject(model)
        }
    }

    private func fieldLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 13)).foregroundStyle(LS.textSecondary)
    }

    private func profileField(_ placeholder: String, text: Binding<String>, content: UITextContentType) -> some View {
        TextField(placeholder, text: text)
            .textContentType(content).foregroundStyle(LS.textPrimary).font(.system(size: 15))
            .padding(.horizontal, 14).frame(minHeight: 50)
            .background(LS.raised, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.borderStrong, lineWidth: 1))
    }

    /// A selectable pill (Bowling hand / Delivery style): cyan fill when chosen, raised surface otherwise.
    private func selectPill(_ title: String, selected: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(title).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? LS.onAction : LS.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(selected ? LS.action : LS.raised, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? LS.action : LS.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
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

struct AddBallStep: View {
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

/// Under-13 block (design Under13.dc.html / 18a). Reached only when the entered DOB is under 13. Nothing
/// has been saved to the profile at this point (the save runs only on the age-OK path). "Back" dismisses
/// to correct the date; "Sign out" abandons onboarding entirely.
struct Under13View: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Capsule().fill(LS.action).frame(height: 4)
                Capsule().fill(LS.borderStrong).frame(height: 4)
            }
            Text("LaneSight is for bowlers 13 and older")
                .font(.lsTitle2.weight(.semibold)).foregroundStyle(LS.textPrimary).padding(.top, 24)
            Text("Based on the date of birth you entered, you can't use LaneSight yet. We haven't saved your profile.")
                .font(.lsBody).foregroundStyle(LS.textSecondary)
            Text("If the date was entered by mistake, go back and correct it.")
                .font(.lsCallout).foregroundStyle(LS.textSecondary)
            Spacer()
            Button { dismiss() } label: { Text("Back").frame(maxWidth: .infinity) }
                .buttonStyle(SecondaryButtonStyle())
            Button { model.signOut() } label: { Text("Sign out").frame(maxWidth: .infinity) }
                .buttonStyle(.plain)
                .font(.lsSubheadline.weight(.semibold)).foregroundStyle(LS.action).frame(minHeight: 44)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LSBackground(auth: true))
    }
}
