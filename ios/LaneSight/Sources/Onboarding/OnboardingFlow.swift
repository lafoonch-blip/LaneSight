import SwiftUI

/// Onboarding: Welcome → Create account (dev stub) → Profile setup (13+ gate) → Add ball → Home.
/// There is no real Supabase auth in this slice; "Create account" just sets the dev user id and saves
/// the profile. Clearly labeled dev throughout.
struct OnboardingFlow: View {
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
            NavigationLink { CreateAccountStep() } label: { Text("Get Started") }
                .buttonStyle(PrimaryButtonStyle())
            NavigationLink { CreateAccountStep() } label: { Text("Sign In") }
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

private struct CreateAccountStep: View {
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var agree = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Create your account").font(.title2.bold()).foregroundStyle(LS.textPrimary)
                Text("Dev build: this sets your dev user id and profile — no real sign-in yet.")
                    .font(.caption).foregroundStyle(LS.bestEffort)

                field("First name", text: $firstName)
                field("Last name", text: $lastName)
                field("Email address", text: $email, keyboard: .emailAddress)
                field("Password", text: $password, secure: true)

                Toggle(isOn: $agree) {
                    Text("I agree to the Terms of Service and Privacy Policy")
                        .font(.caption).foregroundStyle(LS.textSecondary)
                }.tint(LS.blue)

                NavigationLink {
                    ProfileSetupStep(name: [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " "),
                                     email: email)
                } label: { Text("Create Account") }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!agree)
            }
            .padding(20)
        }
        .background(LSBackground(auth: true))
        .navigationTitle("Create account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field(_ label: String, text: Binding<String>, secure: Bool = false,
                       keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(LS.textSecondary)
            Group {
                if secure { SecureField("", text: text) }
                else { TextField("", text: text).keyboardType(keyboard).textInputAutocapitalization(keyboard == .emailAddress ? .never : .words) }
            }
            .foregroundStyle(LS.textPrimary)
            .padding(10)
            .background(LS.card, in: RoundedRectangle(cornerRadius: 10))
            .autocorrectionDisabled()
        }
    }
}

private struct ProfileSetupStep: View {
    @EnvironmentObject var model: AppModel
    let name: String
    let email: String

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
                Text("Step 2 of 3").font(.caption).foregroundStyle(LS.cyan)
                Text("Set up your bowler profile").font(.title2.bold()).foregroundStyle(LS.textPrimary)

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
                        .padding(10).background(LS.card, in: RoundedRectangle(cornerRadius: 10))
                }

                if let saveError { Text(saveError).font(.caption).foregroundStyle(LS.bestEffort) }

                NavigationLink { AddBallStep(email: email) } label: {
                    HStack { Text("Next: add your ball"); if saving { ProgressView().tint(.white) } }
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
        // Set the dev user id first so the PUT lands on the right user.
        let devId = devUserId(from: email, name: name)
        if !devId.isEmpty { model.devUser = devId }
        var fields: [String: Any] = [
            "name": name, "email": email, "handedness": handedness, "delivery_style": delivery,
            "dob": ISO8601DateFormatter().string(from: dob),
        ]
        if let n = Int(steps) { fields["approach_steps"] = n }
        model.handed = (handedness == "left") ? "L" : "R"
        do { _ = try await model.makeClient().putProfile(fields) }
        catch { saveError = "Couldn't save profile (you can still continue): \(error.localizedDescription)" }
        saving = false
    }

    private func devUserId(from email: String, name: String) -> String {
        let base = email.split(separator: "@").first.map(String.init) ?? name
        let slug = base.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        return slug.isEmpty ? model.devUser : "dev-\(slug)"
    }
}

private struct AddBallStep: View {
    @EnvironmentObject var model: AppModel
    let email: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Step 3 of 3").font(.caption).foregroundStyle(LS.cyan)
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
                    model.completeOnboarding(devUserId: model.devUser)
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
