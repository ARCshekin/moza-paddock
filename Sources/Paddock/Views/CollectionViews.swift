import AppKit
import SwiftUI

struct PresetsView: View {
    @ObservedObject var model: PaddockController
    @State private var deleting: DrivePreset?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                SectionLabel(text: "Текущая конфигурация")
                HStack {
                    TextField("Название пресета", text: $model.presetName).textFieldStyle(.roundedBorder)
                    Button("Сохранить") { model.savePreset() }.buttonStyle(.borderedProminent)
                    Button("Как новый") { model.savePreset(asNew: true) }
                }
                HStack {
                    Label(model.car?.name ?? model.configuration.car, systemImage: "car.side")
                    Spacer()
                    Text(model.layout?.name ?? model.configuration.track)
                    Text("· \(model.configuration.mode.title)")
                }.font(.caption).foregroundStyle(.secondary)
                if model.dirty { Label("Есть несохранённые изменения", systemImage: "circle.fill").font(.caption2).foregroundStyle(PaddockStyle.accent) }
            }.paddockPanel()
            if model.presets.isEmpty {
                EmptyPaddock(symbol: "slider.horizontal.3", title: "Первый пресет", detail: "Выберите машину и трассу, настройте руль и сохраните конфигурацию здесь.")
            }
            ForEach(model.presets.sorted { $0.updated > $1.updated }) { preset in
                HStack(spacing: 16) {
                    Image(systemName: "flag.checkered").font(.title2).foregroundStyle(PaddockStyle.accent).frame(width: 34)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(preset.name).font(.system(size: 16, weight: .semibold)); if model.selectedPreset == preset.id { Text("ВЫБРАН").font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(PaddockStyle.accent) } }
                        Text(summary(preset.configuration)).font(.caption).foregroundStyle(.secondary)
                        Text("\(preset.configuration.angle)° · FFB \(Int(preset.configuration.gain * 100))% · \(preset.configuration.bindings.count) кнопок").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(lapText(model.sessions.filter { $0.onlineServer == nil && $0.configuration.fingerprint == preset.configuration.fingerprint }.compactMap(\.bestMilliseconds).min())).font(.system(size: 17, design: .monospaced))
                        Text("лучший круг").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Button("Загрузить") { model.loadPreset(preset) }
                    Button { deleting = preset } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.secondary)
                }.paddockPanel()
            }
        }.confirmationDialog("Удалить пресет? История заездов останется.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Удалить пресет", role: .destructive) { if let preset = deleting { model.deletePreset(preset) }; deleting = nil }
            Button("Отмена", role: .cancel) { deleting = nil }
        }
    }
    private func summary(_ c: DriveConfiguration) -> String {
        let car = model.library.cars.first { $0.id == c.car }?.name ?? c.car
        let track = model.library.tracks.first { $0.id == c.track }?.layouts.first { $0.id == c.layout }?.name ?? c.track
        return "\(car) · \(track) · \(c.mode.title)"
    }
}

struct ModsView: View {
    @ObservedObject var model: PaddockController
    @State private var confirmInstall = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 18) {
                Image(systemName: "shippingbox").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(PaddockStyle.accent)
                Text("Добавьте что-нибудь в гараж").font(.system(size: 23, weight: .semibold))
                Text("ZIP, 7z, RAR или папка с автомобилями и трассами.\nСначала проверим состав, затем установим выбранный пакет.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Выбрать архив или папку…") { model.chooseMod() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.operation != nil)
                Text("Скины отдельно, CSP и сторонние приложения пока не устанавливаются.").font(.caption2).foregroundStyle(.tertiary)
            }.frame(maxWidth: .infinity).padding(.vertical, 25).paddockPanel()
                .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
                    guard model.operation == nil, let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in if let url { DispatchQueue.main.async { model.inspectMod(url) } } }
                    return true
                }
            if let source = model.modSource {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        SectionLabel(text: "План установки")
                        Spacer()
                        Button("Отмена") { model.modSource = nil; model.modPlan = [] }.disabled(model.operation != nil)
                    }
                    Text(source.lastPathComponent).font(.headline).textSelection(.enabled)
                    ForEach(model.modPlan) { item in
                        HStack {
                            Image(systemName: item.kind == "cars" ? "car.side" : "road.lanes").frame(width: 22).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) { Text(item.id).font(.system(size: 13, weight: .medium)); Text(item.destination).font(.caption2).foregroundStyle(.secondary) }
                            Spacer()
                            Text(item.replaces ? "Заменит установленный" : "Новый").font(.caption).foregroundStyle(item.replaces ? Color.orange : Color.green)
                        }
                    }
                    if !model.modPlan.isEmpty {
                        HStack {
                            Text("Предыдущие версии сохранятся в резервной копии.").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Установить \(model.modPlan.count)") { confirmInstall = true }.buttonStyle(.borderedProminent).disabled(model.gameRunning || model.operation != nil)
                        }
                    }
                    if model.gameRunning { Text("Для установки завершите текущий заезд.").font(.caption).foregroundStyle(.orange) }
                }.paddockPanel()
            }
            HStack(spacing: 18) {
                Label("\(model.library.cars.count) автомобилей", systemImage: "car.side")
                Label("\(model.library.tracks.count) трасс", systemImage: "road.lanes")
                Spacer()
                Button("Обновить библиотеку") { model.reload() }.disabled(model.operation != nil)
                Button("Резервные копии") { NSWorkspace.shared.open(model.paths.store.appendingPathComponent("ModBackups")) }
            }.font(.caption).foregroundStyle(.secondary)
        }.confirmationDialog("Установить найденные моды? Существующие версии будут сохранены в резервной копии.", isPresented: $confirmInstall) {
            Button("Установить") { model.installMod() }
            Button("Отмена", role: .cancel) {}
        }
    }
}

struct RecordsView: View {
    @ObservedObject var model: PaddockController
    @ObservedObject private var timing: SessionLiveState
    init(model: PaddockController) { self.model = model; timing = model.timing }
    @State private var currentOnly = false
    var filtered: [SessionContext] {
        model.sessions.filter { !currentOnly || $0.onlineServer == nil && $0.configuration.fingerprint == model.configuration.fingerprint }.sorted { $0.started > $1.started }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                metric("ТЕКУЩИЙ КРУГ", lapText(model.liveLap))
                metric("ЛУЧШИЙ В ЗАЕЗДЕ", lapText(model.liveBest))
                metric("ЗАЕЗДОВ", "\(model.sessions.count)")
            }
            HStack {
                Toggle("Только текущая конфигурация", isOn: $currentOnly).toggleStyle(.switch).font(.caption)
                Spacer()
                Button("Экспорт JSON…") { model.exportRecords() }.disabled(model.sessions.isEmpty)
            }
            if filtered.isEmpty { EmptyPaddock(symbol: "stopwatch", title: "Каждый круг на счету", detail: "Запустите заезд из Paddock. Лучшее время игры и завершённые круги сохранятся автоматически.") }
            ForEach(filtered) { session in SessionRecordCard(session: session) }
            Text("Личный рекорд берётся из лучшего времени Assetto Corsa. Для остальных кругов статус зачёта не подтверждается. Изменение настроек создаёт отдельную конфигурацию для сравнения; старые результаты сохраняются. Для автоматической записи Paddock должен работать; окно можно свернуть.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 14) { SectionLabel(text: title); Text(value).font(.system(size: 25, weight: .medium, design: .monospaced)) }
            .frame(maxWidth: .infinity, alignment: .leading).paddockPanel()
    }
}

struct SessionRecordCard: View {
    let session: SessionContext
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.onlineServer.map { "Онлайн · " + $0 } ?? session.presetName).font(.system(size: 16, weight: .semibold))
                    Text("\(session.carName) · \(session.trackName)").font(.caption).foregroundStyle(.secondary)
                    Text("\(session.configuration.mode.title) · \(session.configuration.angle)° · FFB \(Int(session.configuration.gain * 100))% · \(session.configuration.temperature) °C")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(lapText(session.bestMilliseconds)).font(.system(size: 24, weight: .medium, design: .monospaced)).foregroundStyle(PaddockStyle.accent)
                    Text(session.started, style: .date).font(.caption2).foregroundStyle(.secondary)
                }
            }
            DisclosureGroup("Круги: \(session.laps.count) · конфигурация \(String(session.configuration.fingerprint.prefix(8)))", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(session.configuration.car) / \(session.configuration.track) / \(session.configuration.layout.nonempty ?? "default") · \(session.configuration.weather)").font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                    ForEach(session.laps) { lap in
                        HStack { Text("Круг \(lap.number)"); Spacer(); Text(lapText(lap.milliseconds)).monospacedDigit(); Text(lap.matchedGameBest ? "Лучший в момент записи" : "Зачёт не подтверждён").foregroundStyle(.secondary).frame(width: 160, alignment: .trailing) }.font(.caption)
                    }
                }.padding(.top, 12)
            }.font(.caption).foregroundStyle(.secondary)
        }.paddockPanel()
    }
}

struct EmptyPaddock: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 36, weight: .ultraLight)).foregroundStyle(PaddockStyle.accent.opacity(0.8))
            Text(title).font(.title3.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
        }.frame(maxWidth: .infinity).padding(.vertical, 38).paddockPanel()
    }
}
