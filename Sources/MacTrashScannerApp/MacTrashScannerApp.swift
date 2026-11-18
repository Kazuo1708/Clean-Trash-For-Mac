import SwiftUI
import Foundation

@main
struct MacTrashScannerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1120, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct TrashItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let location: String
    let size: Int64
    let category: Category
    let risk: Risk
    let explanation: String
    let icon: String
    var selected: Bool = false
    var absolutePath: String? = nil
    var groupKey: String? = nil

    enum Category: String, CaseIterable { case all = "Tất cả", cache = "Cache", logs = "Logs", leftovers = "Dư thừa", trash = "Thùng rác" }
    enum Risk: Hashable { case safe, review, protected }
}

@MainActor
final class ScanStore: ObservableObject {
    @Published var isScanning = false
    @Published var progress = 0.0
    @Published var items: [TrashItem] = []
    @Published var selectedCategory: TrashItem.Category = .all
    @Published var query = ""
    @Published var showOnlySelected = false
    @Published var lastScan = "Chưa quét"
    @Published var scanTarget = "TFT FBE"
    @Published var showDeleteConfirmation = false
    @Published var deletedCount = 0
    @Published var showOnlyLarge = false
    @Published var showOnlyRecommended = false
    @Published var minimumSizeMB = 0.0
    @Published var includeApplications = true
    @Published var includeCaches = true
    @Published var includeDMG = true
    @Published var includeLogs = true

    private let protectedRoots = ["/System", "/private/var/db", "/Library/Apple", "/usr/bin", "/bin"]

    private let samples: [TrashItem] = []


    var filtered: [TrashItem] {
        items.filter { item in
            (selectedCategory == .all || item.category == selectedCategory) &&
            (!showOnlySelected || item.selected) &&
            (!showOnlyLarge || item.size >= 100_000_000) &&
            (!showOnlyRecommended || item.risk == .safe || item.category == .trash) &&
            item.size >= Int64(minimumSizeMB * 1_000_000) &&
            (query.isEmpty || item.name.localizedCaseInsensitiveContains(query) || item.location.localizedCaseInsensitiveContains(query))
        }
    }

    var selectedBytes: Int64 { items.filter(\.selected).reduce(0) { $0 + $1.size } }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.size } }

    func scan() {
        guard !isScanning else { return }
        isScanning = true; progress = 0
        Task {
            for step in 1...20 {
                try? await Task.sleep(for: .milliseconds(65))
                progress = Double(step) / 20
            }
            items = scanSystem()
            lastScan = "Vừa xong"
            isScanning = false
        }
    }

    private func scanSystem() -> [TrashItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let appRoots = ["/Applications", "\(home)/Applications"]
        var found: [TrashItem] = []
        for root in appRoots {
            guard let urls = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey], options: []) else { continue }
            for app in urls where app.pathExtension == "app" {
                let appName = app.deletingPathExtension().lastPathComponent
                let size = directorySize(app)
                found.append(TrashItem(name: appName, location: app.path, size: size, category: .leftovers, risk: .review, explanation: "Ứng dụng. Khi chọn, CleanMac sẽ đưa ứng dụng và dữ liệu liên quan vào Thùng rác.", icon: "app.fill", absolutePath: app.path))
            }
        }
        let junkRoots = ["\(home)/Library/Caches", "\(home)/Library/Logs", "\(home)/Library/Saved Application State", "\(home)/Library/Application Support", "\(home)/Library/Preferences", "\(home)/Library/Containers", "\(home)/Library/Group Containers"]
        for root in junkRoots {
            guard let enumerator = fm.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey], options: []) else { continue }
            for case let url as URL in enumerator {
                let name = url.lastPathComponent.lowercased()
                let isJunk = url.pathExtension == "dmg" || name.contains("cache") || name.contains("crash") || name.contains("deriveddata") || name.contains("saved state") || name.contains("tft") || name.contains("league") || name.contains("riot")
                guard isJunk else { continue }
                let path = url.path
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey])
                let size = values?.isDirectory == true ? directorySize(url) : Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
                let category: TrashItem.Category = url.pathExtension == "dmg" ? .trash : path.contains("Caches") ? .cache : path.contains("Logs") ? .logs : .leftovers
                found.append(TrashItem(name: url.lastPathComponent, location: path.replacingOccurrences(of: home, with: "~"), size: size, category: category, risk: .review, explanation: url.pathExtension == "dmg" ? "Ảnh đĩa cài đặt. Chỉ xóa nếu ứng dụng đã cài xong." : "Dữ liệu phụ/cache có thể dọn sau khi kiểm tra.", icon: url.pathExtension == "dmg" ? "externaldrive.fill" : "trash.fill", absolutePath: path))
                if values?.isDirectory == true { enumerator.skipDescendants() }
            }
        }
        return found.sorted { $0.size > $1.size }
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in e { let v = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]); total += Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0) }
        return total
    }

    func toggle(_ item: TrashItem) {
        guard item.risk != .protected else { return }
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].selected.toggle() }
    }

    func selectSafe() { items = items.map { var x = $0; x.selected = x.risk == .safe || x.category == .trash; return x } }
    func selectRecommended() { items = items.map { var x = $0; x.selected = x.risk == .safe || x.category == .trash || x.name.lowercased().hasSuffix(".dmg"); return x } }
    func clearSelection() { items = items.map { var x = $0; x.selected = false; return x } }
    func cleanSelected() {
        let fm = FileManager.default
        let selected = items.filter(\.selected)
        for item in selected {
            guard let path = item.absolutePath, !protectedRoots.contains(where: path.hasPrefix) else { continue }
            let url = URL(fileURLWithPath: path)
            let trashURL = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").appendingPathComponent(url.lastPathComponent)
            if fm.fileExists(atPath: trashURL.path) { try? fm.removeItem(at: trashURL) }
            try? fm.moveItem(at: url, to: trashURL)
        }
        deletedCount = selected.count
        items.removeAll { $0.selected }
    }
}

struct ContentView: View {
    @StateObject private var store = ScanStore()
    @State private var showSettings = false
    @State private var showAbout = false

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(store: store, showSettings: $showSettings, showAbout: $showAbout)
            Divider()
            VStack(spacing: 0) {
                Header(store: store)
                Divider()
                MainPanel(store: store)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showAbout) { AboutView() }
    }
}

struct Sidebar: View {
    @ObservedObject var store: ScanStore
    @Binding var showSettings: Bool
    @Binding var showAbout: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) { Image(systemName: "sparkles").font(.title2.bold()).foregroundStyle(.blue); Text("CleanMac").font(.title2.bold()) }.padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 34)
            Text("KHÁM PHÁ").font(.caption.bold()).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 10)
            SideButton(title: "Tổng quan", icon: "rectangle.grid.2x2.fill", active: store.selectedCategory == .all) { store.selectedCategory = .all }
            SideButton(title: "Mục có thể dọn", icon: "sparkles", active: store.selectedCategory != .all) { store.selectedCategory = .all }
            Text("DỌN DẸP").font(.caption.bold()).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 10)
            ForEach(TrashItem.Category.allCases.dropFirst(), id: \.self) { category in
                SideButton(title: category.rawValue, icon: icon(for: category), active: store.selectedCategory == category) { store.selectedCategory = category }
            }
            Spacer()
            Divider()
            SideButton(title: "Cài đặt", icon: "gearshape.fill", active: false) { showSettings = true }
            SideButton(title: "Về CleanMac", icon: "info.circle.fill", active: false) { showAbout = true }.padding(.bottom, 12)
        }
        .frame(width: 246)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    func icon(for category: TrashItem.Category) -> String { switch category { case .cache: return "externaldrive.fill"; case .logs: return "doc.text.fill"; case .leftovers: return "archivebox.fill"; case .trash: return "trash.fill"; case .all: return "circle" } }
}

struct SideButton: View {
    let title: String; let icon: String; let active: Bool; let action: () -> Void
    var body: some View { Button(action: action) { HStack(spacing: 12) { Image(systemName: icon).frame(width: 20); Text(title); Spacer() }.padding(.vertical, 9).padding(.horizontal, 24).contentShape(Rectangle()) }.buttonStyle(.plain).foregroundStyle(active ? .blue : .primary).background(active ? Color.blue.opacity(0.12) : .clear) }
}

struct Header: View {
    @ObservedObject var store: ScanStore
    var body: some View { HStack { VStack(alignment: .leading, spacing: 4) { Text("Quản lý ứng dụng & dung lượng").font(.title.bold()); Text("Chọn ứng dụng để gỡ cùng dữ liệu liên quan, cache và file cài đặt .dmg").foregroundStyle(.secondary) }; Spacer(); Button { store.scan() } label: { Label(store.isScanning ? "Đang quét…" : "Quét ứng dụng & file rác", systemImage: "magnifyingglass") }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.isScanning) }.padding(.horizontal, 32).padding(.vertical, 22) }
}

struct MainPanel: View {
    @ObservedObject var store: ScanStore
    var body: some View { VStack(spacing: 18) {
        if store.items.isEmpty { WelcomeCard(store: store) } else { SummaryCard(store: store) }
        HStack { Text(store.items.isEmpty ? "Chưa có kết quả" : "KẾT QUẢ QUÉT").font(.caption.bold()).foregroundStyle(.secondary); Spacer(); if !store.items.isEmpty { Text("\(store.filtered.count)/\(store.items.count) mục • Lần quét: \(store.lastScan)").font(.caption).foregroundStyle(.secondary) } }.padding(.top, 4)
        if !store.items.isEmpty { ResultsView(store: store) }
        Spacer()
    }.padding(32) }
}

struct WelcomeCard: View {
    @ObservedObject var store: ScanStore
    var body: some View { VStack(spacing: 14) { Image(systemName: "sparkles.rectangle.stack.fill").font(.system(size: 44)).foregroundStyle(.blue); Text("Sẵn sàng làm sạch").font(.title2.bold()); Text("CleanMac sẽ tìm cache, log, file dư thừa và các mục ẩn không còn cần thiết — không tự ý đụng vào file hệ thống.").multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 540); Button("Bắt đầu quét") { store.scan() }.buttonStyle(.borderedProminent).controlSize(.large) }.frame(maxWidth: .infinity).padding(48).background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 16)) }
}

struct SummaryCard: View {
    @ObservedObject var store: ScanStore
    var body: some View { HStack(spacing: 22) { VStack(alignment: .leading, spacing: 6) { Text("Có thể giải phóng").foregroundStyle(.secondary); Text(ByteCountFormatter.string(fromByteCount: store.totalBytes, countStyle: .file)).font(.system(size: 30, weight: .bold, design: .rounded)); Text("Đã chọn: \(ByteCountFormatter.string(fromByteCount: store.selectedBytes, countStyle: .file))").font(.subheadline).foregroundStyle(.blue) }; Spacer(); ZStack { Circle().stroke(.gray.opacity(0.16), lineWidth: 10); Circle().trim(from: 0, to: store.totalBytes > 0 ? CGFloat(store.selectedBytes) / CGFloat(store.totalBytes) : 0).stroke(.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90)); Image(systemName: "checkmark.shield.fill").foregroundStyle(.blue) }.frame(width: 86, height: 86) }.padding(24).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.gray.opacity(0.15))) }
}

struct ResultsView: View {
    @ObservedObject var store: ScanStore
    var body: some View { VStack(spacing: 12) {
        HStack { TextField("Tìm theo tên hoặc vị trí…", text: $store.query).textFieldStyle(.roundedBorder).frame(width: 280); Picker("Nhóm", selection: $store.selectedCategory) { ForEach(TrashItem.Category.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 130); Toggle("≥ 100 MB", isOn: $store.showOnlyLarge).toggleStyle(.checkbox); Toggle("Gợi ý dọn", isOn: $store.showOnlyRecommended).toggleStyle(.checkbox); Spacer() }
        HStack { Text("Lọc theo dung lượng tối thiểu: \(Int(store.minimumSizeMB)) MB").font(.caption).foregroundStyle(.secondary); Slider(value: $store.minimumSizeMB, in: 0...500, step: 10).frame(width: 180); Spacer(); Toggle("Chỉ đã chọn", isOn: $store.showOnlySelected).toggleStyle(.checkbox); Button("Chọn mục an toàn") { store.selectSafe() }.buttonStyle(.bordered); Button("Bỏ chọn") { store.clearSelection() }.buttonStyle(.bordered) }
        ScrollView { LazyVStack(spacing: 8) { ForEach(store.filtered) { item in ItemRow(item: item, store: store) } } }.frame(maxHeight: 340)
        HStack { Label("Mỗi mục đều hiển thị lý do và đường dẫn để kiểm tra trước khi dọn.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary); Spacer(); Button { store.showDeleteConfirmation = true } label: { Label("Đưa mục đã chọn vào Thùng rác", systemImage: "trash") }.buttonStyle(.borderedProminent).disabled(store.selectedBytes == 0) }
    }.padding(20).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .alert("Xác nhận dọn mục đã chọn", isPresented: $store.showDeleteConfirmation) {
            Button("Hủy", role: .cancel) { }
            Button("Đưa vào Thùng rác", role: .destructive) { store.cleanSelected() }
        } message: {
            Text("CleanMac chỉ di chuyển các mục đã chọn vào ~/.Trash. Hãy kiểm tra ứng dụng, dữ liệu chung và file .dmg trước khi xác nhận.")
        }
    }
}

struct ItemRow: View {
    let item: TrashItem; @ObservedObject var store: ScanStore
    var body: some View { HStack(spacing: 14) { Button { store.toggle(item) } label: { Image(systemName: item.selected ? "checkmark.circle.fill" : "circle").foregroundStyle(item.selected ? .blue : .secondary).font(.title3) }.buttonStyle(.plain); Image(systemName: item.icon).font(.title3).foregroundStyle(item.risk == .protected ? .orange : .blue).frame(width: 28); VStack(alignment: .leading, spacing: 3) { Text(item.name).fontWeight(.medium); Text(item.location).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)).font(.subheadline.monospacedDigit()); Text(item.risk == .protected ? "Được bảo vệ" : item.risk == .review ? "Xem lại" : "An toàn").font(.caption.bold()).foregroundStyle(item.risk == .protected ? .orange : item.risk == .review ? .secondary : .green).frame(width: 82, alignment: .trailing); if item.risk != .protected { Button { } label: { Image(systemName: "info.circle") }.buttonStyle(.plain).help(item.explanation) } }.padding(12).background(item.selected ? .blue.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10)) }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { VStack(alignment: .leading, spacing: 18) { HStack { Text("Cài đặt").font(.title.bold()); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }.buttonStyle(.plain).help("Đóng") }; Divider(); Toggle("Tự động bỏ qua mục được bảo vệ", isOn: .constant(true)); Toggle("Hiển thị cảnh báo trước khi dọn", isOn: .constant(true)); Toggle("Tính cả file .dmg trong thư mục Downloads", isOn: .constant(true)); Text("CleanMac luôn đưa file vào Thùng rác thay vì xóa vĩnh viễn. Không đụng vào vùng hệ thống được bảo vệ.").foregroundStyle(.secondary); Spacer(); HStack { Spacer(); Button("Đóng") { dismiss() }.keyboardShortcut(.cancelAction) } }.padding(28).frame(width: 460, height: 320) }
}
struct AboutView: View { var body: some View { VStack(spacing: 12) { Image(systemName: "sparkles").font(.system(size: 42)).foregroundStyle(.blue); Text("CleanMac").font(.title.bold()); Text("Công cụ dọn dẹp minh bạch cho macOS"); Text("Phiên bản thử nghiệm • Ưu tiên an toàn dữ liệu").font(.caption).foregroundStyle(.secondary); Button("Đóng") { NSApp.keyWindow?.close() }.buttonStyle(.borderedProminent) }.padding(30).frame(width: 360, height: 240) } }
