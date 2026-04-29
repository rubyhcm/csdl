II. TÊN ĐỀ TÀI
Nghiên cứu và Xây dựng hệ thống Audit Log hiệu năng cao trên PostgreSQL sử dụng Partitioning và JSONB
III. CHI TIẾT ĐỀ TÀI
1.	Giới thiệu
1.1 Mục tiêu nghiên cứu
Giải quyết bài toán lưu vết dữ liệu (Audit Trail) trong các hệ thống thông tin lớn (Tài chính, Ngân hàng) với ba thách thức chính:
●	Khối lượng dữ liệu tăng trưởng nhanh (Big Data)
●	Yêu cầu không làm chậm hiệu năng hệ thống (Latency)
●	Đảm bảo tính toàn vẹn dữ liệu trước sự can thiệp của người quản trị (Data Integrity & Security)
1.2	Tổng quan giải pháp
Để giải quyết bài toán lưu vết dữ liệu (Audit Trail), hiện nay có một số phương pháp phổ biến:
•	Logical Decoding (Đọc từ WAL - Write-Ahead Logging): Ghi nhận thay đổi ở cấp độ engine cơ sở dữ liệu. Nhược điểm là khó ánh xạ chính xác thông tin người dùng ứng dụng (Application User) thực hiện giao dịch, và yêu cầu thiết lập phức tạp.
•	Sử dụng Extension (Ví dụ: pgaudit): Hỗ trợ tốt nhưng ghi log dưới dạng text thô (raw text) vào file log của hệ điều hành, gây khó khăn cho việc truy vấn có cấu trúc, tìm kiếm và phân tích báo cáo sau này. * Phương pháp đề xuất (Trigger + JSONB + Partitioning): Vượt trội ở khả năng giải quyết triệt để vấn đề tìm kiếm trên dữ liệu phức tạp nhờ sức mạnh của JSONB và GIN Index, đồng thời duy trì hiệu năng cao cho hệ thống lớn thông qua cơ chế phân mảnh Partitioning
1.3	So sánh các giải pháp
| Tiêu chí | Trigger + JSONB | pgAudit | CDC (Debezium) |
|----------|----------------|--------|----------------|
| Structured Query | Có | Không | Hạn chế |
| Real-time | Không | Không | Có |
| Application Context | Có | Không | Không |
| Độ phức tạp | Trung bình | Thấp | Cao |

Khi KHÔNG nên dùng:
- Hệ thống cần real-time streaming
- Throughput cực cao (>10k TPS)
- Kiến trúc microservices đa database

Sơ đồ tổng quan hệ thống

 
1.4. Trade-offs

JSONB:
+ Linh hoạt
- Tốn storage
- Query phức tạp

Trigger:
+ Không cần sửa app
- Tăng latency
- Khó debug

Partition:
+ Quản lý dữ liệu tốt
- Query cross-partition có thể chậm


2. Nội dung thực hiện
●	Lưu trữ:
●	Sử dụng kiểu dữ liệu JSONB (Binary JSON) để lưu trữ linh hoạt (Schema-less) trạng thái dữ liệu trước và sau khi thay đổi (OLD và NEW values), cho phép một bảng Log duy nhất phục vụ cho toàn bộ hệ thống.
●	Áp dụng kỹ thuật Declarative Partitioning (Phân mảnh theo thời gian) để tối ưu hóa việc quản lý các bảng Log có kích thước lớn, hỗ trợ truy vấn nhanh và lưu trữ phân cấp (Tablespace). 
●	Xử lí:
●	Xây dựng các Dynamic Triggers và Generic Functions bằng ngôn ngữ PL/pgSQL để tự động hóa việc bắt các sự kiện INSERT, UPDATE, DELETE mà không cần can thiệp vào mã nguồn ứng dụng.
●	Tối ưu hóa thuật toán ghi log để đảm bảo độ trễ (Overhead) ở mức thấp nhất, không gây tắc nghẽn (Blocking I/O) cho các giao dịch nghiệp vụ chính.
●	An toàn - Bảo mật:
●	Triển khai mô hình SECURITY DEFINER trong Stored Procedures để thiết lập cơ chế ủy quyền: Người dùng có thể kích hoạt ghi Log nhưng không có quyền truy cập trực tiếp vào bảng Log.
●	Xây dựng cơ chế Immutability (Bất biến): Sử dụng Trigger chặn chiều DELETE/UPDATE trên bảng Log, biến bảng này thành dạng "Append-Only", đảm bảo ngay cả tài khoản Admin cũng không thể xóa log.
3. Kết quả dự kiến
●	Mô hình cơ sở dữ liệu hoàn chỉnh với Partitioning và JSONB Indexing.
●	Bộ Script PL/pgSQL tự động hóa việc Audit cho các bảng nghiệp vụ.
●	Báo cáo thực nghiệm so sánh hiệu năng (TPS - Transactions Per Second) giữa việc có và không có Audit Log.
●	Kịch bản Demo tấn công giả lập: Chứng minh hệ thống ngăn chặn được nỗ lực xóa log của tài khoản có quyền cao. 

4. Dữ liệu và Kịch bản Thực nghiệm


Để chứng minh tính đúng đắn và hiệu quả của giải pháp, quá trình thực nghiệm sẽ được tiến hành trên mô hình giả lập với các thông số và kịch bản cụ thể như sau:

4.1. Môi trường Thực nghiệm

Để đảm bảo tính nhất quán của số liệu đo đạc (Benchmark), hệ thống thử nghiệm được thiết lập với cấu hình:

Hệ quản trị CSDL: PostgreSQL phiên bản 16 (Hỗ trợ tối ưu cho JSONB và Partitioning).

Hệ điều hành: Window 11 với (Ubuntu Server 22.04 LTS - WSL2).

Phần cứng: 4 vCPU, 8GB RAM, ổ cứng 20GB SSD

Công cụ đo lường: pgbench (Công cụ chuẩn của PostgreSQL để Stress Test).
Lưu ý về khả năng mở rộng (Scalability): > Môi trường thử nghiệm hiện tại đóng vai trò là Proof of Concept (PoC) để kiểm chứng tính khả thi của thuật toán và kiến trúc cơ sở dữ liệu. Trong môi trường vận hành thực tế (Production), hiệu năng ghi log của PostgreSQL sẽ phụ thuộc rất lớn vào tốc độ xử lý của ổ cứng (Disk I/O). Việc sử dụng kỹ thuật Declarative Partitioning trong đề tài này mở ra khả năng tối ưu hóa lưu trữ phân cấp bằng Tablespace: các Partition "nóng" (tháng hiện tại) có thể đặt trên ổ cứng NVMe/SSD tốc độ cao, trong khi các Partition "nguội" (dữ liệu lịch sử) được tự động luân chuyển sang các ổ cứng HDD/SATA dung lượng lớn, giá rẻ để tối ưu chi phí hạ tầng

4.2. Bộ Dữ liệu Giả lập

Dữ liệu thực nghiệm được sinh ra bằng các script PL/pgSQL sử dụng hàm generate_series() để đảm bảo tốc độ sinh nhanh và khả năng tái lập (reproducibility). Bộ dữ liệu được thiết kế để mô phỏng một hệ thống Thương mại điện tử (E-commerce) với đặc thù giao dịch cao, bao gồm hai nhóm chính:

A. Nhóm Dữ liệu Nghiệp vụ

Đây là các bảng nguồn chịu tác động của các lệnh INSERT/UPDATE/DELETE trong kịch bản kiểm thử.

Bảng Orders (Đại diện cho dữ liệu CÓ cấu trúc)

Số lượng: 1.000.000 bản ghi.

Mục đích: Dùng để Stress Test hiệu năng ghi log (TPS) vì đây là bảng có tần suất thay đổi trạng thái cao nhất.

Chi tiết cấu trúc:

id (BIGSERIAL): Khóa chính.

customer_id (INT): Random từ 1 đến 50.000.

total_amount (DECIMAL): Giá trị ngẫu nhiên từ 100.000 đến 100.000.000 VNĐ.

status (TEXT): Phân bố đều giữa các trạng thái PENDING, PAID, SHIPPED, CANCELLED (để mô phỏng việc update trạng thái).

created_at (TIMESTAMP): Rải đều trong 6 tháng gần nhất.

Bảng Products (Đại diện cho dữ liệu BÁN cấu trúc)

Số lượng: 100.000 bản ghi.

Mục đích: Kiểm chứng khả năng của JSONB trong việc lưu trữ các thuộc tính động (Dynamic Attributes) mà không cần sửa đổi bảng Audit.

Chi tiết cấu trúc:

id (SERIAL): Khóa chính.

sku (VARCHAR): Mã sản phẩm duy nhất.

tech_specs (JSONB): Chứa thông số kỹ thuật đa dạng.

Mẫu dữ liệu JSON giả lập:

Loại 1 (Laptop): {"cpu": "Core i9", "ram": "32GB", "screen": "15 inch"}

Loại 2 (Áo thun): {"color": "Blue", "size": "L", "material": "Cotton"}

NOTE: Bảng Audit phải lưu trữ được cả hai cấu trúc JSON hoàn toàn khác nhau này vào cùng một cột new_data.

B. Nhóm Dữ liệu Audit

Đây là bảng đích, nơi chứa dữ liệu lịch sử để kiểm thử khả năng lưu trữ và Partitioning.

Cấu trúc bảng audit_logs

Tổng dung lượng giả lập: ~10.000.000 dòng log (Tương đương kích thước khoảng 5GB - 8GB bao gồm Index).

Chiến lược Partitioning: Phân mảnh theo thời gian (RANGE Partitioning) dựa trên cột changed_at.

Phân bố dữ liệu:

Partition Lịch sử: 5 Partition tương ứng với 5 tháng trước đó (Ví dụ: T8/2025 - T12/2025). Mỗi Partition chứa khoảng 1.5 triệu dòng. Dữ liệu này ở trạng thái "nguội" (Cold Data).

Partition Hiện tại (Active): 1 Partition cho tháng hiện tại (T1/2026). Đây là nơi hứng chịu các thao tác ghi (Write) từ bài test hiệu năng.

Đặc điểm nội dung Log

Cột old_data và new_data trong bảng Audit sẽ chứa toàn bộ snapshot của dòng dữ liệu để đảm bảo tính độc lập.

Kích thước trung bình mỗi dòng log: ~500 bytes - 1KB.

Index: Tạo chỉ mục GIN (Generalized Inverted Index) trên cột new_data để phục vụ kịch bản tìm kiếm sâu trong JSON (Ví dụ: Tìm tất cả log của user đã mua Laptop Core i9).

C. Phương pháp sinh dữ liệu

Thay vì nhập tay, dữ liệu được sinh tự động bằng Stored Procedure để đảm bảo tính ngẫu nhiên và khách quan.

Dưới đây là ví dụ mã giả (Pseudo-code) bằng SQL sử dụng hàm generate_series() trong PostgreSQL để sinh ngẫu nhiên 1.000.000 bản ghi cho bảng orders, mô phỏng dữ liệu trong 6 tháng gần nhất:

-- Ví dụ mã giả (Pseudo-code) sinh dữ liệu Order (1.000.000 bản ghi)

INSERT INTO orders (

    customer_id, 

    total_amount, 

    status, 

    created_at

) 

SELECT 

    floor(random() * 50000 + 1)::int, -- customer_id ngẫu nhiên (từ 1 đến 50.000)

    (random() * 10000000 + 100000)::decimal(10,2), -- total_amount ngẫu nhiên (từ 100.000 đến 10.100.000)

    (ARRAY['PENDING', 'PAID', 'SHIPPED', 'CANCELLED'])[floor(random()*4+1)], -- status ngẫu nhiên

    NOW() - (random() * (INTERVAL '180 days')) -- created_at rải đều trong 6 tháng (180 ngày)

FROM 

    generate_series(1, 1000000); -- Sinh 1.000.000 dòng

4.3. Các Kịch bản Thực nghiệm

Quá trình đánh giá được chia thành 3 kịch bản chính tương ứng với 3 nội dung nghiên cứu:

Kịch bản 1: Đánh giá Hiệu năng Xử lý

Mục tiêu: Chứng minh giải pháp tối ưu hóa thuật toán ghi log, đảm bảo độ trễ thấp và không gây tắc nghẽn (Blocking I/O).

Phương pháp: Sử dụng pgbench giả lập 50 kết nối đồng thời (concurrent connections), thực hiện liên tục lệnh UPDATE trên bảng Orders trong 60 giây.

Các trường hợp đo đạc:

Trường hợp A (Baseline): Không gắn Trigger Audit.

Trường hợp B (Proposed): Có gắn Dynamic Trigger (Ghi log vào bảng Partition JSONB).

Chỉ số đánh giá:

TPS (Transactions Per Second): So sánh sự sụt giảm TPS giữa A và B.

Average Latency (ms): Đo độ trễ trung bình tăng thêm (Overhead). Kỳ vọng < 15%.

Kịch bản 2: Đánh giá Mô hình Lưu trữ

Mục tiêu: Chứng minh tính linh hoạt của JSONB và hiệu quả quản lý của Partitioning.

Thử nghiệm JSONB:

Thực hiện thay đổi dữ liệu trên cả hai bảng Orders và Products.

Kết quả mong đợi: Cùng một Trigger và bảng Audit duy nhất có thể lưu trữ chính xác cấu trúc dữ liệu khác nhau của hai bảng này.

Thử nghiệm Partitioning (Quản lý vòng đời dữ liệu):

Thực hiện xóa dữ liệu log cũ (Data Retention) của 1 tháng (khoảng 1 triệu dòng).

So sánh thời gian thực thi giữa lệnh DELETE tiêu chuẩn và lệnh DROP PARTITION.

Kết quả mong đợi: DROP PARTITION diễn ra tức thì (< 1 giây), không gây khóa bảng (Table Locking) lâu như DELETE.

Kịch bản 3: Đánh giá An toàn & Bảo mật (Security & Integrity)

Mục tiêu: Kiểm chứng cơ chế Security Definer và tính chất Bất biến (Immutability).

Thiết lập: Tạo 2 user mẫu: app_user (quyền hạn chế) và db_admin (quyền cao).

Thử nghiệm 1 (Ủy quyền - Security Definer):

app_user thực hiện cập nhật đơn hàng -> Hệ thống ghi log thành công (nhờ cơ chế ủy quyền).

app_user cố tình truy vấn (SELECT) bảng Audit -> Hệ thống từ chối (Access Denied).

Thử nghiệm 2 (Chống chối bỏ - Immutability):

 Hành động: db_admin thực hiện lệnh DELETE hoặc UPDATE trực tiếp lên bảng Audit để cố gắng xóa hoặc sửa dấu vết. 
 Kết quả mong đợi: 
1. Trigger bảo vệ được kích hoạt, ngay lập tức trả về lỗi ngoại lệ (Exception), ngăn chặn hoàn toàn hành vi xóa/sửa.
2. Đồng thời, Trigger sẽ tự động bắt sự kiện vi phạm này và ghi nhận log vào một bảng cảnh báo độc lập (ví dụ: security_alerts). Bảng này có thể được các hệ thống giám sát bên ngoài (SIEM/Monitoring) quét để phát ra cảnh báo (Alert) tới Ban Giám đốc hoặc Trưởng phòng An ninh thông tin về việc "Có dấu hiệu tài khoản Admin cố tình can thiệp Audit Log".

Kịch bản 4: Đánh giá Hiệu năng Truy vấn (Read/Query Performance)
* Mục tiêu: Chứng minh khả năng tra cứu nhanh chóng dữ liệu lịch sử thông qua GIN Index trên cấu trúc JSONB, giải quyết thách thức khi cần điều tra sự cố. * Phương pháp: Thực hiện các câu lệnh SELECT truy xuất sâu vào các key của JSON (Ví dụ: new_data->>'cpu' = 'Core i9') trên bảng audit_logs có chứa khoảng 1.5 triệu bản ghi (mô phỏng 1 Partition).
•	Các trường hợp đo đạc:
o	Trường hợp A: Truy vấn Full Table Scan (Không sử dụng Index). * Trường hợp B: Truy vấn có sử dụng GIN Index trên cột new_data.
•	Chỉ số đánh giá: Thời gian thực thi truy vấn (Execution Time).
•	Kết quả mong đợi: GIN Index giúp giảm thời gian truy vấn từ mức hàng chục giây (Full Table Scan) xuống mức mili-giây (ms), đảm bảo hệ thống Audit vừa ghi nhanh vừa dễ dàng tra cứu.


4.4. Ma trận tổng hợp

Ma trận này giúp trực quan hóa mối liên hệ giữa các mục tiêu nghiên cứu và kịch bản kiểm thử:

Nội dung thực hiện

Kịch bản thực nghiệm

Kết quả đầu ra dự kiến

Lưu trữ: JSONB cho đa dạng cấu trúc

Kịch bản 2 (Audit Orders & Products)

Log lưu trữ thành công cấu trúc khác nhau vào 1 bảng.

Lưu trữ: Partitioning tối ưu quản lý

Kịch bản 2 (Drop Partition)

Thời gian giải phóng dữ liệu cực nhanh so với DELETE.

Xử lý: Hiệu năng cao, độ trễ thấp

Kịch bản 1 (Stress test pgbench)

Báo cáo TPS và độ trễ (Latency) ở mức chấp nhận được.

An toàn: Security Definer (Ủy quyền)

Kịch bản 3 (User quyền thấp)

User ghi được log nhưng không xem được log.

An toàn: Immutability (Chống xóa)

Kịch bản 3 (Admin can thiệp)

Hệ thống báo lỗi, dữ liệu log được bảo toàn.
Xử lý: Tra cứu dữ liệu bán cấu trúc (JSONB Indexing)
Kịch bản 4 (Query Performance)
GIN Index mang lại tốc độ tra cứu lịch sử cực nhanh (tính bằng ms) so với việc quét toàn bô bảng.

An toàn: Cảnh báo bảo mật chủ động (Alerting)
Kịch bản 3 (Admin can thiệp)
Hệ thống không chỉ ngăn chặn hành vi xóa log mà còn tự động sinh bản ghi cảnh báo (Alert).


5. Benchmark

- Chạy 5 lần, lấy trung bình
- Warm-up 10s
- Đo TPS, Latency, Disk usage

6. Data lifecycle

- Retention: 6 tháng
- Drop partition
- Archive sang storage ngoài (S3/HDD)

7. Security nâng cao

Tamper-evident logging:
hash_n = hash(log_n + hash_n-1)

8. Giới hạn

- Môi trường WSL2 không phản ánh production
- Disk I/O hạn chế

9. Kết luận

Hệ thống đảm bảo:
- Hiệu năng cao
- Linh hoạt
- Bảo mật mạnh


