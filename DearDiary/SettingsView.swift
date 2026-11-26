import SwiftUI
import CoreLocation

/// Opened from the city toggle in the title: which city the diary addresses
/// (also used to skip photos taken elsewhere).
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var newCity = ""
    @State private var adding = false
    @State private var cityError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("City") {
                    ForEach(state.cities) { city in
                        Button {
                            Haptics.tap()
                            state.city = city.name
                        } label: {
                            HStack {
                                Text("dear \(city.name) diary,")
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                if state.city == city.name {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        guard state.cities.count > offsets.count else { return }
                        state.cities.remove(atOffsets: offsets)
                        if state.currentCity == nil, let first = state.cities.first {
                            state.city = first.name
                        }
                    }

                    HStack {
                        TextField("Add a city", text: $newCity)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { Task { await addCity() } }
                        if adding {
                            ProgressView()
                        } else {
                            Button("Add") { Task { await addCity() } }
                                .disabled(newCity.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    if let cityError {
                        Text(cityError)
                            .font(.footnote)
                            .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.5))
                    }
                }
            }
            .navigationTitle("City")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Finds the city on the map, adds it and selects it.
    @MainActor
    private func addCity() async {
        let query = newCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        adding = true
        cityError = nil
        defer { adding = false }
        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(query)
            guard let place = placemarks.first, let location = place.location else {
                cityError = "Couldn't find \(query)."
                return
            }
            let name = (place.locality ?? query).lowercased()
            let city = DiaryCity(name: name,
                                 latitude: location.coordinate.latitude,
                                 longitude: location.coordinate.longitude)
            if !state.cities.contains(where: { $0.name == name }) {
                state.cities.append(city)
            }
            Haptics.success()
            state.city = name
            newCity = ""
        } catch {
            cityError = "Couldn't find \(query). Check the spelling or your connection."
        }
    }
}

struct LookSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) {
        self.title = title
        self._value = value
        self.range = range
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}
