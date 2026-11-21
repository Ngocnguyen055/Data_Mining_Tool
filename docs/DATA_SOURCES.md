# Nguồn dữ liệu và khả năng đối chiếu

## Nguồn gốc

- Dataset: **Groceries dataset**.
- Người đăng trên Kaggle: **Heeral Dedhia**, tài khoản `heeraldedhia`.
- Trang nguồn: <https://www.kaggle.com/datasets/heeraldedhia/groceries-dataset>.
- Chủ dự án xác nhận ngày **20/11/2026**: đã tải từ link trên, giải nén, sau đó xử lý trong WEKA.

Xác nhận này ghi lại nguồn do chủ dự án cung cấp. Repository hiện không chứa ZIP tải về hoặc CSV gốc, nên chưa thể đối chiếu byte hay hash với bản tải ban đầu và chưa xác minh lại ngày lịch gốc.

## Các file trong dự án

| File | Vai trò | Thông tin đã kiểm tra |
|---|---|---|
| `groceries_sorted.arff` | Dữ liệu trung gian ở mức sản phẩm | 38.765 dòng; 3.898 Member_number; 167 sản phẩm; giữ Date và Basket_ID |
| `groceries_basket.arff` | Đầu vào benchmark | 14.963 giỏ × 167 thuộc tính `{f,t}` |
| `Apriori_*.txt`, `FPGrowth_*.txt` | Kết quả xuất từ WEKA Explorer | Bốn support và ba confidence, với confidence 0.05 dùng kết quả Support_0.001 |
| `benchmark_weka/results/run_20261113_224427_764_9d8ed359/` | Thực nghiệm Java API tham chiếu | 80 lượt; 8 cấu hình; đối chiếu cùng tập luật giữa hai thuật toán |

Giỏ được nhóm theo cùng `Member_number` và cùng `Date`. Trong file trung gian, `Basket_ID = Member_number × 1000 + Date`; Date có giá trị số từ 0 đến 727 và không có trùng ID giữa các cặp khác nhau. Nội dung và số lần xuất hiện của toàn bộ các giỏ đã được đối chiếu với ma trận cuối.

Tên relation của các ARFF lưu dấu vết các bước `OrdinalToNumeric`, `AddExpression`, `Remove` và `Denormalize`; đó là thông tin của file đã lưu, không thay thế toàn bộ cấu hình thao tác Explorer. Mã trong repository thực hiện benchmark trên ARFF đã xử lý.

## Dấu vân tay dữ liệu

SHA-256 của hai file đang dùng:

```text
groceries_basket.arff
69D2CA2626095B970FD4D63FB9888358EE4D1F127B9A558E617CC4ECF218DB18

groceries_sorted.arff
4646DAC849CFB370AC1C395146D928664CFA8AA7B94790A9A6932DDEF908B93F
```

Có thể kiểm tra bằng PowerShell từ thư mục gốc:

```powershell
Get-FileHash .\groceries_basket.arff -Algorithm SHA256
Get-FileHash .\groceries_sorted.arff -Algorithm SHA256
```

`.gitattributes` tắt chuyển đổi xuống dòng cho các file dữ liệu và kết quả thực nghiệm để hash không bị đổi chỉ vì clone trên hệ điều hành khác.

## Giấy phép và thông tin còn thiếu

Nguồn Kaggle đã được chủ dự án xác nhận, nhưng **loại license cụ thể của dataset trên Data Card chưa được xác minh**. Không gán MIT, GPL hoặc CC0 cho dữ liệu chỉ dựa trên việc dữ liệu được đăng công khai; đối chiếu mục License ở trang nguồn trước khi xác nhận điều kiện phân phối lại các file ARFF.

Tham khảo cơ chế khai báo license của Kaggle: [Kaggle Datasets documentation](https://www.kaggle.com/docs/datasets). Trạng thái mã benchmark và phần mềm WEKA được ghi riêng tại [LICENSE_NOTES.md](LICENSE_NOTES.md).

Các giới hạn còn lại: không có CSV/ZIP gốc trong repository, chưa khôi phục ngày lịch từ Date mã hóa, và không có giá bán, doanh thu, lợi nhuận hoặc kết quả thử nghiệm kinh doanh.
