import SwiftUI
import UserNotifications
import AudioToolbox
import AVFoundation

// MARK: - Models
struct SheetResponse: Codable {
    let success: Bool
    let total: Int?
    let data: [AccountModel]?
}

struct AccountModel: Codable, Identifiable, Equatable {
    var id: String { phone }
    var phone: String
    var password: String
    var device_id: String
    var status: String
    var expire_at: String
    var trigger_sec: Int
    var note: String
    var amount: String
    var payment_status: String
}

// MARK: - App Entry & Notification Delegate
@main
struct SheetAdminApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .badge, .sound])
    }
}

// MARK: - Main View
struct ContentView: View {
    let webAppUrl = "https://script.google.com/macros/s/AKfycbz6gvfUZuyuO8-BW8tRVkoTFGPvZNu_eJPz1JtI9AuVnUQd2NLKcMCCQ4wBckVPPg5V/exec"

    @State private var accounts: [AccountModel] = []
    @State private var selectedAccount: AccountModel?
    @State private var isMonitoring: Bool = true
    @State private var checkInterval: Double = 5
    @State private var statusText: String = "Đang kết nối..."
    
    @State private var previousState: [String: String] = [:] // Phone -> Payment_Status
    @State private var timer: Timer?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header điều khiển
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Tự động quét mỗi \(Int(checkInterval)) giây")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Toggle("", isOn: $isMonitoring)
                        .labelsHidden()
                        .onChange(of: isMonitoring) { running in
                            if running { startPolling() } else { stopPolling() }
                        }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))

                // Danh sách tài khoản
                List {
                    // Danh sách chờ xác nhận thanh toán (UNPAID)
                    let unpaidList = accounts.filter { $0.payment_status == "UNPAID" }
                    if !unpaidList.isEmpty {
                        Section(header: Text("⚠️ Chờ thanh toán & Kích hoạt (\(unpaidList.count))").foregroundColor(.orange)) {
                            ForEach(unpaidList) { acc in
                                AccountRow(account: acc)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedAccount = acc }
                            }
                        }
                    }

                    // Danh sách tài khoản còn lại
                    let activeList = accounts.filter { $0.payment_status != "UNPAID" }
                    Section(header: Text("Tài khoản hệ thống (\(activeList.count))")) {
                        ForEach(activeList) { acc in
                            AccountRow(account: acc)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedAccount = acc }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .refreshable {
                    fetchData()
                }
            }
            .navigationTitle("Quản Lý Bản Quyền")
            .sheet(item: $selectedAccount) { acc in
                AccountDetailView(account: acc, webAppUrl: webAppUrl) {
                    fetchData()
                }
            }
            .onAppear {
                initAudioAndNotification()
                startPolling()
            }
        }
    }

    func initAudioAndNotification() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
    }

    func startPolling() {
        stopPolling()
        fetchData()
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { _ in
            fetchData()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
        statusText = "Đã tạm dừng theo dõi"
    }

    func fetchData() {
        guard let url = URL(string: "\(webAppUrl)?action=get_all") else { return }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                guard let data = data, err == nil else {
                    self.statusText = "Lỗi kết nối máy chủ"
                    return
                }

                // Sửa thành SheetResponse.self để tránh lỗi compile exit code 65
                if let res = try? JSONDecoder().decode(SheetResponse.self, from: data), res.success, let list = res.data {
                    self.detectNewUnpaidOrders(newList: list)
                    self.accounts = list
                    self.statusText = "Cập nhật lúc: \(Date().formatted(date: .omitted, time: .standard))"
                }
            }
        }.resume()
    }

    func detectNewUnpaidOrders(newList: [AccountModel]) {
        if previousState.isEmpty {
            for item in newList { previousState[item.phone] = item.payment_status }
            return
        }

        for item in newList {
            let oldPayment = previousState[item.phone]
            // Báo động khi đơn chuyển sang UNPAID
            if item.payment_status == "UNPAID" && (oldPayment != "UNPAID") {
                triggerOrderAlert(account: item)
                self.selectedAccount = item
            }
            previousState[item.phone] = item.payment_status
        }
    }

    func triggerOrderAlert(account: AccountModel) {
        let content = UNMutableNotificationContent()
        content.title = "🚨 KHÁCH ĐẶT MUA / GIA HẠN!"
        content.body = "SĐT: \(account.phone) | Gói: \(account.amount)đ\n\(account.note)"
        content.sound = UNNotificationSound.defaultCritical

        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)

        AudioServicesPlayAlertSound(1005)
    }
}

// MARK: - Row hiển thị từng tài khoản
struct AccountRow: View {
    let account: AccountModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(account.phone)
                    .font(.headline)
                Spacer()
                
                Text(account.payment_status)
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(account.payment_status == "PAID" ? Color.green.opacity(0.15) : Color.orange.opacity(0.2))
                    .foregroundColor(account.payment_status == "PAID" ? .green : .orange)
                    .cornerRadius(4)

                Text(account.status)
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(account.status == "ACTIVE" ? Color.blue.opacity(0.15) : Color.red.opacity(0.15))
                    .foregroundColor(account.status == "ACTIVE" ? .blue : .red)
                    .cornerRadius(4)
            }

            HStack {
                Text("Hạn: \(account.expire_at.isEmpty ? "Chưa có" : account.expire_at)")
                Spacer()
                if let amt = Int(account.amount), amt > 0 {
                    Text("\(amt)đ")
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
            }
            .font(.footnote)
            .foregroundColor(.secondary)

            if !account.note.isEmpty {
                Text(account.note)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Màn hình chỉnh sửa & Kích hoạt tài khoản
struct AccountDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    @State var account: AccountModel
    let webAppUrl: String
    var onSaved: () -> Void

    @State private var isSaving = false
    @State private var alertMsg = ""
    @State private var showAlert = false

    var body: some View {
        NavigationView {
            Form {
                if account.payment_status == "UNPAID" {
                    Section {
                        VStack(spacing: 8) {
                            Text("Khách đang chờ duyệt thanh toán")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                            
                            Button(action: quickActivate) {
                                HStack {
                                    Spacer()
                                    if isSaving {
                                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Text("✅ ĐÃ NHẬN TIỀN - KÍCH HOẠT NGAY")
                                            .fontWeight(.bold)
                                    }
                                    Spacer()
                                }
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .disabled(isSaving)
                        }
                    }
                }

                Section(header: Text("Thông tin cơ bản")) {
                    HStack {
                        Text("Số điện thoại")
                        Spacer()
                        Text(account.phone).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Mật khẩu")
                        TextField("Password", text: $account.password)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Device ID")
                        TextField("Device ID", text: $account.device_id)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section(header: Text("Trạng thái & Hạn dùng")) {
                    Picker("Trạng thái", selection: $account.status) {
                        Text("ACTIVE").tag("ACTIVE")
                        Text("PENDING").tag("PENDING")
                        Text("EXPIRED").tag("EXPIRED")
                    }

                    Picker("Thanh toán", selection: $account.payment_status) {
                        Text("PAID").tag("PAID")
                        Text("UNPAID").tag("UNPAID")
                    }

                    HStack {
                        Text("Hết hạn lúc")
                        TextField("YYYY-MM-DD HH:mm:ss", text: $account.expire_at)
                            .multilineTextAlignment(.trailing)
                    }

                    Stepper("Trigger Sec: \(account.trigger_sec)s", value: $account.trigger_sec, in: 1...60)
                }

                Section(header: Text("Ghi chú & Số tiền")) {
                    HStack {
                        Text("Số tiền (đ)")
                        TextField("Amount", text: $account.amount)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    VStack(alignment: .leading) {
                        Text("Ghi chú").font(.caption).foregroundColor(.secondary)
                        TextEditor(text: $account.note)
                            .frame(height: 60)
                    }
                }
            }
            .navigationTitle(account.phone)
            .navigationBarItems(
                leading: Button("Đóng") { presentationMode.wrappedValue.dismiss() },
                trailing: Button("Lưu") { saveChanges() }.disabled(isSaving)
            )
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Thông báo"), message: Text(alertMsg), dismissButton: .default(Text("OK")) {
                    presentationMode.wrappedValue.dismiss()
                })
            }
        }
    }

    func quickActivate() {
        account.payment_status = "PAID"
        account.status = "ACTIVE"
        saveChanges()
    }

    func saveChanges() {
        isSaving = true
        var components = URLComponents(string: webAppUrl)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "update_account"),
            URLQueryItem(name: "phone", value: account.phone),
            URLQueryItem(name: "password", value: account.password),
            URLQueryItem(name: "device_id", value: account.device_id),
            URLQueryItem(name: "status", value: account.status),
            URLQueryItem(name: "expire_at", value: account.expire_at),
            URLQueryItem(name: "trigger_sec", value: String(account.trigger_sec)),
            URLQueryItem(name: "amount", value: account.amount),
            URLQueryItem(name: "payment_status", value: account.payment_status),
            URLQueryItem(name: "note", value: account.note)
        ]

        guard let targetUrl = components.url else { return }

        URLSession.shared.dataTask(with: targetUrl) { data, _, err in
            DispatchQueue.main.async {
                self.isSaving = false
                if let data = data, let str = String(data: data, encoding: .utf8), str.contains("\"success\":true") {
                    self.alertMsg = "Đã cập nhật dữ liệu thành công lên Google Sheet!"
                    self.showAlert = true
                    self.onSaved()
                } else {
                    self.alertMsg = "Lỗi cập nhật. Vui lòng thử lại!"
                    self.showAlert = true
                }
            }
        }.resume()
    }
}
