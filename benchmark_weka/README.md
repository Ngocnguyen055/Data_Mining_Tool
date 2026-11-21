# Benchmark WEKA 3.8.7

Chạy **một lệnh** từ `C:\Projects\Data_Mining_Tool`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\benchmark_weka\Run-Benchmark.ps1
```

Chương trình tự tìm `weka.jar` đã cài, xác nhận phiên bản **3.8.7**, ưu tiên Java đi kèm WEKA và tìm `javac` trong PATH. Không đọc CSV, không lọc lại dữ liệu và không cài thư viện ngoài. Apriori và FP-Growth đều được gọi trực tiếp từ WEKA Java API.

Mỗi lần chạy tạo thư mục mới `benchmark_weka\results\run_<timestamp>_<id>\`. Không ghi đè lần chạy trước, ARFF hoặc kết quả Explorer cũ.

- `benchmark_raw.csv`: 80 dòng mặc định — 40 lần đo thời gian và 40 lần đo bộ nhớ, mỗi lần là một JVM mới.
- `benchmark_summary.csv`: 8 cấu hình, trung bình, trung vị, độ lệch chuẩn mẫu, min/max; tách baseline và peak, heap và RAM tiến trình.
- `runtime_comparison.png`: thời gian trung bình, không bật giám sát bộ nhớ.
- `memory_comparison.png`: heap Java dùng, baseline và sampled peak.
- `process_memory_comparison.png`: baseline working set và `PeakWorkingSet64` của toàn JVM.
- `benchmark_methodology.md`: cách đo, cấu hình máy/phần mềm, thông số thuật toán, bảng kết quả và giới hạn.
- `environment.json`, `runs\*.json`, `runs\*.log`, `runs\*.rules.tsv`: thông tin tái lập và chẩn đoán.
- `original_files_before.json` / `original_files_after.json`: SHA-256 chứng minh các file gốc không đổi.

Thời gian đo chỉ bao quanh `buildAssociations()`. Mỗi cấu hình chạy 5 lần ở mỗi đợt. JVM mới được dùng cho từng lần; đây là lần gọi đầu của thuật toán, có ảnh hưởng nạp lớp/JIT bên trong lời gọi. Dữ liệu và đối tượng thuật toán được chuẩn bị trước. Không có JVM benchmark chạy đồng thời. Trong từng lượt lặp, thứ tự cấu hình được xáo trộn với seed cố định.

Đợt bộ nhớ lấy mẫu heap bằng `MemoryMXBean` với khoảng nghỉ yêu cầu **1 ms**; khoảng thực tế và số mẫu được ghi vào CSV. Đây là ước lượng đỉnh qua lấy mẫu, có thể bỏ sót đỉnh ngắn. PowerShell theo dõi `PeakWorkingSet64` với khoảng nghỉ yêu cầu **5 ms**; đây là mốc đỉnh RAM do Windows lưu cho **toàn tiến trình**, gồm cả nạp ARFF, JVM, thư viện và mã đo. Hai phép đo không phải RAM riêng của thuật toán. Không dùng RAM cuối trừ RAM đầu làm đỉnh.

Chương trình dừng và giữ log nếu số luật khác **10, 57, 219, 450**, nếu tập luật của hai thuật toán khác nhau, hoặc nếu JVM lỗi. Không chỉnh số luật quan sát được. Tập luật được so sánh bằng danh sách mục và số đếm support nguyên; không chỉ so số lượng.

Nếu có nhiều bản WEKA, hoặc WEKA được cài ở nơi khác, chỉ định đường dẫn thực tế:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\benchmark_weka\Run-Benchmark.ps1 -WekaJar "D:\duong-dan-thuc-te\weka.jar"
```

Có thể truyền `-Java "...\java.exe"`, `-Javac "...\javac.exe"`, `-Repetitions 10`, hoặc `-MaximumHeap 4g`. Giữ cùng cấu hình JVM khi so sánh hai thuật toán. Nếu dùng một ARFF khác qua `-Dataset`, chương trình vẫn yêu cầu đúng cấu trúc và số luật của bài thực nghiệm này.

Nếu thiếu JDK, cài **Temurin JDK 64-bit** từ [trang chính thức Adoptium](https://adoptium.net/temurin/releases/), bật tùy chọn thêm vào PATH, mở lại PowerShell rồi kiểm tra:

```powershell
java -version
javac -version
```

JRE đi kèm WEKA có thể chạy Java nhưng không có `javac`; cần JDK để biên dịch. Trên máy đang làm bài, JDK Temurin 25.0.1 đã có sẵn; benchmark dùng Java BellSoft 25.0.2 đi kèm WEKA. File Java được biên dịch với đích bytecode Java 8. Bộ nhớ JVM mặc định: `-Xms256m -Xmx2g -XX:+UseG1GC`.

Để đọc kết quả: ưu tiên `runtime_mean_ms`, `runtime_median_ms`, `runtime_sd_ms` cho thời gian; `heap_peak_mean_mib` cho đỉnh heap lấy mẫu; `process_peak_mean_mib` cho RAM đỉnh toàn tiến trình. Cột `instrumented_runtime_ms` chỉ là thời gian khi đang giám sát bộ nhớ và không được dùng để kết luận tốc độ. Đơn vị MiB = 1.048.576 byte.
