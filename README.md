# ChromeRemote

Bộ công cụ quản lý nhiều **Chrome Profile** (lưu riêng cookie, lịch sử đăng nhập) và khởi chạy Chrome với **Remote Debugging (`--remote-debugging-port=9222`)** để kết nối, điều khiển tự động qua **Chrome DevTools MCP**.

---

## Cấu trúc thư mục

```text
ChromeRemote/
├── chrome/                         # Bản Chrome portable (tự đặt vào, không lưu trên Git)
│   └── chrome.exe
└── ChromeMCPProfiles/
    ├── ProfileData/                # Dữ liệu profile (cookie/login — tự tạo khi chạy, không lưu trên Git)
    ├── profiles.example.csv        # File mẫu danh sách profile
    ├── profiles.csv                # File danh sách profile cá nhân (tự copy từ file mẫu)
    ├── tao_profile.ps1             # Script PowerShell tạo/cập nhật shortcut .lnk tự động
    ├── TAO_PROFILE.bat             # Click đúp để chạy nhanh tao_profile.ps1
    └── *.lnk                       # Các shortcut profile được tạo tự động
```

> **Lưu ý bảo mật:** Thư mục `chrome/`, `ChromeMCPProfiles/ProfileData/`, `profiles.csv` và các file `*.lnk` đã được chặn trong `.gitignore` để không đẩy dữ liệu đăng nhập cá nhân hoặc file thực thi nặng lên GitHub.

---

## 1. Chuẩn bị môi trường

1. **Clone dự án:**
   ```bash
   git clone https://github.com/kivie9/ChromeRemote.git
   cd ChromeRemote
   ```
2. **Đặt bản Chrome vào thư mục `chrome/`:**
   - Giải nén bản Chrome (hoặc Chrome for Testing / Chromium) vào thư mục `chrome/` sao cho có file `chrome\chrome.exe`.
   - *(Tuỳ chọn)* Nếu muốn dùng Chrome cài sẵn trên Windows, sửa biến `$ChromeExe` trong `ChromeMCPProfiles/tao_profile.ps1` thành:
     ```powershell
     $ChromeExe = "C:\Program Files\Google\Chrome\Application\chrome.exe"
     ```

---

## 2. Hướng dẫn tạo Profile hàng loạt

1. Copy file mẫu `ChromeMCPProfiles/profiles.example.csv` thành `ChromeMCPProfiles/profiles.csv`.
2. Mở `ChromeMCPProfiles/profiles.csv` bằng **Excel** hoặc **Notepad** và điền danh sách profile cần tạo:
   ```csv
   TenShortcut,ProfileDir,ThemeColor,AvatarIndex
   01-account1,Default,#1E88E5,27
   02-account2,Profile 02,#43A047,28
   03-account3,Profile 03,#FB8C00,29
   04-account4,,,
   ```
   - `TenShortcut`: Tên file shortcut `.lnk` sẽ được tạo.
   - `ProfileDir`: Tên thư mục con bên trong `ProfileData\`. Nếu để trống, script sẽ tự lấy theo `TenShortcut`.
   - `ThemeColor`: Mã màu hex chủ đạo của profile (ví dụ `#1E88E5`, `#43A047`, `#FB8C00`). Nếu để trống, script tự xoay vòng bảng màu mặc định.
   - `AvatarIndex`: Chỉ số avatar Chrome (`27` → `55`). Nếu để trống, script tự chọn lần lượt.
3. **Click đúp** vào `ChromeMCPProfiles/TAO_PROFILE.bat` (hoặc chạy bằng PowerShell):
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File ".\ChromeMCPProfiles\tao_profile.ps1"
   ```
4. Script sẽ tự động:
   - **Tạo mới** shortcut `.lnk` cho các profile chưa có.
   - **Cập nhật** nếu thông số/icon thay đổi.
   - **Bỏ qua** các shortcut đã khớp cấu hình (tránh tạo trùng `ProfileDir`).

---

## 3. Hướng dẫn khởi chạy Chrome Profile

### Cách 1: Mở bằng Shortcut (khuyên dùng)
Click đúp vào file `.lnk` tương ứng trong `ChromeMCPProfiles/` (ví dụ `02-account2.lnk`).

Lần đầu mở, Chrome sẽ tự động tạo thư mục profile tương ứng bên trong `ChromeMCPProfiles/ProfileData/` và lưu toàn bộ lịch sử đăng nhập, cookie, phiên làm việc cho các lần sau.

### Cách 2: Chạy bằng dòng lệnh (PowerShell / CMD)
```powershell
& ".\chrome\chrome.exe" `
  --remote-debugging-port=9222 `
  --user-data-dir="$PWD\ChromeMCPProfiles\ProfileData" `
  --profile-directory="Profile 02" `
  --no-default-browser-check `
  --no-first-run `
  --start-maximized
```

### Ý nghĩa các cờ khởi chạy
| Cờ (Flag) | Tác dụng |
| :--- | :--- |
| `--remote-debugging-port=9222` | Mở cổng DevTools để MCP / công cụ tự động hoá kết nối |
| `--user-data-dir="..."` | Chỉ định thư mục gốc chứa toàn bộ dữ liệu các profile |
| `--profile-directory="..."` | Chọn đúng profile cần mở (`Default`, `Profile 02`, `Profile 03`, ...) |
| `--no-default-browser-check` | Tắt thông báo hỏi đặt làm trình duyệt mặc định |
| `--no-first-run` | Bỏ qua màn hình chào mừng lần đầu |
| `--start-maximized` | Mở cửa sổ tối đa màn hình |

---

## 4. Kết nối và điều khiển qua Chrome DevTools MCP

1. Mở một profile bằng shortcut `.lnk` (hoặc dòng lệnh ở mục 3) để kích hoạt cổng debug `http://127.0.0.1:9222`.
2. Kiểm tra cổng debug đã sẵn sàng bằng cách truy cập:
   ```text
   http://127.0.0.1:9222/json/version
   ```
3. Cấu hình MCP server `chrome-devtools-mcp` trỏ tới `--browser-url=http://127.0.0.1:9222` (nếu client MCP chưa tự động kết nối mặc định vào cổng `9222`).

> **Lưu ý:** Khi các profile dùng chung một `--user-data-dir` và cùng cổng `9222`, chúng chạy chung một tiến trình Chrome. Nếu cần chạy nhiều phiên điều khiển độc lập song song, hãy tách riêng `--user-data-dir` và dùng các cổng khác nhau (`9222`, `9223`, `9224`, ...).
