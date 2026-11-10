import SwiftUI

struct ServerCarsView: View {
    let library: ContentLibrary
    @Binding var cars: [HostedServerCar]
    let capacity: Int
    @State private var adding = false
    private var total: Int { cars.reduce(0) { $0 + $1.slots } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Автомобили")
                Spacer()
                Text("Мест: \(total) / \(capacity)").font(.caption).foregroundStyle(total > capacity ? Color.orange : Color.secondary)
            }
            ForEach($cars) { $selection in
                if let asset = library.cars.first(where: { $0.id == selection.model }) {
                    ServerCarRow(selection: $selection, asset: asset) {
                        let model = selection.model
                        cars.removeAll { $0.model == model }
                    }
                } else {
                    HStack {
                        Text("Не установлена: \(selection.model)").foregroundStyle(.orange)
                        Spacer()
                        Button("Убрать") { let model = selection.model; cars.removeAll { $0.model == model } }
                    }
                }
            }
            Button("Добавить автомобиль…") { adding = true }
                .disabled(total >= capacity || cars.count >= library.cars.count)
            if total > capacity {
                Text("Уменьшите число мест или выберите трассу с большим числом пит-боксов.").font(.caption).foregroundStyle(.orange)
            }
        }
        .sheet(isPresented: $adding) {
            ServerCarPicker(cars: library.cars.filter { asset in !cars.contains { $0.model == asset.id } }) { asset in
                cars.append(HostedServerCar(model: asset.id, slots: 1))
            }
        }
    }
}

private struct ServerCarRow: View {
    @Binding var selection: HostedServerCar
    let asset: CarAsset
    let remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(asset.name).fontWeight(.medium)
                Spacer()
                Stepper("Мест: \(selection.slots)", value: $selection.slots, in: 1...64).fixedSize()
                Button(action: remove) { Image(systemName: "trash") }.accessibilityLabel("Убрать \(asset.name)")
            }
            DisclosureGroup("Скины по местам · по умолчанию автоматически") {
                ForEach(0..<selection.slots, id: \.self) { slot in
                    Picker("Место \(slot + 1)", selection: Binding(get: { selection.skins[slot] ?? "" }, set: { selection.skins[slot] = $0.nonempty })) {
                        Text("Автоматически").tag("")
                        ForEach(asset.skins) { Text($0.name).tag($0.id) }
                    }
                }
            }.font(.caption)
        }.padding(12).background(Color.white.opacity(0.025)).clipShape(RoundedRectangle(cornerRadius: 10))
            .onChange(of: selection.slots) { count in selection.skins = selection.skins.filter { $0.key < count } }
    }
}

private struct ServerCarPicker: View {
    let cars: [CarAsset]
    let select: (CarAsset) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var filtered: [CarAsset] {
        cars.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Добавить автомобиль").font(.title2); Spacer(); Button("Закрыть") { dismiss() } }
            TextField("Название или ID машины", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filtered) { asset in
                        Button {
                            select(asset); dismiss()
                        } label: {
                            HStack { Text(asset.name); Spacer(); Text(asset.skins.isEmpty ? "Нет скинов" : asset.brand).foregroundStyle(.secondary) }
                                .padding(10).frame(maxWidth: .infinity)
                        }.buttonStyle(.plain).disabled(asset.skins.isEmpty)
                    }
                }
            }
            if filtered.isEmpty { Text("Машины не найдены").foregroundStyle(.secondary) }
        }.padding(24).frame(width: 580, height: 520)
    }
}
