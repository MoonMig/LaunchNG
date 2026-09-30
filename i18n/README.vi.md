# LaunchNG

**Ngôn ngữ**: [English](../README.md) | [简体中文](README.zh.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

macOS Tahoe (26) đã loại bỏ hoàn toàn Launchpad. LaunchNG mang nó trở lại dưới dạng một ứng dụng gốc: khi khởi chạy lần đầu, nó đọc trực tiếp bố cục Launchpad hiện có của bạn từ chính cơ sở dữ liệu của macOS, sau đó tự triển khai lại tính năng phân trang, thư mục, tìm kiếm và sắp xếp lại bằng kéo-thả trên một lưới được render bằng Core Animation, cùng với tích hợp Dock, một CLI/TUI đi kèm, và tính năng tự động cập nhật đã ký ngay trong ứng dụng.

## Tải xuống

**[Lấy bản phát hành mới nhất](https://github.com/moonmig/LaunchNG/releases/latest)**

Nếu bạn thấy hữu ích, một sao trên repository sẽ rất được trân trọng. LaunchNG khởi đầu là một fork của [LaunchNext](https://github.com/RoversX/LaunchNext) bởi RoversX — dự án gốc cũng xứng đáng nhận một sao.

<!-- Ảnh chụp màn hình sẽ ở đây — xem phần Đóng góp nếu bạn muốn gửi những ảnh mới nhất. -->

### Nếu macOS chặn ứng dụng khi mở lần đầu

Các bản phát hành là bản build không ký/ad-hoc (fork này không dùng tài khoản Apple Developer trả phí), vì vậy Gatekeeper sẽ từ chối mở ứng dụng cho đến khi bạn gỡ cờ cách ly một lần:

```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNG.app
```

Chỉ chạy lệnh này với các ứng dụng bạn thực sự tin tưởng — nó vô hiệu hóa việc kiểm tra cách ly tải xuống của macOS đối với ứng dụng đó.

Đang build từ mã nguồn? Xem [Cấu hình ký mã cục bộ](#configure-local-code-signing) bên dưới; bạn sẽ không cần lệnh này.

## LaunchNG làm được gì

- **Nhập bố cục chỉ với một cú nhấp từ cơ sở dữ liệu Launchpad thật** — đọc trực tiếp `/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db` và khôi phục chính xác các thư mục, vị trí và trang hiện có của bạn
- **Trải nghiệm lưới phân trang cổ điển** — tìm kiếm, điều hướng bằng bàn phím, sắp xếp lại bằng kéo-thả, tạo thư mục bằng cách kéo một biểu tượng lên biểu tượng khác
- **Render hoàn toàn bằng Core Animation**, bao gồm kéo-thả thẳng vào Dock và biểu tượng thư mục Liquid Glass gốc trên macOS 26
- **Bố cục thư mục**: phân trang (như bản gốc) hoặc cuộn dọc, tùy theo sở thích của bạn
- **Tìm kiếm mờ (fuzzy)** với khớp phiên âm CJK (bính âm, v.v.), để đầu vào một phần hoặc không chính xác vẫn tìm ra đúng ứng dụng
- **Kích hoạt bằng góc nóng và cử chỉ trackpad**, bao gồm hỗ trợ thử nghiệm chụm/chạm bằng 4/5 ngón tay
- **Một CLI và TUI** để kiểm tra hoặc viết script cho bố cục của bạn từ terminal
- **Cập nhật tự động đã ký** thông qua [Sparkle](https://sparkle-project.org), với nút "Kiểm tra cập nhật" thông thường trong ứng dụng
- **Sao lưu cục bộ** vào một thư mục bạn chọn, với lịch sử được quản lý để khôi phục
- **Ẩn nhãn biểu tượng ứng dụng, thay đổi kích thước biểu tượng, điều chỉnh khoảng cách** — độc lập cho lưới chính và nội dung thư mục
- **13 ngôn ngữ** với bản dịch giao diện đầy đủ (xem danh sách ngôn ngữ ở trên)
- **Menu ngữ cảnh nâng cao** — hiện trong Finder, sao chép đường dẫn ứng dụng, đổi tên thư mục, và (tùy chọn) một phím tắt để gỡ cách ly Gatekeeper cho các ứng dụng khác mà bạn tin tưởng
- **Hỗ trợ tay cầm điều khiển và phản hồi giọng nói** cho các thiết lập hướng đến khả năng tiếp cận

## Những gì macOS Tahoe đã lấy đi

- Không có thư mục do người dùng tạo hay tổ chức tùy chỉnh
- Không thể sắp xếp lại bằng kéo-thả
- Hoàn toàn không có quản lý ứng dụng trực quan — chỉ là một lưới được tạo tự động, sắp xếp theo bảng chữ cái, mà bạn không thể chạm vào

LaunchNG tồn tại vì đó là một bước lùi thực sự, không phải một mặc định hợp lý.

## Dữ liệu của bạn được lưu ở đâu

Bố cục, tùy chọn và bộ nhớ đệm riêng của LaunchNG được lưu tại:

```
~/Library/Application Support/LaunchNG/Data.store
```

Không có gì được gửi đi đâu cả. Hoạt động mạng duy nhất là kiểm tra feed cập nhật và, khi bạn chọn nhập, đọc chính cơ sở dữ liệu Launchpad của Apple tại:

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## Cài đặt

### Yêu cầu

- macOS 26 (Tahoe) trở lên
- Apple Silicon hoặc Intel
- Xcode 26, nếu build từ mã nguồn

### Build từ mã nguồn

```bash
git clone https://github.com/moonmig/LaunchNG.git
cd LaunchNG
open LaunchNG.xcodeproj
```

<a name="configure-local-code-signing"></a>**Cấu hình ký mã cục bộ** (không cần tài khoản Apple Developer trả phí):

- Chọn target **LaunchNG** → **Signing & Capabilities** → đặt **Team** thành `None`, chứng chỉ thành `Sign to Run Locally`. Giữ Hardened Runtime bật.
- Xcode sẽ đánh dấu file dự án là đã sửa đổi sau bước này — đừng đưa các thay đổi chỉ liên quan đến ký mã vào pull request.

Để chạy bằng `⌘R`, đích chạy phải là **My Mac** — đích universal/"Any Mac" có thể build và archive nhưng không thể chạy để debug. `⌘B` chỉ để build.

### Build từ dòng lệnh

```bash
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release

# Binary universal (Apple Silicon + Intel):
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## Cách sử dụng

1. **Khi khởi chạy lần đầu** sẽ tự động quét các ứng dụng đã cài đặt của bạn.
2. **Settings → General → Import System Launchpad** nhập bố cục, thư mục và vị trí hiện có của bạn chỉ với một cú nhấp.
3. Nhấp để chọn, nhấp đúp (hoặc Return) để mở; gõ ở bất kỳ đâu để tìm kiếm ngay lập tức.
4. Kéo một ứng dụng lên ứng dụng khác để tạo thư mục; kéo các ứng dụng để sắp xếp lại.
5. Tùy chọn bật CLI trong Settings nếu bạn muốn viết script cho bố cục từ terminal.

### Toàn màn hình so với thu gọn

- **Toàn màn hình** phủ kín toàn bộ màn hình, gần giống Launchpad gốc nhất.
- **Thu gọn** là một cửa sổ nổi, bo góc mà bạn có thể thay đổi kích thước.
- Các cài đặt giao diện (tỷ lệ biểu tượng, khoảng cách, vị trí chỉ báo trang, v.v.) được lưu riêng cho từng chế độ.
- Chế độ toàn màn hình có thể tùy chọn ẩn thanh menu; macOS sẽ tự động ẩn Dock khi bật tính năng đó.

## Cài đặt đáng chú ý

- **Giao diện**: tỷ lệ biểu tượng, kích thước và khả năng hiển thị nhãn, khoảng cách lưới — với giá trị riêng cho nội dung thư mục — cùng một kiểu nền (làm mờ, Liquid Glass gốc, hoặc nền lấy từ hình nền động)
- **Tìm kiếm**: bật/tắt khớp mờ và thời gian debounce tìm kiếm
- **Ứng dụng ẩn**: giữ các ứng dụng cụ thể ngoài lưới mà không cần gỡ cài đặt
- **Sao lưu**: chọn một thư mục, tạo bản sao lưu có dấu thời gian, khôi phục hoặc xóa các bản cũ từ danh sách
- **Phím tắt & cử chỉ**: phím tắt toàn cục, góc nóng, và các liên kết cử chỉ trackpad (thử nghiệm)
- **Cập nhật**: bật/tắt kiểm tra tự động và nút "Kiểm tra cập nhật" thủ công, cả hai đều dựa trên Sparkle

## Khắc phục sự cố

**Ứng dụng không khởi động.** Xác nhận bạn đang dùng macOS 26.0 trở lên và cờ cách ly đã được gỡ bỏ (xem ở trên).

**"Kiểm tra cập nhật" báo lỗi.** LaunchNG dùng Sparkle với feed cập nhật đã ký; một lần kiểm tra thủ công luôn phải phản ánh bản phát hành mới nhất trong vòng vài phút.

**Không thấy lệnh `launchng` trong terminal.** Đây là tính năng tùy chọn — hãy bật giao diện dòng lệnh trong Settings trước, LaunchNG sẽ tự cài đặt (và sau này có thể gỡ bỏ) shim được quản lý.

## Đóng góp

1. Fork repository
2. Tạo nhánh tính năng (`git checkout -b feature/tinh-nang-cua-ban`)
3. Commit các thay đổi với thông điệp rõ ràng
4. Push nhánh và mở pull request

Một vài điều giúp việc review diễn ra suôn sẻ:
- Giữ các thay đổi dự án Xcode chỉ liên quan đến ký mã ra khỏi diff của bạn (xem phần ký mã cục bộ ở trên)
- Nếu bạn động vào lưới Core Animation, hãy kiểm tra `GridReorderPlan.swift` trước — logic sắp xếp lại/phân trang nên nằm ở đó, không lặp lại theo từng view
- Chạy bộ test suite trước khi mở PR:
  ```bash
  xcodebuild test -scheme LaunchNG -destination 'platform=macOS'
  ```

Ảnh chụp màn hình mới, cập nhật (lưới chính, vài tab Settings) cũng là đóng góp thực sự hữu ích — xem phần giữ chỗ gần đầu file này.

### Tài liệu thêm

- [Folder Liquid Glass](../Documentation/FolderLiquidGlass.md) — các ràng buộc thiết kế đằng sau biểu tượng thư mục kính, những gì đã được xác minh và những gì vẫn cần kiểm thử chấp nhận
- [Grid diagnostics](../scripts/diagnostics/README.md) — các công cụ dò thủ công cho lưới và lớp phủ kính, cùng phạm vi và giới hạn chính xác của chúng

## Giấy phép và ghi nhận

LaunchNG là một fork của [LaunchNext](https://github.com/RoversX/LaunchNext) bởi RoversX, mà bản thân nó bắt nguồn từ nỗ lực cộng đồng rộng lớn hơn nhằm thay thế Launchpad. Cả hai dự án đều được cấp phép GPL-3.0, và LaunchNG tuân theo các điều khoản tương tự — xem [LICENSE](../LICENSE).

Hỗ trợ cử chỉ trackpad thử nghiệm được xây dựng trên [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) và bản fork bởi [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport).

---

![GitHub downloads](https://img.shields.io/github/downloads/moonmig/LaunchNG/total)
