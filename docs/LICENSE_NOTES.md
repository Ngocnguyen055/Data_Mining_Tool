# Trạng thái giấy phép

Cập nhật ngày **20/11/2026** theo lựa chọn của chủ dự án.

## Mã do dự án viết

**Chủ dự án chưa cấp license riêng cho mã benchmark.** Vì vậy repository chưa thêm file `LICENSE` với một giấy phép phần mềm cụ thể.

Phạm vi mã benchmark gồm:

- `benchmark_weka/WekaBenchmark.java`;
- `benchmark_weka/Run-Benchmark.ps1`;
- `benchmark_weka/Create-Charts.ps1`;
- các bản chụp mã tương ứng trong thư mục `source/` của lần benchmark tham chiếu.

Nếu sau này chủ dự án chọn giấy phép, cần thêm nội dung `LICENSE` tương ứng và cập nhật mục này cùng README. Tài liệu trạng thái này không tự cấp thêm quyền sử dụng cho mã nguồn, dữ liệu hoặc phần mềm bên thứ ba.

## Dataset và ARFF dẫn xuất

Nguồn đã xác nhận: [Groceries dataset — Heeral Dedhia, Kaggle](https://www.kaggle.com/datasets/heeraldedhia/groceries-dataset).

Loại license cụ thể trên Data Card Kaggle chưa được xác minh trong repository. Các file ARFF được tạo từ dataset này, vì vậy trạng thái giấy phép của dữ liệu cần được đối chiếu riêng với trang nguồn. Xem [DATA_SOURCES.md](DATA_SOURCES.md).

## WEKA

WEKA là thư viện bên thứ ba. [Trang chính thức WEKA](https://ml.cms.waikato.ac.nz/weka/) công bố phần mềm theo GNU General Public License; file `COPYING` trong bản WEKA 3.8.7 được dùng cho thực nghiệm mang nội dung **GNU GPL version 3**.

Repository dùng WEKA Java API và không kèm `weka.jar`, mã nguồn WEKA hoặc bộ cài WEKA. Người chạy benchmark sử dụng bản WEKA đã cài trên máy và cần tham chiếu giấy phép đi kèm bản cài đó.

## Kết quả và tài liệu trình bày

Các kết quả WEKA, CSV benchmark, biểu đồ, Word và slide được công bố cùng dự án để trình bày thực nghiệm. Chưa có giấy phép riêng được chủ dự án chọn cho nhóm tài liệu này. Việc chọn giấy phép cho mã benchmark sau này không tự thay giấy phép của dataset, WEKA hoặc tài liệu bên thứ ba.
