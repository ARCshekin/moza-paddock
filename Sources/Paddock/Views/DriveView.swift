import AppKit
import SwiftUI

struct DriveView: View {
    @ObservedObject var model: PaddockController
    @State private var chooseCar = false
    @State private var chooseTrack = false
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 16) { carCard; trackCard }
            HStack(alignment: .top, spacing: 16) {
                sessionPanel.frame(maxWidth: .infinity)
                conditionsPanel.frame(maxWidth: .infinity)
            }

        }
        .sheet(isPresented: $chooseCar) { ContentPicker(model: model, kind: .car) }
        .sheet(isPresented: $chooseTrack) { ContentPicker(model: model, kind: .track) }
    }
    private var carCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                AssetPicture(url: model.car?.skins.first(where: { $0.id == model.configuration.skin })?.preview ?? model.car?.preview).frame(height: 175)
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.car?.brand.uppercased() ?? "ГАРАЖ").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(PaddockStyle.accent)
                    Text(model.car?.name ?? "Выберите машину").font(.system(size: 21, weight: .bold)).lineLimit(1)
                }.padding(16)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(text: "Автомобиль")
                    Spacer()
                    Button("Выбрать…") { chooseCar = true }.buttonStyle(.plain).foregroundStyle(PaddockStyle.accent)
                }
                Picker("Ливрея", selection: $model.configuration.skin) {
                    ForEach(model.car?.skins ?? []) { Text($0.name).tag($0.id) }
                }
            }.padding(16)
        }.background(Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 16)).frame(maxWidth: .infinity)
    }
    private var trackCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                AssetPicture(url: model.layout?.preview, symbol: "road.lanes").frame(height: 175)
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(model.layout?.length ?? "") м").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                        Text(model.track?.name ?? "Выберите трассу").font(.system(size: 21, weight: .bold)).lineLimit(1)
                    }
                    Spacer()
                    if let url = model.layout?.outline, let image = NSImage(contentsOf: url) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 70, height: 60)
                    }
                }.padding(16)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(text: "Трасса")
                    Spacer()
                    Button("Выбрать…") { chooseTrack = true }.buttonStyle(.plain).foregroundStyle(PaddockStyle.accent)
                }
                Picker("Конфигурация", selection: $model.configuration.layout) {
                    ForEach(model.track?.layouts ?? []) { Text($0.name).tag($0.id) }
                }
            }.padding(16)
        }.background(Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 16)).frame(maxWidth: .infinity)
    }
    private var sessionPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: "Формат заезда")
            Picker("Режим", selection: $model.configuration.mode) { ForEach(DriveMode.allCases) { Text($0.title).tag($0) } }
            if model.configuration.mode == .race {
                Stepper("Соперники: \(model.configuration.opponents)", value: $model.configuration.opponents, in: 1...max(1, min(24, (model.layout?.pits ?? 2) - 1)))
                Stepper("Уровень AI: \(model.configuration.ai)%", value: $model.configuration.ai, in: 50...100)
                Stepper("Кругов: \(model.configuration.laps)", value: $model.configuration.laps, in: 1...99)
                if model.layout?.hasAI != true { Text("В этой конфигурации нет AI-линии.").font(.caption).foregroundStyle(.orange) }
            } else {
                Stepper("Длительность: \(model.configuration.minutes) мин", value: $model.configuration.minutes, in: 5...180, step: 5)
            }
            Picker("Сетап авто", selection: $model.configuration.setup) {
                Text("По умолчанию").tag("")
                ForEach(model.setups, id: \.self) { Text($0).tag($0) }
            }
            Toggle("Автосцепление", isOn: $model.configuration.autoClutch)
            Toggle("Автоматические передачи", isOn: $model.configuration.autoShift)
            Toggle("Правила и штрафы", isOn: $model.configuration.penalties)
        }.font(.system(size: 12)).paddockPanel()
    }
    private var conditionsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: "Условия и помощники")
            Picker("Погода", selection: $model.configuration.weather) { ForEach(model.library.weather) { Text($0.name).tag($0.id) } }
            HStack { Text("Время"); Spacer(); Text(String(format: "%02d:%02d", Int(model.configuration.hour), Int(model.configuration.hour.truncatingRemainder(dividingBy: 1) * 60))).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: $model.configuration.hour, in: 8...18, step: 0.5)
            Stepper("Воздух: \(model.configuration.temperature) °C", value: $model.configuration.temperature, in: 10...36)
            Picker("ABS", selection: $model.configuration.abs) { Text("Выкл.").tag(0); Text("Заводской").tag(1); Text("Вкл.").tag(2) }
            Picker("Traction Control", selection: $model.configuration.traction) { Text("Выкл.").tag(0); Text("Заводской").tag(1); Text("Вкл.").tag(2) }
            HStack { Image(systemName: "info.circle"); Text("Условия входят в пресет и учитываются при сравнении рекордов.") }.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: 12)).paddockPanel()
    }
}

struct ContentPicker: View {
    enum Kind { case car, track }
    @ObservedObject var model: PaddockController
    let kind: Kind
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(kind == .car ? "Гараж" : "Трассы").font(.title2.bold()); Spacer(); Button("Готово") { dismiss() } }
            TextField(kind == .car ? "Название, производитель, класс или тег…" : "Название или страна…", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 8) {
                    if kind == .car {
                        ForEach(model.library.cars.filter { search.isEmpty || ([$0.name, $0.id] + $0.badges).joined(separator: " ").localizedCaseInsensitiveContains(search) }) { car in
                            Button {
                                model.configuration.car = car.id; model.configuration.skin = car.skins.first?.id ?? ""; model.configuration.setup = ""; model.persist(); dismiss()
                            } label: {
                                HStack(spacing: 16) {
                                    AssetPicture(url: car.preview).frame(width: 140, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(car.name).fontWeight(.semibold)
                                        ContentBadges(values: car.badges)
                                        Text([car.power, car.weight].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if model.configuration.car == car.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(PaddockStyle.accent) }
                                }.padding(8).background(Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                    } else {
                        ForEach(model.library.tracks.filter { search.isEmpty || ([$0.name, $0.id] + $0.countries).joined(separator: " ").localizedCaseInsensitiveContains(search) }) { track in
                            Button {
                                model.configuration.track = track.id; model.configuration.layout = track.layouts.first?.id ?? ""; model.configuration.setup = ""; model.persist(); dismiss()
                            } label: {
                                HStack(spacing: 16) {
                                    AssetPicture(url: track.layouts.first?.preview, symbol: "road.lanes").frame(width: 140, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(track.name).fontWeight(.semibold)
                                        ContentBadges(values: track.countries)
                                        Text("Конфигураций: \(track.layouts.count)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if model.configuration.track == track.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(PaddockStyle.accent) }
                                }.padding(8).background(Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Text(kind == .car ? "Установлено автомобилей: \(model.library.cars.count)" : "Установлено трасс: \(model.library.tracks.count)").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 650, height: 590).preferredColorScheme(.dark)
    }
}


struct DriveLaunchBar: View {
    @ObservedObject var model: PaddockController
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    SectionLabel(text: "Личный рекорд · эта конфигурация")
                    Text(lapText(model.currentBest)).font(.system(size: 24, weight: .medium, design: .monospaced))
                }
                Spacer()
                if model.gameRunning {
                    Button("Завершить заезд", role: .destructive) { model.stopGame() }.controlSize(.large)
                } else {
                    Button { model.launch() } label: {
                        HStack(spacing: 14) { Text("Поехали").fontWeight(.bold); Image(systemName: "arrow.up.right") }.padding(.horizontal, 22).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.operation != nil || model.car == nil || model.track == nil)
                }
            }.padding(18).background(PaddockStyle.accent.opacity(0.09)).clipShape(RoundedRectangle(cornerRadius: 16))
            HStack {
                Label("Внешний экран · без рамок", systemImage: "display")
                Spacer()
                Text("\(model.configuration.angle)° · FFB \(Int(model.configuration.gain * 100))%")
                Text(model.activePreset?.name ?? "Без пресета").foregroundStyle(PaddockStyle.accent).lineLimit(1)
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Adaptive rows keep long mod tags readable within the selection sheet.
struct ContentBadges: View {
    let values: [String]
    var body: some View {
        if !values.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)], alignment: .leading, spacing: 4) {
                ForEach(values, id: \.self) { value in
                    Text(value).font(.caption2).foregroundStyle(PaddockStyle.accent)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(PaddockStyle.accent.opacity(0.1), in: Capsule())
                }
            }
        }
    }
}
