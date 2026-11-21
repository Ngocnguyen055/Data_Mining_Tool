# Đưa dự án lên GitHub

Hướng dẫn chạy trong PowerShell tại thư mục gốc dự án. Repository đã được chuẩn bị README, `.gitignore`, `.gitattributes`, thông tin nguồn dữ liệu và trạng thái giấy phép; chủ dự án tự thực hiện commit, tạo repository trên GitHub và push.

## 1 Kiểm tra nội dung dự định đưa lên

Nếu thư mục chưa được khởi tạo Git:

```powershell
git init -b main
```

Kiểm tra danh sách file trước khi stage:

```powershell
git status --short
git ls-files --others --exclude-standard
git add --dry-run .
```

Nội dung cần có: mã Java/PowerShell, ARFF, 12 file kết quả WEKA, kết quả benchmark tham chiếu, Word, slide và ảnh bảng. `.class`, log, file `.ready/.go/.complete/.release`, lượt benchmark thử lỗi và `presentation_tables/_build/` đã được bỏ qua.

Mặc định chỉ thư mục `run_20261113_224427_764_9d8ed359` được chọn làm kết quả benchmark tham chiếu để đưa lên. Muốn thêm một lần chạy khác, bổ sung dòng ngoại lệ tương ứng trong `.gitignore` rồi kiểm tra lại.

Thông tin nguồn và giấy phép nằm trong [DATA_SOURCES.md](DATA_SOURCES.md) và [LICENSE_NOTES.md](LICENSE_NOTES.md). Chủ dự án đã chọn chưa cấp license cho mã benchmark; license cụ thể của dataset vẫn cần đối chiếu với Data Card Kaggle.

## 2 Stage và tạo commit đầu tiên

```powershell
git add .
git diff --cached --stat
git status
git commit -m "Initial commit: WEKA market basket analysis"
```

Nếu Git báo chưa có danh tính tác giả, cấu hình cho riêng repository này bằng thông tin của bạn rồi chạy lại lệnh commit:

```powershell
git config user.name "Ten cua ban"
git config user.email "Email GitHub hoac dia chi noreply cua ban"
```

## 3 Tạo repository trống trên GitHub

Tạo repository mới, ví dụ `supermarket-market-basket-analysis`. Chọn phạm vi public hoặc private theo nhu cầu của bạn. Ở bước tạo repository, để trống các tùy chọn khởi tạo README, `.gitignore` và license vì chúng đã được chuẩn bị cục bộ.

Sao chép URL HTTPS của repository vừa tạo. Thay `YOUR_USERNAME` và tên repository trong lệnh dưới bằng thông tin thực tế:

```powershell
git remote add origin https://github.com/YOUR_USERNAME/supermarket-market-basket-analysis.git
git remote -v
git push -u origin main
```

Thực hiện đăng nhập GitHub khi trình quản lý thông tin xác thực yêu cầu. Không ghi token vào README, file mã nguồn hoặc URL remote.

## 4 Kiểm tra sau khi push

Mở trang repository và kiểm tra README, ảnh benchmark, đường dẫn tới Word/slide, hai ARFF và CSV kết quả. Tải hoặc clone thử repository rồi chạy lệnh benchmark từ README nếu muốn kiểm tra trên một máy khác có JDK và WEKA 3.8.7.

Đối chiếu hướng dẫn chính thức: [Adding locally hosted code to GitHub](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github).
