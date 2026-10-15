import SwiftUI
import PhotosUI

/// Alex's settings. English UI on purpose: only Alex uses this.
struct AlexModeView: View {
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var learning: LearningStore
    @EnvironmentObject private var app: AppState

    @State private var openAIKey = ""
    @State private var anthropicKey = ""
    @State private var keyStatus = ""
    @State private var editingPlace: Place?
    @State private var showTranslationPrep = false
    @State private var frontItem: PhotosPickerItem?
    @State private var backItem: PhotosPickerItem?
    @State private var newPIN = ""
    @State private var pinStatus = ""
    @AppStorage("demoSound") private var demoSound = false
    @AppStorage(InterpreterVoice.momKey) private var voiceForMom = InterpreterVoice.defaultID
    @AppStorage(LearnSpeed.key) private var learnSpeed = LearnSpeed.slow.rawValue
    @AppStorage(InterpreterVoice.othersKey) private var voiceForOthers = InterpreterVoice.defaultID

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: store.config.reminderHour,
                                  minute: store.config.reminderMinute, second: 0, of: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            store.config.reminderHour = parts.hour ?? 10
            store.config.reminderMinute = parts.minute ?? 0
        }
    }

    var body: some View {
        Form {
            Section("Mom") {
                LabeledField("Name in Chinese", text: $store.config.momNameZH, prompt: "妈妈")
                LabeledField("Name in English", text: $store.config.momNameEN, prompt: "Used in lessons and the medical card")
                LabeledField("Mom's phone", text: $store.config.momPhone, prompt: "+1 408 555 0100", keyboard: .phonePad)
            }

            Section {
                LabeledField("Your name", text: $store.config.alexName, prompt: "Alex")
                LabeledField("Your phone", text: $store.config.alexPhone, prompt: "+1 408 555 0199", keyboard: .phonePad)
            } header: {
                Text("You")
            } footer: {
                Text("Call Alex, Text Alex, ride requests and Ask Alex all go to this number.")
            }

            Section {
                StackedField("Home address in English", text: $store.config.homeAddressEN,
                             prompt: "123 Main St, San Jose, CA 95112")
                StackedField("Home address in Chinese (optional)", text: $store.config.homeAddressZH,
                             prompt: "圣何塞 Main 街 123 号")
            } header: {
                Text("Home")
            } footer: {
                Text("Shown in big English to drivers and strangers, and read aloud on the 911 screen.")
            }

            Section {
                ForEach(store.config.places) { place in
                    Button {
                        editingPlace = place
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(place.nameZH).foregroundStyle(.primary)
                                Text(place.addressEN).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: place.icon)
                        }
                    }
                }
                .onDelete { store.config.places.remove(atOffsets: $0) }
                Button {
                    editingPlace = Place(nameZH: "", addressEN: "")
                } label: {
                    Label("Add a place", systemImage: "plus")
                }
            } header: {
                Text("Places for rides")
            } footer: {
                Text("Home is added automatically. Use short Chinese names Mom recognizes, like 超市 or 公园.")
            }

            medicalSection

            Section {
                SecureField("OpenAI API key (interpreter)", text: $openAIKey)
                Text("OpenAI: \(APIKeys.masked(.openAI))").font(.caption).foregroundStyle(.secondary)
                SecureField("Claude API key (Ask, coach tips)", text: $anthropicKey)
                Text("Claude: \(APIKeys.masked(.anthropic))").font(.caption).foregroundStyle(.secondary)
                Button("Save keys") {
                    if !openAIKey.isEmpty { APIKeys.set(openAIKey, for: .openAI) }
                    if !anthropicKey.isEmpty { APIKeys.set(anthropicKey, for: .anthropic) }
                    openAIKey = ""
                    anthropicKey = ""
                    keyStatus = "Saved to this iPhone's Keychain."
                }
                .disabled(openAIKey.isEmpty && anthropicKey.isEmpty)
                if !keyStatus.isEmpty {
                    Text(keyStatus).font(.caption).foregroundStyle(.green)
                }
            } header: {
                Text("API keys")
            } footer: {
                Text("Stored in the Keychain on this phone only. Leave a field empty to keep the saved key. A phone with no saved key uses the keys built into the app (BundledKeys.json on Alex's Mac).")
            }

            Section {
                NavigationLink {
                    VoiceChooser(title: "Mom's words", key: InterpreterVoice.momKey, chinese: false)
                } label: {
                    LabeledContent("Mom's words (English/German)", value: InterpreterVoice.named(voiceForMom).name)
                }
                NavigationLink {
                    VoiceChooser(title: "Others' words", key: InterpreterVoice.othersKey, chinese: true)
                } label: {
                    LabeledContent("Others' words (Chinese)", value: InterpreterVoice.named(voiceForOthers).name)
                }
            } header: {
                Text("Interpreter voices")
            } footer: {
                Text("The voice 翻译官 uses for each side. Tap a side to hear the voices and pick one.")
            }

            Section {
                TextField("e.g. We live in San Jose. She shops at 99 Ranch on Saturdays. Her doctor is Dr. Lee.",
                          text: $store.config.askContext, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("What 小A should know (Ask)")
            } footer: {
                Text("Sent to Claude with Mom's questions so answers feel personal. Medical card details are never sent.")
            }

            learningSection

            Section("Rides") {
                NavigationLink("Send car details to Mom") { RideDetailsComposer() }
            }

            Section {
                Button("Download offline translation (English → Chinese)") { showTranslationPrep = true }
                Button("Run an emergency practice drill") { app.go(.emergency(practice: true)) }
            } header: {
                Text("Setup")
            } footer: {
                Text("Do the download on Wi-Fi so 看一看 works without data. The drill never calls anyone.")
            }

            Section {
                SecureField(store.config.pin.isEmpty ? "Set a PIN" : "New PIN", text: $newPIN)
                    .keyboardType(.numberPad)
                Button("Save PIN") {
                    store.config.pin = newPIN
                    newPIN = ""
                    pinStatus = store.config.pin.isEmpty ? "PIN removed." : "PIN saved."
                }
                if !pinStatus.isEmpty {
                    Text(pinStatus).font(.caption).foregroundStyle(.green)
                }
            } header: {
                Text("Alex mode PIN")
            } footer: {
                Text("To open Alex mode: long-press 小A on the home screen for 2 seconds.")
            }

            #if DEBUG && targetEnvironment(simulator)
            Section {
                Button("Fill in sample details") { store.config = AppConfig.simulatorSample }
                Toggle("Sound in the simulator", isOn: $demoSound)
            } header: {
                Text("Simulator testing")
            } footer: {
                Text("Only in the simulator. Without API keys, Look, Ask, the interpreter and the coach's microphone play a short scripted demo, marked 模拟器示例. Sound is off so the Mac stays quiet.")
            }
            #endif
        }
        .navigationTitle("Alex mode")
        .sheet(item: $editingPlace) { place in
            PlaceEditor(place: place) { saved in
                if let i = store.config.places.firstIndex(where: { $0.id == saved.id }) {
                    store.config.places[i] = saved
                } else {
                    store.config.places.append(saved)
                }
            }
        }
        .sheet(isPresented: $showTranslationPrep) { TranslationPrepView() }
        .onChange(of: frontItem) { _, item in load(item, side: .front) }
        .onChange(of: backItem) { _, item in load(item, side: .back) }
        .onDisappear {
            LessonReminder.reschedule(hour: store.config.reminderHour,
                                      minute: store.config.reminderMinute,
                                      enabled: store.config.remindersOn)
        }
    }

    private var medicalSection: some View {
        Section {
            LabeledField("Insurer", text: $store.config.medical.insurer, prompt: "e.g. IMG Patriot")
            LabeledField("Policy number", text: $store.config.medical.policyNumber, prompt: "")
            LabeledField("Member ID", text: $store.config.medical.memberID, prompt: "")
            LabeledField("Insurer phone", text: $store.config.medical.insurerPhone, prompt: "", keyboard: .phonePad)
            StackedField("Conditions (English, for staff)", text: $store.config.medical.conditionsEN)
            StackedField("Conditions (Chinese, for Mom)", text: $store.config.medical.conditionsZH)
            StackedField("Medications (English)", text: $store.config.medical.medicationsEN)
            StackedField("Medications (Chinese)", text: $store.config.medical.medicationsZH)
            StackedField("Allergies (English)", text: $store.config.medical.allergiesEN)
            StackedField("Allergies (Chinese)", text: $store.config.medical.allergiesZH)
            LabeledField("Doctor", text: $store.config.medical.doctorName, prompt: "")
            LabeledField("Doctor phone", text: $store.config.medical.doctorPhone, prompt: "", keyboard: .phonePad)
            cardRow("Insurance card (front)", side: .front, selection: $frontItem)
            cardRow("Insurance card (back)", side: .back, selection: $backItem)
        } header: {
            Text("Medical card")
        } footer: {
            Text("Kept only on this iPhone, encrypted while it's locked. Never sent to any AI.")
        }
    }

    private func cardRow(_ title: String, side: CardSide, selection: Binding<PhotosPickerItem?>) -> some View {
        HStack {
            if let image = store.cardImage(side) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 64, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            PhotosPicker(title, selection: selection, matching: .images)
            Spacer()
            if store.cardImage(side) != nil {
                Button(role: .destructive) { store.removeCard(side) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
        }
    }

    private var learningSection: some View {
        Section {
            Toggle("Daily reminder", isOn: $store.config.remindersOn)
            if store.config.remindersOn {
                DatePicker("Reminder time", selection: reminderTime, displayedComponents: .hourAndMinute)
            }
            Stepper("New phrases per day: \(store.config.newPhrasesPerDay)",
                    value: $store.config.newPhrasesPerDay, in: 2...10)
            Toggle("Strict pronunciation", isOn: $store.config.strictPronunciation)
            Picker("English reading speed", selection: $learnSpeed) {
                ForEach(LearnSpeed.allCases) { speed in
                    Text(speed.label).tag(speed.rawValue)
                }
            }
            LabeledContent("Days completed", value: "\(learning.data.daysDone.count)")
            LabeledContent("Current streak", value: "\(learning.streak) days")
            LabeledContent("Phrases learned", value: "\(learning.masteredCount) of \(learning.allPhrases(for: store.config).count)")
            let struggling = learning.strugglingPhrases(for: store.config)
            if !struggling.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Needs practice").font(.subheadline.bold())
                    ForEach(struggling) { p in
                        Text("\(p.en)  ·  \(p.zh)").font(.callout)
                    }
                }
            }
        } header: {
            Text("Learning")
        } footer: {
            Text("Lessons are hands-free: 小A reads the phrase, listens, and keeps coaching until she says it. Normal: passes when speech recognition clearly understands her. Strict: every word must be recognized.")
        }
    }

    private func load(_ item: PhotosPickerItem?, side: CardSide) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                store.saveCard(data, side: side)
            }
        }
    }
}

private struct LabeledField: View {
    var title: String
    @Binding var text: String
    var prompt: String
    var keyboard: UIKeyboardType = .default

    init(_ title: String, text: Binding<String>, prompt: String, keyboard: UIKeyboardType = .default) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.keyboard = keyboard
    }

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: $text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
        }
    }
}

/// A caption above a multi-line field, so the label stays visible after the field is filled in.
private struct StackedField: View {
    var title: String
    @Binding var text: String
    var prompt: String

    init(_ title: String, text: Binding<String>, prompt: String = "") {
        self.title = title
        self._text = text
        self.prompt = prompt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: $text, prompt: Text(prompt.isEmpty ? title : prompt), axis: .vertical)
        }
        .padding(.vertical, 2)
    }
}

private struct PlaceEditor: View {
    @State var place: Place
    var onSave: (Place) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name Mom sees, in Chinese (e.g. 超市)", text: $place.nameZH)
                    TextField("Address in English", text: $place.addressEN, axis: .vertical)
                } footer: {
                    Text("The English address is shown to the driver and sent with ride requests.")
                }
                Picker("Icon", selection: $place.icon) {
                    ForEach(Place.iconChoices, id: \.symbol) { choice in
                        Label(choice.label, systemImage: choice.symbol).tag(choice.symbol)
                    }
                }
            }
            .navigationTitle("Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(place)
                        dismiss()
                    }
                    .disabled(place.nameZH.isEmpty || place.addressEN.isEmpty)
                }
            }
        }
    }
}
