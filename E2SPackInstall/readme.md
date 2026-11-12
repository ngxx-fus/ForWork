# FSP Pack Installer

`PackInstall.sh` (Bash for Linux / containers) and `PackInstall.ps1` (PowerShell for Windows) automate downloading, extracting, and deploying both the standard Renesas FSP pack and the INTERNAL pack into the `internal` directory of an Eclipse / e² studio environment.

---

## Quick Start

### On Linux / Containers (Coder, WSL, Ubuntu):
```bash
chmod +x ./PackInstall.sh
./PackInstall.sh
```

### On Windows:
```powershell
# Run with ExecutionPolicy Bypass if script execution is restricted
powershell -ExecutionPolicy Bypass -File .\PackInstall.ps1
```

Script sẽ tự động:
1. Nhận diện thư mục e² studio (`com.renesas.platform_<digits>`) trong `.eclipse`.
2. Lấy danh sách phiên bản FSP từ Artifactory và mở giao diện `fzf` để bạn chọn.
3. Tải các gói pack về thư mục temp (`/tmp/pack_install` hoặc `%TEMP%\pack_install`).
4. Giải nén và sao chép toàn bộ nội dung vào thư mục `internal/` của IDE.

---

## Features

- **Tự động nhận diện thư mục e² studio (Auto-Detection)**: Tự động quét regex `com.renesas.platform_[0-9]+` trong `~/.eclipse/` (Linux) hoặc `%USERPROFILE%\.eclipse\` (Windows) để tìm đúng thư mục hỗ trợ platform và `internal/`. Bỏ qua các thư mục phụ khác (như `com.renesas.platform_26.10.0_...`).
- **Tải file vào thư mục Temp**: Tải các file pack ZIP vào thư mục tạm thời (`/tmp/pack_install` hoặc `%TEMP%\pack_install`) thay vì lưu tại thư mục làm việc hiện tại.
- **Chọn phiên bản trực quan**: Sử dụng `fzf` để duyệt và chọn version (release) hoặc branch & build (manual snapshot).
- **Tự động kiểm tra & cài đặt công cụ (Linux)**: Tự kiểm tra các dependency (`curl`, `grep`, `fzf`, `unzip`) và hỏi để cài đặt tự động qua `apt`, `xbps`, `dnf`, hoặc `pacman`.
- **Hỗ trợ cài đặt Offline (Local ZIP)**: Bỏ qua bước tải bằng cách truyền đường dẫn 2 file ZIP pack có sẵn.
- **Tùy chọn Clean Install**: Dọn sạch thư mục `internal` cũ trước khi giải nén các pack mới.

---

## Prerequisites

### Cho Linux / Bash (`PackInstall.sh`):
* Bash 4+
* Các công cụ: `curl`, `grep`, `fzf`, `unzip` (script sẽ tự đề xuất cài đặt nếu thiếu).
* Kết nối mạng tới Artifactory (nếu tải online).
* **Đóng e² studio / Eclipse** trước khi chạy để tránh lỗi xung đột/khóa file.

### Cho Windows (`PackInstall.ps1`):
* Windows PowerShell 5.1 hoặc PowerShell 7+.
* Đã cài đặt `fzf` và có trong `PATH` (không bắt buộc nếu truyền cả 2 file zip local).
* Kết nối mạng tới Artifactory (nếu tải online).
* **Đóng e² studio / Eclipse** trước khi chạy.

---

## Configuration

Toàn bộ cấu hình được đưa lên **đầu file** của cả hai script (`PackInstall.sh` và `PackInstall.ps1`) trong khối **`CONFIGURATION & DEFAULT SETTINGS`**:

| Biến cấu hình | Ý nghĩa | Giá trị mặc định |
| --- | --- | --- |
| `BASE_URL_RELEASE` | Endpoint Artifactory cho bản Release chính thức. | `https://artifactory.global.renesas.com/artifactory/fsp-ra/release/` |
| `BASE_URL_MANUAL` | Endpoint Artifactory cho bản snapshot/build nhánh manual. | `https://artifactory.global.renesas.com/artifactory/fsp-ra/manual/` |
| `SOURCE` | Chế độ nguồn: `"release"` (mặc định) hoặc `"manual"`. | `"release"` |
| `DIR_INTERNAL` | Đường dẫn tới thư mục `internal/` đích. Nếu để `""`, script sẽ tự động tìm thông qua `DIR_E2S_SUPPORT`. | `""` (auto-detect) |
| `DIR_E2S_SUPPORT` | Thư mục nền tảng e² studio (`com.renesas.platform_<digits>`). Nếu để `""`, script tự động quét tìm. | `""` (auto-detect) |
| `DIR_DOWNLOADS` | Thư mục lưu file ZIP tải về. | `${TMPDIR:-/tmp}/pack_install` (Linux)<br>`$env:TEMP\pack_install` (Windows) |
| `DIR_EXTRACTED` | Thư mục tạm dùng để giải nén file pack. | `${TMPDIR:-/tmp}` (Linux)<br>`$env:TEMP` (Windows) |
| `CLEANALL` | Xóa sạch thư mục `internal` đích trước khi cài. | `false` |
| `ZIP0` / `ZIP1` | Đường dẫn file ZIP pack có sẵn (nếu dùng local). | `""` |

> [!TIP]
> **Cơ chế tự động dò tìm (Auto-Detection):**
> Khi `DIR_INTERNAL` để trống, cả hai script sẽ tìm trong `~/.eclipse/` (hoặc `/home/coder/.eclipse/` trên Linux) các thư mục có tên khớp mẫu `com.renesas.platform_[0-9]+` (ví dụ `com.renesas.platform_2047834950`).
> - Nếu tìm thấy **1 thư mục**: Tự động chọn và gán `DIR_INTERNAL="${DIR_E2S_SUPPORT}/internal/"`.
> - Nếu tìm thấy **nhiều thư mục**: Mở giao diện `fzf` để bạn chọn thư mục mong muốn.
> - Nếu **không tìm thấy**: Script sẽ báo lỗi và nhắc bạn điền đường dẫn vào biến cấu hình hoặc truyền qua cờ `-d` (`-dirinternal`).

---

## Tham số dòng lệnh (CLI Options)

| Linux (`PackInstall.sh`) | Windows (`PackInstall.ps1`) | Mô tả |
| --- | --- | --- |
| `-c` | `-cleanall` | Hỏi xác nhận và xóa sạch nội dung trong thư mục `internal` trước khi giải nén. |
| `-d <path>` | `-dirinternal <path>` | Ghi đè đường dẫn thư mục `internal/` đích. |
| `-z <path>` | `-zip0 <path>` | Đường dẫn tới file ZIP **public pack**. |
| `-Z <path>` | `-zip1 <path>` | Đường dẫn tới file ZIP **internal pack**. |
| `-o <path>` | `-dirdownloads <path>` | Thư mục lưu file ZIP tải về. |
| `-s <source>` | `-source <source>` | Nguồn tải: `'release'` (mặc định) hoặc `'manual'`. |
| `-h` | - | Hiển thị trợ giúp và thoát. |

> [!IMPORTANT]
> Script chỉ bỏ qua bước kết nối Artifactory và `fzf` khi bạn cung cấp **đồng thời cả hai file ZIP** (`-z` và `-Z` hoặc `-zip0` và `-zip1`).

---

## Ví dụ sử dụng

### 1. Tải bản Release và cài đặt tự động (Khuyên dùng)

**Linux / Bash:**
```bash
./PackInstall.sh
```

**Windows PowerShell:**
```powershell
.\PackInstall.ps1
```

### 2. Tải bản build thử nghiệm (Manual snapshot / Branch)

**Linux / Bash:**
```bash
./PackInstall.sh -s manual
```

**Windows PowerShell:**
```powershell
.\PackInstall.ps1 -source manual
```

### 3. Dọn sạch thư mục cũ trước khi cài đặt (`-c`)

**Linux / Bash:**
```bash
./PackInstall.sh -c
```

**Windows PowerShell:**
```powershell
.\PackInstall.ps1 -cleanall
```

### 4. Cài đặt từ 2 file ZIP có sẵn trong máy (Offline)

**Linux / Bash:**
```bash
./PackInstall.sh \
    -z /tmp/FSP_Packs_v6.6.0.zip \
    -Z /tmp/FSP_Packs_INTERNAL_v6.6.0.zip
```

**Windows PowerShell:**
```powershell
.\PackInstall.ps1 `
    -zip0 'C:\Downloads\FSP_Packs_v6.6.0.zip' `
    -zip1 'C:\Downloads\FSP_Packs_INTERNAL_v6.6.0.zip'
```

### 5. Chỉ định đường dẫn tùy chỉnh

**Linux / Bash:**
```bash
./PackInstall.sh \
    -d /home/coder/.eclipse/com.renesas.platform_2047834950/internal \
    -o /tmp/custom_downloads
```

**Windows PowerShell:**
```powershell
.\PackInstall.ps1 `
    -dirinternal 'C:\CustomIDE\.eclipse\internal' `
    -dirdownloads 'C:\CustomDownloads'
```

---

## Quy trình hoạt động bên dưới (Workflow Details)

1. **Kiểm tra công cụ**: Xác minh đầy đủ các tiện ích cần thiết (`curl`, `grep`, `fzf`, `unzip`).
2. **Xác định môi trường & Thư mục**: Tự động nhận diện thư mục platform e² studio (`DIR_E2S_SUPPORT`) và thư mục `internal` (`DIR_INTERNAL`).
3. **Lấy Pack**:
   - Nếu có sẵn cả 2 file ZIP local: Sử dụng trực tiếp.
   - Nếu tải online: Lấy danh sách từ Artifactory, cho người dùng chọn qua `fzf`, rồi tải về thư mục temp (`/tmp/pack_install` hoặc `%TEMP%\pack_install`). Nếu file đã tồn tại sẽ bỏ qua tải lại.
4. **Dọn dẹp (Tùy chọn)**: Nếu có cờ `-c` / `-cleanall`, xác nhận người dùng rồi làm sạch thư mục `internal` đích.
5. **Giải nén**: Giải nén cả 2 pack vào thư mục tạm.
6. **Sao chép**: Copy các file từ public pack trước, sau đó ghi đè các file từ internal pack vào thư mục `internal` của IDE.
