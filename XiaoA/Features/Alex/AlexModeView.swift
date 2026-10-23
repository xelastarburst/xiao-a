import SwiftUI
import PhotosUI

/// Settings, for her family. English UI on purpose: the family sets the app up.
struct AlexModeView: View {
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var app: AppState

    @State private var openAIKey = ""
    @State private var anthropicKey = ""
    @State private var keyStatus = ""
    @State private var testingKeys = false
    @State private var keyResults: [KeyCheck.Result] = []
    @State private var editingPlace: Place?
    @State private var showTranslationPrep = false
    @State private var frontItem: PhotosPickerItem?
    @State private var backItem: PhotosPickerItem?
    @State private var newPIN = ""
    @State private var pinStatus = ""
    @AppStorage("demoSound") private var demoSound = false
    @AppStorage(InterpreterVoice.herKey) private var voiceForHer = InterpreterVoice.defaultID
    @AppStorage(InterpreterVoice.othersKey) private var voiceForOthers = InterpreterVoice.defaultID

    var body: some View {
        Form {
            Section {
                LabeledField("What the app calls her", text: $store.config.herName, prompt: "e.g. Frau Weber or Oma Inge")
                LabeledField("Full name in English", text: $store.config.herNameEN, prompt: "For the medical card")
                LabeledField("Her phone", text: $store.config.herPhone, prompt: "+1 408 555 0100", keyboard: .phonePad)
            } header: {
                Text("Her")
            } footer: {
                Text("The home screen greets her with “Guten Morgen, …!”. Leave the first field empty for no name.")
            }

            Section {
                LabeledField("Name she knows you by", text: $store.config.contactName, prompt: "e.g. Sabine")
                LabeledField("Your phone", text: $store.config.contactPhone, prompt: "+1 408 555 0199", keyboard: .phonePad)
            } header: {
                Text("Her family contact")
            } footer: {
                Text("Notfall calls and texts, ride requests and “send to family” in Fragen all go to this number. Until a name is set, the app says “Ihre Familie”.")
            }

            Section {
                StackedField("Home address in English", text: $store.config.homeAddressEN,
                             prompt: "123 Main St, San Jose, CA 95112")
                StackedField("Home address as she says it (optional)", text: $store.config.homeAddressDE,
                             prompt: "123 Main Street, San Jose")
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
                                Text(place.nameDE).foregroundStyle(.primary)
                                Text(place.addressEN).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: place.icon)
                        }
                    }
                }
                .onDelete { store.config.places.remove(atOffsets: $0) }
                Button {
                    editingPlace = Place(nameDE: "", addressEN: "")
                } label: {
                    Label("Add a place", systemImage: "plus")
                }
            } header: {
                Text("Places for rides")
            } footer: {
                Text("Home is added automatically. Use short German names she recognizes, like Supermarkt or Arztpraxis.")
            }

            medicalSection

            Section {
                SecureField("OpenAI API key (interpreter)", text: $openAIKey)
                Text("OpenAI: \(APIKeys.masked(.openAI))").font(.caption).foregroundStyle(.secondary)
                SecureField("Claude API key (Fragen, Lesen, interpreter)", text: $anthropicKey)
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
                Button(testingKeys ? "Testing keys…" : "Test keys") {
                    testingKeys = true
                    Task {
                        keyResults = await KeyCheck.run()
                        testingKeys = false
                    }
                }
                .disabled(testingKeys)
                ForEach(keyResults) { result in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.label)
                            Text(result.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(result.ok ? .green : .red)
                    }
                }
            } header: {
                Text("API keys")
            } footer: {
                Text("Stored in the Keychain on this phone only. Leave a field empty to keep the saved key. A phone with no saved key uses the keys built into the app (BundledKeys.json on the Mac it was built on).")
            }

            Section {
                NavigationLink {
                    VoiceChooser(title: "Her words", key: InterpreterVoice.herKey, toHer: false)
                } label: {
                    LabeledContent("Her words (English/Chinese)", value: InterpreterVoice.named(voiceForHer).name)
                }
                NavigationLink {
                    VoiceChooser(title: "Others' words", key: InterpreterVoice.othersKey, toHer: true)
                } label: {
                    LabeledContent("Others' words (German)", value: InterpreterVoice.named(voiceForOthers).name)
                }
            } header: {
                Text("Interpreter voices")
            } footer: {
                Text("The voice the Dolmetscher uses for each side. Tap a side to hear the voices and pick one.")
            }

            Section {
                TextField("e.g. She lives in San Jose. She shops at Trader Joe's on Saturdays. Her doctor is Dr. Lee.",
                          text: $store.config.askContext, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("What Helferlein should know (Fragen)")
            } footer: {
                Text("Sent to Claude with her questions so answers feel personal. Medical card details are never sent.")
            }

            Section("Rides") {
                NavigationLink("Send car details to her") { RideDetailsComposer() }
            }

            Section {
                Button("Download offline translation (English → German)") { showTranslationPrep = true }
                Button("Run an emergency practice drill") { app.go(.emergency(practice: true)) }
            } header: {
                Text("Setup")
            } footer: {
                Text("Do the download on Wi-Fi so Lesen works without data. The drill never calls anyone.")
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
                Text("Settings PIN")
            } footer: {
                Text("To open Settings: long-press the little orange on the home screen for 2 seconds.")
            }

            #if DEBUG && targetEnvironment(simulator)
            Section {
                Button("Fill in sample details") { store.config = AppConfig.simulatorSample }
                Toggle("Sound in the simulator", isOn: $demoSound)
            } header: {
                Text("Simulator testing")
            } footer: {
                Text("Only in the simulator. Without API keys, Lesen, Fragen and the Dolmetscher play a short scripted demo, marked Beispiel. Sound is off so the Mac stays quiet.")
            }
            #endif
        }
        .navigationTitle("Settings")
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
    }

    private var medicalSection: some View {
        Section {
            LabeledField("Insurer", text: $store.config.medical.insurer, prompt: "e.g. IMG Patriot")
            LabeledField("Policy number", text: $store.config.medical.policyNumber, prompt: "")
            LabeledField("Member ID", text: $store.config.medical.memberID, prompt: "")
            LabeledField("Insurer phone", text: $store.config.medical.insurerPhone, prompt: "", keyboard: .phonePad)
            StackedField("Conditions (English, for staff)", text: $store.config.medical.conditionsEN)
            StackedField("Conditions (German, for her)", text: $store.config.medical.conditionsDE)
            StackedField("Medications (English)", text: $store.config.medical.medicationsEN)
            StackedField("Medications (German)", text: $store.config.medical.medicationsDE)
            StackedField("Allergies (English)", text: $store.config.medical.allergiesEN)
            StackedField("Allergies (German)", text: $store.config.medical.allergiesDE)
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
                    TextField("Name she sees, in German (e.g. Supermarkt)", text: $place.nameDE)
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
                    .disabled(place.nameDE.isEmpty || place.addressEN.isEmpty)
                }
            }
        }
    }
}
