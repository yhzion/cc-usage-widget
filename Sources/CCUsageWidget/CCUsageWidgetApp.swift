import SwiftUI
import AppKit

// MARK: - Models

struct UsageResponse: Codable {
    let five_hour: UsageBucket?
    let seven_day: UsageBucket?
    let seven_day_sonnet: UsageBucket?
    let seven_day_opus: UsageBucket?
    let extra_usage: ExtraUsage?
}

struct UsageBucket: Codable {
    let utilization: Double?
    let resets_at: String?
}

struct ExtraUsage: Codable {
    let is_enabled: Bool?
}

// MARK: - LaunchAgent Helper

enum LaunchAgent {
    static var plistPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.yhzion.cc-usage-widget.plist")
            .path
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }

    static func enable() {
        let plist: [String: Any] = [
            "Label": "com.yhzion.cc-usage-widget",
            "ProgramArguments": [Bundle.main.bundlePath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        let url = URL(fileURLWithPath: plistPath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
    }

    static func disable() {
        try? FileManager.default.removeItem(atPath: plistPath)
    }

    static func toggle() {
        isEnabled ? disable() : enable()
    }
}

// MARK: - ViewModel

@MainActor
class ViewModel: ObservableObject {
    @Published var fiveHour: Double?
    @Published var sevenDay: Double?
    @Published var sonnet7d: Double?
    @Published var opus7d: Double?
    @Published var resetsAt: String?
    @Published var extraEnabled = false
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var timeUntilReset: TimeInterval?
    @Published var lastFetchAgo: String = ""

    private var apiTimer: Timer?
    private var countdownTimer: Timer?
    private var lastFetchTime: Date?
    private let minFetchInterval: TimeInterval = 600 // 10분
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func startAutoRefresh() {
        load()
        apiTimer = Timer.scheduledTimer(withTimeInterval: minFetchInterval, repeats: true) { _ in
            Task { @MainActor in self.load() }
        }
    }

    func stopAutoRefresh() {
        apiTimer?.invalidate()
        countdownTimer?.invalidate()
    }

    func startCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in self.updateCountdown() }
        }
        updateCountdown()
    }

    func updateCountdown() {
        guard let resetsAt = resetsAt else {
            timeUntilReset = nil
            updateLastFetchAgo()
            return
        }
        guard let resetDate = isoFormatter.date(from: resetsAt) else {
            let fallback = ISO8601DateFormatter()
            guard let d = fallback.date(from: resetsAt) else {
                timeUntilReset = nil
                updateLastFetchAgo()
                return
            }
            let remaining = d.timeIntervalSinceNow
            timeUntilReset = remaining > 0 ? remaining : 0
            updateLastFetchAgo()
            return
        }
        let remaining = resetDate.timeIntervalSinceNow
        timeUntilReset = remaining > 0 ? remaining : 0
        updateLastFetchAgo()
    }

    func updateLastFetchAgo() {
        guard let last = lastFetchTime else {
            lastFetchAgo = ""
            return
        }
        let elapsed = Date().timeIntervalSince(last)
        let total = Int(elapsed)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60

        if days > 0 {
            lastFetchAgo = "\(days)일 전"
        } else if hours > 0 {
            lastFetchAgo = "\(hours)시간 전"
        } else if minutes > 0 {
            lastFetchAgo = "\(minutes)분 전"
        } else {
            lastFetchAgo = "방금"
        }
    }

    static let cachePath = "/tmp/cc-widget-cache.json"

    private func saveCache(_ data: Data) {
        try? data.write(to: URL(fileURLWithPath: Self.cachePath))
    }

    private func loadCache() -> UsageResponse? {
        guard let data = FileManager.default.contents(atPath: Self.cachePath) else { return nil }
        return try? JSONDecoder().decode(UsageResponse.self, from: data)
    }

    private func applyData(_ decoded: UsageResponse) {
        self.fiveHour = decoded.five_hour?.utilization
        self.sevenDay = decoded.seven_day?.utilization
        self.sonnet7d = decoded.seven_day_sonnet?.utilization
        self.opus7d = decoded.seven_day_opus?.utilization
        self.resetsAt = decoded.seven_day?.resets_at ?? decoded.five_hour?.resets_at
        self.extraEnabled = decoded.extra_usage?.is_enabled ?? false
        self.startCountdown()
    }

    func load(force: Bool = false) {
        // 10분 이내에는 캐시 사용 (단, force는 무시)
        if !force, let last = lastFetchTime, Date().timeIntervalSince(last) < minFetchInterval {
            if let cached = loadCache() {
                applyData(cached)
            }
            return
        }

        isLoading = true
        errorMessage = nil

        guard let token = fetchToken() else {
            errorMessage = "로그인 필요: claude auth login"
            isLoading = false
            if let cached = loadCache() {
                applyData(cached)
            }
            return
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, err in
            Task { @MainActor in
                guard let self = self else { return }
                self.isLoading = false

                // 네트워크 에러 또는 응답 없음 — 캐시 폴백, 에러 메시지 없음
                if let err = err {
                    if let cached = self.loadCache() {
                        self.applyData(cached)
                    }
                    return
                }
                guard let data = data else {
                    if let cached = self.loadCache() {
                        self.applyData(cached)
                    }
                    return
                }

                // JSON 파싱
                do {
                    let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)

                    // API 에러 응답 (Rate Limit 등) — 캐시 폴백, 에러 메시지 없음
                    if decoded.five_hour == nil && decoded.seven_day == nil {
                        if let cached = self.loadCache() {
                            self.applyData(cached)
                        }
                        return
                    }

                    // 성공 — 캐시 저장 + 시간 기록
                    self.saveCache(data)
                    self.lastFetchTime = Date()
                    self.applyData(decoded)
                } catch {
                    if let cached = self.loadCache() {
                        self.applyData(cached)
                    }
                }
            }
        }.resume()
    }

    private func fetchToken() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let jsonString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !jsonString.isEmpty else { return nil }
            let json = try JSONSerialization.jsonObject(with: Data(jsonString.utf8)) as? [String: Any]
            let oauth = json?["claudeAiOauth"] as? [String: Any]
            return oauth?["accessToken"] as? String
        } catch {
            return nil
        }
    }
}

// MARK: - Claude Icon

struct ClaudeIcon: View {
    private var iconImage: NSImage? {
        guard let path = Bundle.module.path(forResource: "logo", ofType: "ico"),
              let image = NSImage(contentsOfFile: path) else { return nil }
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    var body: some View {
        if let nsImage = iconImage {
            Image(nsImage: nsImage)
                .resizable()
                .frame(width: 18, height: 18)
        } else {
            // Fallback: 기존 다이아몬드
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.95, green: 0.55, blue: 0.35), Color(red: 0.85, green: 0.4, blue: 0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(45))
                Text("C")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(width: 18, height: 18)
        }
    }
}

// MARK: - Subviews

struct UsageRing: View {
    let label: String
    let value: Double?
    let color: Color

    private var displayValue: Double {
        value ?? 0
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 5)
                    .frame(width: 48, height: 48)
                Circle()
                    .trim(from: 0, to: CGFloat(displayValue) / 100)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [color.opacity(0.5), color]),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(-90))
                if let v = value {
                    Text("\(Int(v))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text("–")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
    }
}

struct HourglassCard: View {
    let remaining: TimeInterval?

    private var displayText: String {
        guard let r = remaining, r > 0 else { return "리셋 중…" }
        let total = Int(r)
        let days = total / 86400
        let h = (total % 86400) / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if days > 0 {
            return String(format: "%d일 %d:%02d:%02d", days, h, m, s)
        } else if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(red: 0.9, green: 0.7, blue: 0.3))
                Text("다음 리셋까지")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
            }

            Text(displayText)
                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .contentTransition(.numericText())

        }
        .padding(10)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Main View

struct ContentView: View {
    @StateObject private var vm = ViewModel()

    var body: some View {
        VStack(spacing: 14) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    ClaudeIcon()
                    Text("Claude Code")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                Spacer()
                HStack(spacing: 12) {
                    Menu {
                        Button(LaunchAgent.isEnabled ? "✓ 시작 시 실행" : "시작 시 실행") {
                            LaunchAgent.toggle()
                        }
                        Divider()
                        Button("종료") {
                            NSApplication.shared.terminate(nil)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 18, height: 18)
                            .foregroundColor(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                }
            }

            Divider()
                .background(Color.primary.opacity(0.06))

            if let err = vm.errorMessage {
                Text(err)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 1, green: 0.4, blue: 0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                // Rings row
                HStack(spacing: 14) {
                    UsageRing(label: "5시간", value: vm.fiveHour, color: Color(red: 0.3, green: 0.85, blue: 0.5))
                    UsageRing(label: "7일", value: vm.sevenDay, color: Color(red: 0.4, green: 0.7, blue: 1.0))
                    UsageRing(label: "Sonnet", value: vm.sonnet7d, color: Color(red: 1.0, green: 0.6, blue: 0.2))
                }
                .frame(maxWidth: .infinity, alignment: .center)

                // Hourglass countdown
                if let remaining = vm.timeUntilReset {
                    HourglassCard(remaining: remaining)
                }

                // Last fetch time
                if !vm.lastFetchAgo.isEmpty {
                    HStack {
                        Spacer()
                        Text("갱신: \(vm.lastFetchAgo)")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }

                // Extra Credits
                if vm.extraEnabled {
                    HStack(spacing: 4) {
                        Spacer()
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                        Text("Extra Credits")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.2))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 240)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onAppear { vm.startAutoRefresh() }
        .onDisappear { vm.stopAutoRefresh() }
    }
}

// MARK: - App Delegate (Floating Panel)

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 싱글 인스턴스
        let bundleID = Bundle.main.bundleIdentifier ?? "com.yhzion.cc-usage-widget"
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == bundleID && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = runningApps.first {
            existing.activate(options: .activateIgnoringOtherApps)
            NSApplication.shared.terminate(nil)
            return
        }

        NSApplication.shared.setActivationPolicy(.accessory)

        let contentView = NSHostingView(rootView: ContentView())
        contentView.frame = NSRect(x: 0, y: 0, width: 240, height: 260)

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 260),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.backgroundColor = .clear
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.contentView = contentView
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 20
        contentView.layer?.masksToBounds = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isOpaque = false
        panel.animationBehavior = .none

        if let screen = NSScreen.main {
            let padding: CGFloat = 20
            let x = screen.visibleFrame.maxX - 240 - padding
            let y = screen.visibleFrame.maxY - 280 - padding
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
    }
}

// MARK: - App

@main
struct CCUsageWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
