import AppKit
import SwiftUI

@main
struct PaddockEntry {
    static func main() {
        if CommandLine.arguments.contains("--server-live-check") {
            do { try ServerLiveChecks.run(); exit(0) }
            catch { fputs("Server live check failed: \(error)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--self-test") {
            do { try PaddockChecks.run(includeInstalledGame: !CommandLine.arguments.contains("--without-game")); exit(0) }
            catch { fputs("Paddock check failed: \(error)\n", stderr); exit(1) }
        }
        PaddockApplication.main()
    }
}

struct PaddockApplication: App {
    @NSApplicationDelegateAdaptor(PaddockDelegate.self) var delegate
    @StateObject private var model = PaddockController()
    var body: some Scene {
        WindowGroup("MOZA Paddock") { PaddockShell(model: model).frame(minWidth: 980, minHeight: 690) }
            .defaultSize(width: 1140, height: 800)
            .windowStyle(.hiddenTitleBar)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}

final class PaddockDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum PaddockTab: String, CaseIterable, Identifiable {
    case drive = "Заезд", online = "Каталог серверов", serverHost = "Свой сервер", wheel = "Руль и кнопки", presets = "Пресеты", mods = "Моды", records = "Рекорды", runtime = "Запуск"
    var id: String { rawValue }
    var sidebarTitle: String { self == .online ? "Серверы" : self == .wheel ? "Руль" : rawValue }
    var symbol: String {
        switch self { case .serverHost: return "server.rack"; case .online: return "network"; case .drive: return "flag.checkered"; case .wheel: return "steeringwheel"; case .presets: return "slider.horizontal.3"; case .mods: return "shippingbox"; case .records: return "stopwatch"; case .runtime: return "desktopcomputer" }
    }
    var subtitle: String {
        switch self {
        case .serverHost: return "Тренировка для друзей на своём компьютере"
        case .online: return "Серверы, свободные машины и подключение"
        case .runtime: return "Wine, Steam и независимый запуск игры"
        case .drive: return "Машина, трасса и условия следующего заезда"
        case .wheel: return "MOZA R5 · живой ввод и назначения"
        case .presets: return "Сохранённые конфигурации для быстрого старта"
        case .mods: return "Автомобили и трассы из архивов или папок"
        case .records: return "Результаты из игры, отдельно для каждой конфигурации"
        }
    }
}

enum PaddockNavigation {
    static let groups: [(title: String, symbol: String, items: [PaddockTab])] = [
        ("Онлайн", "network", [.online, .serverHost]),
        ("Библиотека", "square.stack", [.presets, .mods, .records]),
        ("Настройки", "gearshape", [.wheel, .runtime])
    ]
}

enum PaddockStyle {
    static let accent = Color(red: 1, green: 0.36, blue: 0.16)
    static let background = Color(red: 0.055, green: 0.065, blue: 0.08)
}
struct PaddockPanel: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(20).background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}
extension View { func paddockPanel() -> some View { modifier(PaddockPanel()) } }

struct PaddockShell: View {
    @ObservedObject var model: PaddockController
    @State private var tab = PaddockTab.drive
    @State private var expanded = Set<String>()
    @State private var saveTask: DispatchWorkItem?
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tab.rawValue).font(.system(size: 29, weight: .bold))
                        Text(tab.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let operation = model.operation { ProgressView().controlSize(.small); Text(operation).font(.caption).foregroundStyle(.secondary).frame(maxWidth: 200) }
                }.padding(.horizontal, 28).padding(.top, 32).padding(.bottom, 24)
                ScrollView {
                    Group {
                        switch tab {
                        case .drive: DriveView(model: model)
                        case .online: OnlineView(model: model, browser: model.online)
                        case .serverHost: ServerHostView(model: model, host: model.serverHost)
                        case .wheel: WheelView(model: model)
                        case .presets: PresetsView(model: model)
                        case .mods: ModsView(model: model)
                        case .records: RecordsView(model: model)
                        case .runtime: RuntimeView(model: model)
                        }
                    }.padding(.horizontal, 28).padding(.bottom, 24)
                }
                if tab == .drive {
                    DriveLaunchBar(model: model).padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 18)
                }
                if !model.message.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(model.message).font(.caption).textSelection(.enabled)
                        Spacer()
                        Button { model.message = "" } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }.padding(14).background(Color.white.opacity(0.04))
                }
            }
        }
        .background(PaddockStyle.background)
        .tint(PaddockStyle.accent)
        .preferredColorScheme(.dark)
        .alert("Не удалось выполнить действие", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("Понятно") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onChange(of: model.configuration.car) { _ in model.refreshSetups() }
        .onChange(of: model.configuration.track) { _ in model.refreshSetups() }
        .onChange(of: model.configuration) { _ in
            saveTask?.cancel()
            let task = DispatchWorkItem { model.persist() }; saveTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
        }
    }
    private func navigationGroup(_ title: String, symbol: String, items: [PaddockTab]) -> some View {
        DisclosureGroup(isExpanded: Binding(get: { expanded.contains(title) }, set: { value in
            if value { expanded.insert(title) } else { expanded.remove(title) }
        })) {
            ForEach(items) { item in navigationButton(item).padding(.leading, 8) }
        } label: {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .medium))
                .foregroundStyle(items.contains(tab) ? Color.white : Color.white.opacity(0.58))
                .padding(.vertical, 10)
        }
    }
    private func navigationButton(_ item: PaddockTab) -> some View {
        Button { tab = item } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol).frame(width: 20)
                Text(item.sidebarTitle).fontWeight(tab == item ? .semibold : .regular).lineLimit(1)
                Spacer(minLength: 0)
            }.font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 11)
                .foregroundStyle(tab == item ? Color.white : Color.white.opacity(0.58))
                .background(tab == item ? Color.white.opacity(0.085) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityAddTraits(tab == item ? .isSelected : [])
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "steeringwheel").font(.system(size: 28, weight: .medium)).foregroundStyle(PaddockStyle.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MOZA").font(.system(size: 12, weight: .black, design: .rounded)).tracking(3)
                    Text("PADDOCK").font(.system(size: 17, weight: .bold, design: .rounded)).tracking(1)
                }
            }.padding(.top, 42).padding(.bottom, 40)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    navigationButton(.drive)
                    ForEach(PaddockNavigation.groups, id: \.title) { group in
                        navigationGroup(group.title, symbol: group.symbol, items: group.items)
                    }
                }
            }.scrollIndicators(.hidden)
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Circle().fill(model.connected ? Color.green : Color.gray).frame(width: 6, height: 6)
                    Text(model.connected ? "MOZA R5 подключена" : "MOZA не подключена").font(.system(size: 11, weight: .medium))
                }
                Text(model.gameRunning ? "Заезд идёт · внешний экран" : "Готов к следующему заезду").font(.system(size: 10)).foregroundStyle(.secondary)
                Divider().padding(.vertical, 4)
                Text(model.runtime == .crossover ? "CROSSOVER" : "WINE · FREE").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).tracking(1.5)
                if model.runtime == .crossover {
                Picker("Бутылка", selection: $model.bottle) {
                    ForEach(model.bottles, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().disabled(model.gameRunning || model.operation != nil)
                    .onChange(of: model.bottle) { value in UserDefaults.standard.set(value, forKey: "paddock.bottle"); model.reload() }
                } else { Text("Независимая среда").font(.caption).foregroundStyle(.secondary) }
                Button { model.emergencyStop() } label: { Label("Остановить отдачу", systemImage: "stop.circle").font(.system(size: 11)).foregroundStyle(.red.opacity(0.9)) }
                    .buttonStyle(.plain).padding(.top, 8)
            }.padding(12).background(Color.white.opacity(0.025)).clipShape(RoundedRectangle(cornerRadius: 12))
            Text("ASSETTO CORSA · macOS").font(.system(size: 8, weight: .medium)).foregroundStyle(.tertiary).tracking(1).padding(.top, 18).padding(.bottom, 20)
        }.padding(.horizontal, 18).frame(width: 190).background(Color.black.opacity(0.15))
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary) }
}

struct AssetPicture: View {
    let url: URL?
    var symbol = "car.side"
    @State private var loaded: NSImage?
    var body: some View {
        GeometryReader { size in
            if let image = loaded {
                Image(nsImage: image).resizable().scaledToFill().frame(width: size.size.width, height: size.size.height).clipped()
            } else {
                ZStack { Color.white.opacity(0.035); Image(systemName: symbol).font(.system(size: 44, weight: .light)).foregroundStyle(.tertiary) }.frame(width: size.size.width, height: size.size.height)
            }
        }.task(id: url) { loaded = url.flatMap { NSImage(contentsOf: $0) } }
    }
}
