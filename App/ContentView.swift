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

// MARK: - App Entry Point
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

// MARK: - Palette Màu Chuẩn Doanh Nghiệp (Stripe / Apple Style)
extension Color {
    static let appBackground = Color(red: 0.965, green: 0.973, blue: 0.984) // Xám băng mát mắt
    static let cardBackground = Color.white
    static let primaryText = Color(red: 0.06, green: 0.09, blue: 0.16)
    static let secondaryText = Color(red: 0.39, green: 0.45, blue: 0.55)
    static let brandBlue = Color(red: 0.14, green: 0.43, blue: 0.97)
    
    // Status colors
    static let statusPaidBg = Color(red: 0.88, green: 0.97, blue: 0.92)
    static let statusPaidText = Color(red: 0.09, green: 0.55, blue: 0.31)
    
    static let statusUnpaidBg = Color(red: 0.99, green: 0.94, blue: 0.86)
    static let statusUnpaidText = Color(red: 0.80, green: 0.42, blue: 0.05)
    
    static let statusActiveBg = Color(red: 0.91, green: 0.94, blue: 1.0)
    static let statusActiveText = Color(red: 0.14, green: 0.38, blue: 0.86)
}

// MARK: - Giao Diện Chính
struct ContentView: View {
    let webAppUrl = "https://script.google.com/macros/s/AKfycbz6gvfUZuyuO8-BW8tRVkoTFGPvZNu_eJPz1JtI9AuVnUQd2NLKcMCCQ4wBckVPPg5V/exec"

    @State private var accounts: [AccountModel] = []
    @State private var selectedAccount: AccountModel?
    @State private var searchText: String = ""
    @State private var selectedFilter: String = "ALL" // ALL, UNPAID, ACTIVE
    @State private var isMonitoring: Bool = true
    @State private var checkInterval: Double = 5
    @State private var statusText: String = "Sẵn sàng"
    
    @State private var previousState: [String: String] = [:]
    @State private var timer: Timer?

    // Bộ lọc dữ liệu theo thanh tìm kiếm và tag
    var filteredAccounts: [AccountModel] {
        accounts.filter { acc in
            let matchSearch = searchText.isEmpty || acc.phone.contains(searchText) || acc.note.localizedCaseInsensitiveContains(searchText)
            let matchFilter: Bool
            switch selectedFilter {
            case "UNPAID": matchFilter = (acc.payment_status == "UNPAID")
            case "ACTIVE": matchFilter = (acc.status == "ACTIVE" && acc.payment_status == "PAID")
            default: matchFilter = true
            }
            return matchSearch && matchFilter
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // 1. THANH CHỈ SỐ NHANH (KPI STATS)
                    kpiStatsView
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    // 2. THANH TÌM KIẾM & BỘ LỌC CHIP
                    searchAndFilterSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)

                    // 3. DANH SÁCH THẺ (CARDS LIST)
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredAccounts) { acc in
                                EnterpriseAccountCard(account: acc)
                                    .onTapGesture {
                                        selectedAccount = acc
                                    }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    .refreshable {
                        fetchData()
                    }
                }
            }
            .navigationTitle("Trung Tâm Bản Quyền")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: {
                            playAlert(account: AccountModel(phone: "0900000000", password: "", device_id: "", status: "PENDING", expire_at: "", trigger_sec: 3, note: "Test chuông", amount: "30000", payment_status: "UNPAID"))
                        }) {
                            Image(systemName: "bell.badge")
                                .foregroundColor(.brandBlue)
                        }

                        Toggle("", isOn: $isMonitoring)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .brandBlue))
                            .onChange(of: isMonitoring) { run in
                                if run { startPolling() } else { stopPolling() }
                            }
                    }
                }
            }
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
        .navigationViewStyle(StackNavigationViewStyle()) // Co giãn full màn hình iPad / iPhone
    }

    // KPI Metrics Bar
    var kpiStatsView: some View {
        HStack(spacing: 10) {
            MetricBox(title: "TỔNG MÁY", value: "\(accounts.count)", color: .primaryText)
            MetricBox(title: "ĐANG CHẠY", value: "\(accounts.filter { $0.status == "ACTIVE" }.count)", color: .statusPaidText)
            MetricBox(title: "CHỜ DUYỆT", value: "\(accounts.filter { $0.payment_status == "UNPAID" }.count)", color: .statusUnpaidText, isAlert: accounts.contains { $0.payment_status == "UNPAID" })
        }
    }

    // Search & Segmented Filter
    var searchAndFilterSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondaryText)
                TextField("Tìm số điện thoại, ghi chú...", text: $searchText)
                    .font(.system(size: 15))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white)
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(0.03), radius: 3, y: 1)

            // Chips
            HStack(spacing: 8) {
                FilterChip(title: "Tất cả (\(accounts.count))", isSelected: selectedFilter == "ALL") { selectedFilter = "ALL" }
                FilterChip(title: "Cần duyệt (\(accounts.filter { $0.payment_status == "UNPAID" }.count))", isSelected: selectedFilter == "UNPAID") { selectedFilter = "UNPAID" }
                FilterChip(title: "Đang Active (\(accounts.filter { $0.status == "ACTIVE" }.count))", isSelected: selectedFilter == "ACTIVE") { selectedFilter = "ACTIVE" }
                Spacer()
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
        statusText = "Đã tạm dừng"
    }

    func fetchData() {
        guard let url = URL(string: "\(webAppUrl)?action=get_all") else { return }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                guard let data = data, err == nil else {
                    self.statusText = "Mất kết nối máy chủ"
                    return
                }

                if let res = try? JSONDecoder().decode(SheetResponse.self, from: data), res.success, let list = res.data {
                    self.detectNewUnpaidOrders(newList: list)
                    self.accounts = list
                    self.statusText = "Đồng bộ lúc: \(Date().formatted(date: .omitted, time: .standard))"
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
            if item.payment_status == "UNPAID" && (oldPayment != "UNPAID") {
                playAlert(account: item)
                self.selectedAccount = item
            }
            previousState[item.phone] = item.payment_status
        }
    }

    func playAlert(account: AccountModel) {
        let content = UNMutableNotificationContent()
        content.title = "🚨 CÓ KHÁCH ĐẶT GIA HẠN"
        content.body = "SĐT: \(account.phone) • Gói: \(account.amount)đ\n\(account.note)"
        content.sound = UNNotificationSound.defaultCritical

        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)

        AudioServicesPlayAlertSound(1005)
    }
}

// MARK: - Component Thẻ Tài Khoản Nền Trắng Nổi Bật (Enterprise Card)
struct EnterpriseAccountCard: View {
    let account: AccountModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Hàng 1: SĐT & Các Tag trạng thái
            HStack(alignment: .center) {
                Text(account.phone)
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundColor(.primaryText)

                Spacer()

                // Tag Thanh Toán
                StatusBadge(
                    text: account.payment_status,
                    bgColor: account.payment_status == "PAID" ? Color.statusPaidBg : Color.statusUnpaidBg,
                    textColor: account.payment_status == "PAID" ? Color.statusPaidText : Color.statusUnpaidText
                )

                // Tag Trạng Thái
                StatusBadge(
                    text: account.status,
                    bgColor: account.status == "ACTIVE" ? Color.statusActiveBg : Color(red: 0.95, green: 0.95, blue: 0.96),
                    textColor: account.status == "ACTIVE" ? Color.statusActiveText : Color.secondaryText
                )
            }

            Divider()

            // Hàng 2: Hạn dùng & Số tiền
            HStack {
                Label {
                    Text(account.expire_at.isEmpty ? "Vô thời hạn" : account.expire_at)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondaryText)
                } icon: {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 13))
                        .foregroundColor(.secondaryText)
                }

                Spacer()

                if let amt = Int(account.amount), amt > 0 {
                    Text("\(amt.formatted()) đ")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primaryText)
                }
            }

            // Hàng 3: Ghi chú gói (nếu có)
            if !account.note.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondaryText)
                    Text(account.note)
                        .font(.system(size: 12))
                        .foregroundColor(.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .background(Color.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(account.payment_status == "UNPAID" ? Color.orange.opacity(0.4) : Color.black.opacity(0.04), lineWidth: account.payment_status == "UNPAID" ? 1.5 : 1)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Subcomponents
struct StatusBadge: View {
    let text: String
    let bgColor: Color
    let textColor: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bgColor)
            .foregroundColor(textColor)
            .cornerRadius(6)
    }
}

struct MetricBox: View {
    let title: String
    let value: String
    let color: Color
    var isAlert: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondaryText)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(isAlert ? Color.orange.opacity(0.1) : Color.white)
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.02), radius: 4, y: 1)
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.brandBlue : Color.white)
                .foregroundColor(isSelected ? .white : .secondaryText)
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.02), radius: 2, y: 1)
        }
    }
}

// MARK: - Màn Hình Chi Tiết / Duyệt Đơn
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
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Nút Kích Hoạt Nhanh Nổi Bật
                        if account.payment_status == "UNPAID" {
                            VStack(spacing: 10) {
                                Text("Khách hàng đang chờ duyệt thanh toán gói")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.orange)

                                Button(action: quickActivate) {
                                    HStack {
                                        Spacer()
                                        if isSaving {
                                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        } else {
                                            Image(systemName: "checkmark.seal.fill")
                                            Text("ĐÃ NHẬN TIỀN - KÍCH HOẠT")
                                                .font(.system(size: 15, weight: .bold))
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 14)
                                    .background(Color.statusPaidText)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                                .disabled(isSaving)
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.03), radius: 4, y: 2)
                        }

                        // Form Thông tin thẻ trắng
                        VStack(spacing: 14) {
                            formRow(label: "Số điện thoại") {
                                Text(account.phone)
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primaryText)
                            }
                            Divider()
                            formRow(label: "Mật khẩu") {
                                TextField("Password", text: $account.password)
                                    .multilineTextAlignment(.trailing)
                            }
                            Divider()
                            formRow(label: "Device ID") {
                                TextField("Device ID", text: $account.device_id)
                                    .font(.system(size: 13, design: .monospaced))
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)

                        // Form Trạng Thái & Hạn
                        VStack(spacing: 14) {
                            formRow(label: "Trạng thái chạy") {
                                Picker("", selection: $account.status) {
                                    Text("ACTIVE").tag("ACTIVE")
                                    Text("PENDING").tag("PENDING")
                                    Text("EXPIRED").tag("EXPIRED")
                                }
                                .pickerStyle(SegmentedPickerStyle())
                                .frame(width: 200)
                            }
                            Divider()
                            formRow(label: "Thanh toán") {
                                Picker("", selection: $account.payment_status) {
                                    Text("PAID").tag("PAID")
                                    Text("UNPAID").tag("UNPAID")
                                }
                                .pickerStyle(SegmentedPickerStyle())
                                .frame(width: 160)
                            }
                            Divider()
                            formRow(label: "Hết hạn lúc") {
                                TextField("YYYY-MM-DD HH:mm:ss", text: $account.expire_at)
                                    .font(.system(size: 13, design: .monospaced))
                                    .multilineTextAlignment(.trailing)
                            }
                            Divider()
                            formRow(label: "Trigger (giây)") {
                                Stepper("\(account.trigger_sec)s", value: $account.trigger_sec, in: 1...60)
                            }
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)

                        // Số tiền & Ghi chú
                        VStack(spacing: 14) {
                            formRow(label: "Số tiền (VNĐ)") {
                                TextField("0", text: $account.amount)
                                    .keyboardType(.numberPad)
                                    .font(.system(size: 16, weight: .bold))
                                    .multilineTextAlignment(.trailing)
                            }
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Ghi chú gói mua")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondaryText)
                                TextEditor(text: $account.note)
                                    .frame(height: 70)
                                    .padding(4)
                                    .background(Color.appBackground)
                                    .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Chi Tiết Tài Khoản")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Đóng") { presentationMode.wrappedValue.dismiss() },
                trailing: Button("Lưu") { saveChanges() }.disabled(isSaving).font(.system(size: 15, weight: .bold))
            )
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Thông báo"), message: Text(alertMsg), dismissButton: .default(Text("OK")) {
                    presentationMode.wrappedValue.dismiss()
                })
            }
        }
    }

    func formRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondaryText)
            Spacer()
            content()
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
                    self.alertMsg = "Đã cập nhật thành công lên Google Sheet!"
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
