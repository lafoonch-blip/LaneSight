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
                    HStack {
                        Text("Sign In")
                        if busy { Spacer(); ProgressView().tint(.white) }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmit)
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
    @FocusState private var focus: Field?
    private enum Field { case email, password }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 6 && agree && !busy
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
                    Text("I agree to the Terms of Service and Privacy Policy")
                        .font(.caption).foregroundStyle(LS.textSecondary)
                }.tint(LS.blue)

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(LS.bestEffort)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Create account error: \(errorText)")
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Text("Create Account")
                        if busy { Spacer(); ProgressView().tint(.white) }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmit)
            }
            .padding(20)
        }
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

    @State private var name = ""
    @State private var dob = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var handedness = "right"
    @State private var delivery = "one_handed_thumb"
    @State private var steps = "5"
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

                VStack(alignment: .leading, spacing: 6) {
                    Text("Name").font(.subheadline).foregroundStyle(LS.textPrimary)
                    TextField("Your name", text: $name)
                        .foregroundStyle(LS.textPrimary)
                        .padding(12).frame(minHeight: 44)
                        .background(LS.card, in: RoundedRectangle(cornerRadius: 10))
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

                VStack(alignment: .leading, spacing: 6) {
                    Text("How many steps in your approach?").font(.subheadline).foregroundStyle(LS.textPrimary)
                    TextField("5", text: $steps).keyboardType(.numberPad)
                        .foregroundStyle(LS.textPrimary)
                        .padding(12).frame(minHeight: 44)
                        .background(LS.card, in: RoundedRectangle(cornerRadius: 10))
                }

                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(LS.bestEffort)
                        .fixedSize(horizontal: false, vertical: true)
                }

                NavigationLink {
                    AddBallStep()
                } label: {
                    HStack { Text("Next: add your ball"); if saving { Spacer(); ProgressView().tint(.white) } }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!ageOK || saving)
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
        var fields: [String: Any] = [
            "name": name, "handedness": handedness, "delivery_style": delivery,
            "dob": ISO8601DateFormatter().string(from: dob),
        ]
        if let n = Int(steps) { fields["approach_steps"] = n }
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
                Text("Step 2 of 2").font(.caption).foregroundStyle(LS.cyan)
                Text("Add your first ball").font(.title2.bold()).foregroundStyle(LS.textPrimary)
                Text("Browse the catalog and pick a ball, or skip and add one later from your Profile.")
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

                Button("Finish — go to Home") {
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
