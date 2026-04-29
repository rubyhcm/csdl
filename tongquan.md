ĐỀ CƯƠNG NGHIÊN CỨU KHOA HỌC
I. TÊN ĐỀ TÀI
Nghiên cứu và Xây dựng hệ thống Audit Log hiệu năng cao trên PostgreSQL sử dụng Partitioning và JSONB.

________________________________________II. ĐẶT VẤN ĐỀ VÀ MỤC TIÊU NGHIÊN CỨU
2.1. Đặt vấn đề
Giải quyết bài toán lưu vết dữ liệu (Audit Trail) trong các hệ thống thông tin lớn (như Tài chính, Ngân hàng) hiện đang đối mặt với ba thách thức chính:

●	Khối lượng dữ liệu tăng trưởng nhanh (Big Data).

●	Yêu cầu khắt khe về việc không làm chậm hiệu năng hệ thống hiện tại (Latency).

●	Đảm bảo tính toàn vẹn dữ liệu trước sự can thiệp của người quản trị (Data Integrity & Security).

2.2. Mục tiêu nghiên cứu
Đề xuất và xây dựng một kiến trúc cơ sở dữ liệu tối ưu trên PostgreSQL để ghi log tự động, lưu trữ linh hoạt dữ liệu đa cấu trúc, truy xuất tốc độ cao và có cơ chế bảo mật chống chối bỏ, từ đó giải quyết triệt để ba thách thức đã nêu.

________________________________________III. TỔNG QUAN TÀI LIỆU VÀ CÁC GIẢI PHÁP
3.1. Các phương pháp phổ biến hiện nay
Để giải quyết bài toán Audit Trail, hiện nay có một số phương pháp phổ biến:

●	Logical Decoding (Đọc từ WAL - Write-Ahead Logging): Ghi nhận thay đổi ở cấp độ engine cơ sở dữ liệu. Nhược điểm là khó ánh xạ chính xác thông tin người dùng ứng dụng (Application User) thực hiện giao dịch và yêu cầu thiết lập phức tạp.

●	Sử dụng Extension (Ví dụ: pgaudit): Hỗ trợ tốt nhưng ghi log dưới dạng text thô (raw text) vào file log của hệ điều hành, gây khó khăn cho việc truy vấn có cấu trúc, tìm kiếm và phân tích báo cáo sau này.

3.2. Phương pháp đề xuất (Trigger + JSONB + Partitioning)
Phương pháp này vượt trội ở khả năng giải quyết triệt để vấn đề tìm kiếm trên dữ liệu phức tạp nhờ sức mạnh của JSONB và GIN Index, đồng thời duy trì hiệu năng cao cho hệ thống lớn thông qua cơ chế phân mảnh Partitioning.

3.3. So sánh các giải pháp
Tiêu chí	Trigger + JSONB	pgAudit	CDC (Debezium)
Structured Query	Có
	Không
	Hạn chế

Real-time	Không
	Không
	Có

Application Context	Có
	Không
	Không

Độ phức tạp	Trung bình
	Thấp
	Cao

3.4. Giới hạn áp dụng
Giải pháp đề xuất KHÔNG phù hợp với các trường hợp:

●	Hệ thống yêu cầu real-time streaming.

●	Hệ thống có Throughput cực cao (>10k TPS).

●	Kiến trúc microservices đa database.

________________________________________IV. PHƯƠNG PHÁP VÀ NỘI DUNG THỰC HIỆN
4.1. Kiến trúc hệ thống tổng quan
Sơ đồ hệ thống  hoạt động theo luồng:

1.	Ứng dụng (app_user) thực hiện lệnh INSERT/UPDATE/DELETE trên các Business Tables.

2.	AFTER ROW Trigger kích hoạt Generic Audit Function để chuyển dữ liệu vào bảng phân mảnh audit_logs.

3.	Dữ liệu được lưu trữ bằng JSONB, lập chỉ mục GIN, phân mảnh theo thời gian (Time-based Partitioning).

4.	Security Layer chặn các lệnh UPDATE/DELETE, tạo tính chất Append-only và chuyển cảnh báo bảo mật tới hệ thống Monitoring/SIEM.

4.2. Phân tích đánh đổi (Trade-offs)
●	JSONB: Điểm cộng là tính linh hoạt cao ; tuy nhiên gây tốn storage và truy vấn có thể phức tạp.

●	Trigger: Ưu điểm là không cần sửa đổi mã nguồn ứng dụng; đánh đổi lại là làm tăng latency và khó debug.

●	Partitioning: Quản lý vòng đời dữ liệu rất tốt ; nhược điểm là các câu lệnh truy vấn quét chéo (cross-partition) có thể bị chậm.

4.3. Nội dung thực hiện chi tiết
Nội dung nghiên cứu tập trung vào ba trụ cột kỹ thuật:

A. Cơ chế Lưu trữ & Quản lý vòng đời dữ liệu (Data Lifecycle)
●	Sử dụng kiểu dữ liệu JSONB (Binary JSON) để lưu trữ linh hoạt (Schema-less) trạng thái dữ liệu trước và sau khi thay đổi (OLD và NEW values), cho phép một bảng Log duy nhất phục vụ cho toàn bộ hệ thống.

●	Áp dụng kỹ thuật Declarative Partitioning (Phân mảnh theo thời gian) để tối ưu hóa việc quản lý các bảng Log có kích thước lớn, hỗ trợ truy vấn nhanh và lưu trữ phân cấp (Tablespace).

●	Quản lý vòng đời: Đặt mức Retention là 6 tháng. Sau đó sử dụng Drop partition và Archive dữ liệu sang storage ngoài như S3/HDD .

B. Cơ chế Xử lý & Tối ưu hiệu năng
●	Xây dựng các Dynamic Triggers và Generic Functions bằng ngôn ngữ PL/pgSQL để tự động hóa việc bắt các sự kiện INSERT, UPDATE, DELETE mà không cần can thiệp vào mã nguồn ứng dụng.

●	Tối ưu hóa thuật toán ghi log để đảm bảo độ trễ (Overhead) ở mức thấp nhất, không gây tắc nghẽn (Blocking I/O) cho các giao dịch nghiệp vụ chính.

C. Cơ chế An toàn & Bảo mật
●	Triển khai mô hình SECURITY DEFINER trong Stored Procedures để thiết lập cơ chế ủy quyền: Người dùng có thể kích hoạt ghi Log nhưng không có quyền truy cập trực tiếp vào bảng Log.

●	Xây dựng cơ chế Immutability (Bất biến): Sử dụng Trigger chặn chiều DELETE/UPDATE trên bảng Log, biến bảng này thành dạng "Append-Only", đảm bảo ngay cả tài khoản Admin cũng không thể xóa log.

●	Bảo mật nâng cao (Tamper-evident logging): Ứng dụng chuỗi băm để chống giả mạo với công thức hash_n = hash(log_n + hash_n-1) .

________________________________________V. KỊCH BẢN VÀ MÔI TRƯỜNG THỰC NGHIỆM
Quá trình thực nghiệm được tiến hành trên mô hình giả lập với các thông số cụ thể:

5.1. Môi trường thực nghiệm và Benchmark
●	Cấu hình: PostgreSQL 16 (Hỗ trợ tối ưu JSONB và Partitioning) chạy trên Windows 11 qua Ubuntu Server 22.04 LTS (WSL2), sử dụng 4 vCPU, 8GB RAM, ổ cứng 20GB SSD .

●	Phương pháp Benchmark: Dùng công cụ pgbench với kịch bản chạy 5 lần, lấy kết quả trung bình, thời gian warm-up 10s. Đo lường TPS, Latency và mức sử dụng Disk .

●	Khả năng mở rộng (Scalability): Môi trường thử nghiệm đóng vai trò Proof of Concept (PoC). Trên Production, tốc độ ghi log phụ thuộc lớn vào Disk I/O. Kỹ thuật Declarative Partitioning mở ra cơ hội dùng Tablespace: Partition "nóng" đặt trên NVMe/SSD, Partition "nguội" luân chuyển sang HDD/SATA để tối ưu chi phí .

5.2. Bộ dữ liệu giả lập
Dữ liệu sinh tự động bằng script PL/pgSQL (hàm generate_series()).

●	Bảng Orders (Dữ liệu có cấu trúc): 1.000.000 bản ghi, mô phỏng giao dịch mật độ cao để Stress Test (TPS). Bao gồm các trường id, customer_id, total_amount, status, created_at .

●	Bảng Products (Dữ liệu bán cấu trúc): 100.000 bản ghi để kiểm chứng tính linh hoạt của JSONB (VD: chứa thông số Laptop hoặc Áo thun hoàn toàn khác nhau vào cùng cột new_data) .

●	Bảng Audit Logs: Tổng dung lượng giả lập ~10.000.000 dòng log (5GB - 8GB), kích thước trung bình 500 bytes - 1KB/dòng. Partition Lịch sử (5 tháng trước) lưu 1.5 triệu dòng lạnh/Partition; Partition Hiện tại hứng chịu thao tác ghi .

●	Chỉ mục: GIN Index trên cột new_data phục vụ tìm kiếm sâu trong JSON.

5.3. Các kịch bản thực nghiệm
●	Kịch bản 1: Đánh giá Hiệu năng Xử lý. Dùng pgbench giả lập 50 kết nối, UPDATE liên tục bảng Orders trong 60 giây. So sánh Baseline (Không Trigger) và Proposed (Có Trigger) để đo sự sụt giảm TPS và Overhead tăng thêm (Kỳ vọng < 15%) .

●	Kịch bản 2: Đánh giá Mô hình Lưu trữ. Thay đổi dữ liệu Orders và Products để kiểm chứng JSONB có thể lưu cấu trúc khác nhau vào 1 bảng. Xóa log tháng cũ (khoảng 1 triệu dòng) để chứng minh DROP PARTITION diễn ra tức thì (< 1s), không gây Table Locking như lệnh DELETE tiêu chuẩn .

●	Kịch bản 3: Đánh giá An toàn & Bảo mật. Sử dụng user quyền hạn chế (app_user) để cập nhật đơn hàng (ghi log thành công nhờ ủy quyền) nhưng không thể SELECT. Tài khoản db_admin cố xóa/sửa bảng Audit sẽ bị Trigger chặn lại văng lỗi Exception, đồng thời sinh log cảnh báo ra bảng độc lập (security_alerts) để SIEM thu thập .

●	Kịch bản 4: Đánh giá Hiệu năng Truy vấn (Read Performance). Thực hiện câu lệnh SELECT sâu vào JSON key (VD: new_data->>'cpu' = 'Core i9') trên bảng 1.5 triệu dòng. So sánh Full Table Scan và truy vấn có GIN Index. Kỳ vọng thời gian giảm từ hàng chục giây xuống mili-giây .

5.4. Ma trận tổng hợp mục tiêu và kịch bản thực nghiệm
Nội dung thực hiện	Kịch bản thực nghiệm	Kết quả đầu ra dự kiến

Lưu trữ: JSONB cho đa dạng cấu trúc
	Kịch bản 2 (Audit Orders & Products)
	Log lưu trữ thành công cấu trúc khác nhau vào 1 bảng.


Lưu trữ: Partitioning tối ưu quản lý
	Kịch bản 2 (Drop Partition)
	Thời gian giải phóng dữ liệu cực nhanh so với DELETE.


Xử lý: Hiệu năng cao, độ trễ thấp
	Kịch bản 1 (Stress test pgbench)
	Báo cáo TPS và độ trễ (Latency) ở mức chấp nhận được.


Xử lý: Tra cứu dữ liệu (JSONB Indexing)
	Kịch bản 4 (Query Performance)
	GIN Index giúp tra cứu lịch sử cực nhanh (tính bằng ms).


An toàn: Security Definer (Ủy quyền)
	Kịch bản 3 (User quyền thấp)
	User ghi được log nhưng không xem được log.


An toàn: Immutability (Chống xóa)
	Kịch bản 3 (Admin can thiệp)
	Hệ thống báo lỗi, dữ liệu log được bảo toàn.


An toàn: Cảnh báo bảo mật (Alerting)
	Kịch bản 3 (Admin can thiệp)
	Ngăn chặn hành vi và tự động sinh bản ghi cảnh báo.

________________________________________VI. KẾT QUẢ DỰ KIẾN VÀ KẾT LUẬN
6.1. Kết quả đầu ra dự kiến
●	Mô hình cơ sở dữ liệu hoàn chỉnh với Partitioning và JSONB Indexing.

●	Bộ Script PL/pgSQL tự động hóa việc Audit cho các bảng nghiệp vụ.

●	Báo cáo thực nghiệm so sánh hiệu năng (TPS) định lượng giữa việc có và không có Audit Log.

●	Kịch bản Demo tấn công giả lập: Chứng minh được hệ thống có khả năng ngăn chặn nỗ lực xóa log của tài khoản đặc quyền.

6.2. Giới hạn của đề tài
●	Môi trường WSL2 giả lập có thể không phản ánh chính xác 100% điều kiện chạy thực tế trên các máy chủ Production vật lý.

●	Nút thắt cổ chai về Disk I/O trên máy tính cá nhân là một hạn chế trong việc đo lường tới hạn của hệ thống.

6.3. Kết luận
Dựa trên kiến trúc và phương pháp thiết kế đã đề xuất, hệ thống kỳ vọng sẽ giải quyết được bài toán khó của các tổ chức quy mô lớn, đảm bảo sự cân bằng giữa hiệu năng cao, tính linh hoạt lưu trữ và chuẩn mực bảo mật mạnh .
