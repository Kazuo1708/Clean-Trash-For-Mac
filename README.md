# CleanMac

Ứng dụng macOS native SwiftUI giúp xem ứng dụng, cache, log, file cài đặt `.dmg` và dữ liệu dư thừa trước khi đưa chúng vào Thùng rác.

> **Trạng thái:** prototype/early alpha. Hãy kiểm tra từng mục trước khi xác nhận.

## Tính năng

- Quét ứng dụng trong `/Applications` và `~/Applications`.
- Tìm dữ liệu phụ trong `~/Library` như cache, log, Saved Application State, Containers và Application Support.
- Nhận diện `.dmg`, dữ liệu TFT/League/Riot và các thư mục có tên cache/crash.
- Bộ lọc theo nhóm, từ khóa, dung lượng tối thiểu, mục lớn và mục được đề xuất dọn.
- Tính tổng dung lượng và số lượng mục đang hiển thị.
- Chọn nhanh mục an toàn hoặc chọn thủ công.
- Hiển thị lý do, đường dẫn và dung lượng trước khi dọn.
- Hộp thoại xác nhận trước khi thao tác.
- Chỉ di chuyển vào `~/.Trash`, không xóa vĩnh viễn.
- Không thao tác trên vùng hệ thống được bảo vệ.
- Settings có nút đóng bằng dấu `×` và phím `Esc`.

## Chạy nhanh

Yêu cầu macOS 13+ và Xcode/Swift toolchain.

```bash
cd "/Users/macos/Desktop/APP ĐỤC SITE/Scan Trash File"
swift run CleanMac
```

Build trước nếu muốn:

```bash
swift build
.build/arm64-apple-macosx/debug/CleanMac
```

## Quy trình đề xuất

1. Quét ứng dụng & file rác.
2. Dùng ô tìm kiếm hoặc bộ lọc.
3. Mở rộng cửa sổ để xem đường dẫn đầy đủ.
4. Kiểm tra từng mục, đặc biệt là Application Support, Containers và file `.dmg`.
5. Chọn mục muốn dọn.
6. Xác nhận đưa vào Thùng rác.
7. Chỉ Empty Trash sau khi chắc chắn không cần khôi phục.

## Quyền riêng tư và an toàn

CleanMac không cần gửi dữ liệu ra ngoài. Ứng dụng đọc metadata file để tính dung lượng. Một số thư mục có thể yêu cầu quyền truy cập trong **System Settings → Privacy & Security → Full Disk Access**.

Không nên tự động xóa:

- `/System`
- `/private/var/db`
- dữ liệu đang dùng bởi ứng dụng khác
- thư mục dùng chung mà chưa kiểm tra
- bản sao lưu iPhone/iPad
- dữ liệu trình duyệt nếu vẫn cần phiên đăng nhập

## Giới hạn hiện tại

- Ghép file liên quan chủ yếu dựa trên tên và vị trí; có thể có false positive.
- Chưa có database chữ ký ứng dụng để phân biệt mọi dữ liệu dùng chung.
- Chưa có undo riêng trong app; có thể khôi phục từ Finder Trash.
- Tính năng dọn `.dmg` cần mở rộng để quét trực tiếp `~/Downloads` và các thư mục tải xuống tùy chọn.

## Cấu trúc

```text
Package.swift
Sources/MacTrashScannerApp/MacTrashScannerApp.swift
Documentation/USAGE.md
Documentation/SAFETY.md
Documentation/ROADMAP.md
```

## Đóng góp

Fork repository, tạo branch, mô tả thay đổi và gửi pull request. Không gửi log chứa đường dẫn cá nhân hoặc dữ liệu riêng tư.

## License

Chưa chọn license. Hãy thêm `LICENSE` trước khi phát hành công khai.
