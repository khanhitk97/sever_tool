import SwiftUI
import UserNotifications
import AudioToolbox
import AVFoundation

// MARK: - Model dữ liệu trả về từ Apps Script
struct SheetResponse: Codable {
    let success: Bool
    let total: Int?
    let data: [AccountItem]?
}

struct AccountItem: Codable, Identifiable, Equatable {
    var id: String { phone }
    let phone: String
    let status: String
    let expire_at: String
    let amount: String
    let payment_status: String
    let note: String
}

// MARK: - App Entry Point
@main
struct SheetMonitorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - AppDelegate để hiện thông báo ngay cả khi đang mở ứng dụng
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Luôn hiện banner, badge và phát âm thanh
        completionHandler([.banner, .badge, .sound])
    }
}

// MARK: - Giao diện chính
struct ContentView: View {
    // URL Web App của bạn
    @State private var webAppUrl: String = "https://script.google.com/macros/s/AKfycbz6gvfUZuyuO8-BW8tRVkoTFGPvZNu_eJPz1JtI9AuVnUQd2NLKcMCCQ4wBckVPPg5V/exec"
    
    @State private var isMonitoring: Bool = true
    @State private var checkInterval: Double = 5
    @State private var statusMessage: String = "Đang khởi tạo..."
    @State private var accounts: [AccountItem] = []
    
    @State private var previousMap: [String: AccountItem] = [:]
    @State private var timer: Timer?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header điều khiển
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Giám sát Trang tính")
                                .font(.headline)
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $isMonitoring)
                            .labelsHidden()
                            .onChange(of: isMonitoring) { running in
                                if running { startMonitoring() } else { stopMonitoring() }
                            }
                    }

                    HStack {
                        Stepper("Tần suất: \(Int(checkInterval))s", value: $checkInterval, in: 3...60, step: 1)
                            .font(.subheadline)
                        Spacer()
                        Button(action: {
                            playAlert(title: "🔔 Test Chuông", body: "Thông báo và chuông hoạt động hoàn hảo!")
                        }) {
                            Text("Test chuông")
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.12))
                                .foregroundColor(.blue)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)

                // Danh sách tài khoản
                List(accounts) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(item.phone)
                                .font(.headline)
                            Spacer()
                            
                            Text(item.payment_status)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(item.payment_status == "PAID" ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                .foregroundColor(item.payment_status == "PAID" ? .green : .orange)
                                .cornerRadius(4)
                            
                            Text(item.status)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(item.status == "ACTIVE" ? Color.blue.opacity(0.15) : Color.red.opacity(0.15))
                                .foregroundColor(item.status == "ACTIVE" ? .blue : .red)
                                .cornerRadius(4)
                        }
                        
                        HStack {
                            Text("Hạn: \(item.expire_at.isEmpty ? "Chưa có" : item.expire_at)")
                            Spacer()
                            if let amt = Int(item.amount), amt > 0 {
                                Text("\(amt)đ")
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        if !item.note.isEmpty {
                            Text(item.note)
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("Sheet Monitor Pro")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                initNotificationAndAudio()
                startMonitoring()
            }
        }
    }

    func initNotificationAndAudio() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudioSession error: \(error)")
        }
    }

    func startMonitoring() {
        stopMonitoring()
        statusMessage = "Đang kết nối..."

        fetchData { success in
            if success {
                self.statusMessage = "Đang quét mỗi \(Int(self.checkInterval)) giây"
                self.timer = Timer.scheduledTimer(withTimeInterval: self.checkInterval, repeats: true) { _ in
                    self.fetchData(completion: nil)
                }
            } else {
                self.statusMessage = "Lỗi kết nối Web App!"
                self.isMonitoring = false
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        statusMessage = "Đã dừng quét"
    }

    func fetchData(completion: ((Bool) -> Void)?) {
        guard let url = URL(string: "\(webAppUrl)?action=get_all") else {
            completion?(false)
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        URLSession.shared.dataTask(with: request) { data, _, err in
            DispatchQueue.main.async {
                guard let data = data, err == nil else {
                    completion?(false)
                    return
                }

                do {
                    let res = try JSONDecoder().decode(SheetResponse, from: data)
                    if res.success, let list = res.data {
                        self.processChanges(newList: list)
                        self.accounts = list
                        self.statusMessage = "Cập nhật lúc \(Date().formatted(date: .omitted, time: .standard)) (\(list.count) thiết bị)"
                        completion?(true)
                    } else {
                        completion?(false)
                    }
                } catch {
                    completion?(false)
                }
            }
        }.resume()
    }

    func processChanges(newList: [AccountItem]) {
        if previousMap.isEmpty {
            for item in newList { previousMap[item.phone] = item }
            return
        }

        // Cảnh báo khi có số điện thoại mới đăng ký
        for item in newList {
            if previousMap[item.phone] == nil {
                playAlert(
                    title: "🔔 Tài khoản mới!",
                    body: "SĐT: \(item.phone) - Trạng thái: \(item.status)"
                )
            }
        }

        // Cảnh báo khi thay đổi trạng thái
        for item in newList {
            if let old = previousMap[item.phone] {
                // Khách thanh toán thành công (UNPAID -> PAID)
                if old.payment_status != "PAID" && item.payment_status == "PAID" {
                    playAlert(
                        title: "💰 Đã thanh toán!",
                        body: "SĐT: \(item.phone) - Số tiền: \(item.amount)đ"
                    )
                }
                // Khách gửi yêu cầu gia hạn (ACTIVE -> PENDING)
                else if old.status != "PENDING" && item.status == "PENDING" {
                    playAlert(
                        title: "⏳ Yêu cầu gia hạn!",
                        body: "SĐT: \(item.phone) - \(item.note)"
                    )
                }
            }
        }

        previousMap.removeAll()
        for item in newList { previousMap[item.phone] = item }
    }

    func playAlert(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.defaultCritical

        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)

        // Rung và phát chuông cảnh báo
        AudioServicesPlayAlertSound(1005)
    }
}
