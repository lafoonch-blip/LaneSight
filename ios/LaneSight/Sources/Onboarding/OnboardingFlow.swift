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
        VStack(spacing: 20) {
            Spacer()
            HStack(spacing: 2) {
                Text("Lane").font(.largeTitle.bold()).foregroundStyle(LS.textPrimary)
                Text("Sight").font(.largeTitle.bold()).foregroundStyle(LS.cyan)
            }
            Text("UNDERSTAND EVERY SHOT. IMPROVE EVERY GAME.")
                .font(.caption.weight(.semibold)).tracking(1).foregroundStyle(LS.textSecondary)
                .multilineTextAlignment(.center)
            Image(systemName: "figure.bowling")
                .font(.system(size: 90)).foregroundStyle(LS.blue.opacity(0.7))
                .padding(.vertical, 24)
            Spacer()
            NavigationLink { CreateAccountStep() } label: { Text("Create Account") }
                .buttonStyle(PrimaryButtonStyle())
            NavigationLink { SignInStep() } label: { Text("Sign In") }
                .buttonStyle(SecondaryButtonStyle())
            Text("Track your stats · Improve your game · Coaching insights")
                .font(.caption2).foregroundStyle(LS.textFaint)
        }
        .padding(24)
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
            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome back").font(.title2.bold()).foregroundStyle(LS.textPrimary)
                Text("Sign in with your email and password.")
                    .font(.caption).foregroundStyle(LS.textSecondary)

                AuthField("Email address", text: $email, keyboard: .emailAddress, secure: false)
                    .focused($focus, equals: .email)
                AuthField("Password", text: $password, keyboard: .default, secure: true)
                    .focused($focus, equals: .password)

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(LS.bestEffort)
                        .fixedSize(horizontal: false, vertical: true)
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
            }
            .padding(20)
        }
        .background(LSBackground(auth: true))
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.inline)
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
                Text("Create your account").font(.title2.bold()).foregroundStyle(LS.textPrimary)
                Text("Use a real email and a password of at least 6 characters.")
                    .font(.caption).foregroundStyle(LS.textSecondary)

                AuthField("Email address", text: $email, keyboard: .emailAddress, secure: false)
                    .focused($focus, equals: .email)
                AuthField("Password (min 6 characters)", text: $password, keyboard: .default, secure: true)
                    .focused($focus, equals: .password)

                Toggle(isOn: $agree) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("I agree to the Terms of Service and Privacy Policy")
                            .font(.caption).foregroundStyle(LS.textPrimary)
                        Button("Read the Terms of Service & Privacy Policy") { showLegal = true }
                            .font(.caption2).tint(LS.cyan)
                    }
                }.tint(LS.blue)
                .accessibilityHint("Required before you can create an account")

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(LS.bestEffort)
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
                        .font(.caption2).foregroundStyle(LS.textFaint)
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
            Text(label).font(.caption).foregroundStyle(LS.textSecondary)
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
            .padding(12)
            .frame(minHeight: 44)
            .background(LS.card, in: RoundedRectangle(cornerRadius: 10))
            .autocorrectionDisabled()
        }
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
                        .font(.title3.bold()).foregroundStyle(LS.textPrimary)
                    Text("LaneSight is a development build. The full Terms of Service and Privacy Policy will be published before public release. By creating an account now you agree to take part in testing and to the handling of your account data, shot videos and stats for the purpose of running and improving the app.")
                        .font(.callout).foregroundStyle(LS.textSecondary)
                    Text("You can delete your account and all associated data at any time from Settings → Delete account.")
                        .font(.callout).foregroundStyle(LS.textSecondary)
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
                Text("Step 1 of 2").font(.caption).foregroundStyle(LS.cyan)
                Text("Set up your bowler profile").font(.title2.bold()).foregroundStyle(LS.textPrimary)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("First name").font(.subheadline).foregroundStyle(LS.textPrimary)
                        TextField("First", text: $firstName)
                            .textContentType(.givenName)
                            .foregroundStyle(LS.textPrimary)
                            .padding(12).frame(minHeight: 44)
                            .background(LS.card, in: RoundedRectangle(cornerRadius: 10))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last name").font(.subheadline).foregroundStyle(LS.textPrimary)
                        TextField("Last", text: $lastName)
                            .textContentType(.familyName)
                            .foregroundStyle(LS.textPrimary)
                            .padding(12).frame(minHeight: 44)
                            .background(LS.card, in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Date of birth").font(.subheadline).foregroundStyle(LS.textPrimary)
                    DatePicker("", selection: $dob, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.compact).labelsHidden().tint(LS.cyan)
                    if !ageOK {
                        Label("You must be 13 or older to use LaneSight.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(LS.bestEffort)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Which hand do you bowl with?").font(.subheadline).foregroundStyle(LS.textPrimary)
                    Picker("Handedness", selection: $handedness) {
                        Text("Right").tag("right"); Text("Left").tag("left")
                    }.pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Delivery style").font(.subheadline).foregroundStyle(LS.textPrimary)
                    Picker("Delivery", selection: $delivery) {
                        ForEach(deliveryOptions, id: \.0) { Text($0.1).tag($0.0) }
                    }.pickerStyle(.menu).tint(LS.cyan)
                }

                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(LS.bestEffort)
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
                Text("Step 2 of 2 · Optional").font(.caption).foregroundStyle(LS.cyan)
                Text("Add your first ball").font(.title2.bold()).foregroundStyle(LS.textPrimary)
                Text("Optional — you can skip this and add a ball later from your Profile at any time.")
                    .font(.caption).foregroundStyle(LS.textSecondary)

                NavigationLink { AddBallView() } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text(model.currentBallName ?? "Browse the ball catalog")
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote)
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
