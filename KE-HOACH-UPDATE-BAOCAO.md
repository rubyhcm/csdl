# KẾ HOẠCH UPDATE THƯ MỤC `baocao/` CHO ĐỀ TÀI AUDIT LOG POSTGRESQL

**Đề tài mới:** *Nghiên cứu và xây dựng hệ thống Audit Log hiệu năng cao trên PostgreSQL sử dụng Partitioning và JSONB*
**Sinh viên thực hiện:** Nguyễn Đăng Phúc Lợi — phucloi.dev@gmail.com
**Ngày lập kế hoạch:** 02/05/2026
**Phạm vi:** Thay toàn bộ nội dung Federated Learning trong `baocao/` bằng nội dung PostgreSQL Audit Log từ `6-baocao.md` + sơ đồ trong `sodo-baocao.md` + code thực tế trong `sql/`, `bench/`, `verify/`, `scripts/`.

---

## 0. Khoảng cách hiện tại (Gap Analysis)

| Hạng mục | Hiện trạng `baocao/` | Yêu cầu mới |
|---|---|---|
| Tên đề tài | "Tìm hiểu các thuật toán tổng hợp trọng số trong Federated Learning" | "Nghiên cứu và xây dựng hệ thống Audit Log hiệu năng cao trên PostgreSQL …" |
| Tác giả | 3 thành viên (Cường/Minh/Lợi — nhóm FL) | 1 sinh viên (Nguyễn Đăng Phúc Lợi) |
| Môn học | "Cơ sở dữ liệu nâng cao" | Giữ nguyên (đề tài thuộc đúng môn) |
| Cấu trúc chương | 5 chương (FL-flavored) | 5 chương (Audit Log-flavored) — mapping ở §2 |
| Bibliography | 18 entry FL/ML | ~10 entry PostgreSQL/Audit + giữ ISO 27002 nếu liên quan |
| Acronyms | ML/AI/FL | DML/DDL/DBMS/JSONB/WORM/GIN/SHA/TPS/CDC/SIEM/PoC/SOX/PCI-DSS |
| Hình ảnh | 19 ảnh FL (FedAvg, FedProto, …) | 0 ảnh; cần render từ 6 sơ đồ Mermaid + biểu đồ từ `bench/results/` |
| Quy ước môn | Báo cáo đồ án — giữ class `template/thesis` | Giữ nguyên |

---

## 1. Nguyên tắc chung & Quyết định kỹ thuật

1. **Giữ nguyên `template/thesis.cls`** và toàn bộ layout (geometry/font/biblio engine). Không thay class — chỉ thay nội dung.
2. **Single-author**: cập nhật `\Author{...}{...}` thành 1 dòng duy nhất "Nguyễn Đăng Phúc Lợi — MSHV/MSSV"; xóa `team_info.tex` (hoặc đơn giản hóa thành thông tin 1 người, bỏ ảnh vì chưa có).
3. **Render Mermaid → PNG/PDF**: dùng `mermaid-cli` (`npm i -g @mermaid-js/mermaid-cli`) để xuất 6 sơ đồ trong `sodo-baocao.md` ra `baocao/img/*.pdf`. Lý do chọn PDF thay vì PNG: vector, không vỡ khi zoom trong báo cáo.
4. **Biểu đồ benchmark (kịch bản 1 — scaling curve)**: vẽ bằng TikZ/pgfplots trực tiếp trong .tex để tận dụng dữ liệu số (3 mức concurrency × 3 runs) — chính xác hơn xychart-beta của Mermaid và đẹp hơn khi in.
5. **Code SQL**: dùng môi trường `lstlisting` hoặc `minted` (cần shell-escape) — đề xuất `lstlisting` với style PL/pgSQL custom để tránh dependency Python/Pygments.
6. **Bảng**: convert từ Markdown table sang `tabular`/`tabularx`. Bảng dài (>1 trang) dùng `longtable`.
7. **Sơ đồ ER và Sequence**: ưu tiên Mermaid render PDF; nếu cần edit chi tiết — fallback sang TikZ. Bảng so sánh nhiều cột (KS1 raw data) dùng `tabularx`.
8. **Ngôn ngữ**: tiếng Việt, giữ thuật ngữ tiếng Anh kèm (giống `6-baocao.md`).
9. **Bibliography**: `bibliography.bib` viết lại từ đầu — 8 reference từ §"TÀI LIỆU THAM KHẢO" của `6-baocao.md` + bổ sung vài tài liệu PostgreSQL/audit kinh điển nếu cần.

---

## 2. Mapping nội dung `6-baocao.md` → file `.tex`

| File `.tex` (giữ nguyên tên) | Nội dung gốc trong `6-baocao.md` | Ghi chú quan trọng |
|---|---|---|
| `chapters/abstract.tex` | §"Tóm tắt (Abstract)" (dòng 8–16) | Thay hoàn toàn nội dung FL bằng abstract Audit Log; giữ format `\chapter*{Tóm tắt}` + Từ khóa |
| `chapters/team_info.tex` | (không có) | Đơn giản hóa thành 1 sinh viên (bỏ ảnh `member1.jpg`); hoặc xóa file và bỏ `\input{chapters/team_info}` ra khỏi `main.tex` |
| `chapters/1-MoDau.tex` | §"MỞ ĐẦU" (dòng 20–98): Mô tả bài toán, đặt vấn đề, mục tiêu, nội dung 3 trụ cột, RQ1–3, kết quả đạt được, đối tượng/phạm vi, đóng góp C1–C5, bố cục báo cáo | Thay toàn bộ nội dung FL hiện tại; cấu trúc section: Lý do chọn đề tài → Bài toán → Mục tiêu → RQ → Đóng góp → Bố cục |
| `chapters/2-CoSoLyThuyet.tex` | §"CHƯƠNG 1. TỔNG QUAN VÀ CƠ SỞ LÝ THUYẾT" (dòng 101–188): khái niệm Audit Trail, các giải pháp WAL/pgAudit/CDC/Trigger, bảng so sánh, công trình liên quan §1.5, lý do chọn PostgreSQL §1.6 | Bao gồm cả Bảng 1.1 so sánh giải pháp; tham chiếu Atkins 2012, pgAudit, Debezium, Logical Decoding |
| `chapters/PPDeXuat.tex` | §"CHƯƠNG 2. PHƯƠNG PHÁP ĐỀ XUẤT VÀ THIẾT KẾ HỆ THỐNG" (dòng 191–329): kiến trúc tổng quan, schema design (audit_logs, audit_ddl_logs), JSONB + index, partitioning theo thời gian, Bảng 2.1 trade-offs | Chèn **Sơ đồ 1** (kiến trúc tổng quan), **Sơ đồ 3** (ER diagram); chuyển code DDL audit_logs/audit_ddl_logs thành lstlisting |
| `chapters/3-PhuongPhapThucHien.tex` | Hợp nhất §"CHƯƠNG 3. TRIỂN KHAI…" (dòng 332–533) **VÀ** §"CHƯƠNG 4. AN TOÀN, BẢO MẬT…" (dòng 536–717) | **Lý do gộp**: chương "Phương pháp thực hiện" trong template phù hợp chứa cả triển khai cơ chế ghi log + cơ chế bảo mật (cùng tầng implementation). Section: §3.1 Generic trigger function, §3.2 Dynamic triggers, §3.3 Tối ưu write path, §3.4 Vòng đời partition, §3.5 Truy vấn audit, §3.6 DDL audit, §3.7 Phân quyền + SECURITY DEFINER, §3.8 WORM + dblink, §3.9 Hash chain SHA-256, §3.10 Tối ưu truy vấn, §3.11 Alerting. Chèn **Sơ đồ 2** (WORM + dblink), **Sơ đồ 4** (partition lifecycle), **Sơ đồ 6** (3-layer security) |
| `chapters/4-ThucNghiemDanhGia.tex` | §"CHƯƠNG 5. THỰC NGHIỆM, KIỂM THỬ VÀ ĐÁNH GIÁ" (dòng 720–1154) + §"Câu hỏi và trả lời báo cáo giữa kỳ" (dòng 1182–1210) | Section: §4.1 Môi trường, §4.2 Bộ dữ liệu, §4.3 Metrics, §4.4 KS1 stress test (kèm 3 biểu đồ TikZ scaling curve), §4.5 KS2 storage, §4.6 KS3 security, §4.7 KS4 GIN, §4.8 KS5 DDL, §4.9 Edge cases, §4.10 Tổng hợp, §4.11 Bình luận, §4.12 Q&A báo cáo giữa kỳ (5 câu) |
| `chapters/5-KetLuanPhatTrien.tex` | §"KẾT LUẬN VÀ HƯỚNG PHÁT TRIỂN" (dòng 1157–1179) | Trả lời 3 RQ + 4 hướng phát triển; format giống current chapter |
| `chapters/appendix.tex` | §"PHỤ LỤC A–D" (dòng 1232–1328) | Phụ lục A: DDL các bảng; B: Code PL/pgSQL (link đến `sql/`); C: Script benchmark (link `bench/`, `verify/`); D: Truy vấn mẫu kiểm toán (5 query D1–D5) |
| `bibliography.bib` | §"TÀI LIỆU THAM KHẢO" (dòng 1214–1230) | Viết lại 8 entry: PostgreSQL docs (4), ISO 27002, pgAudit, Debezium, FIPS 180-4 SHA |
| `abbrev.tex` | (mới) | Định nghĩa: DML, DDL, DBMS, JSONB, GIN, WORM, SHA, TPS, CDC, SIEM, PoC, SOX, PCI-DSS, OLTP, WAL, HA, SLA |
| `main.tex` | (cập nhật metadata) | Thay `\Title`, `\Title[en]`, `\Author`, hyperref pdfauthor/pdftitle; điều chỉnh `\chapter{...}` đầu mỗi `\input` cho khớp |

---

## 3. Cập nhật `main.tex` (chi tiết)

Patch vào `baocao/main.tex`:

```latex
\Title{Nghiên cứu và xây dựng hệ thống Audit Log hiệu năng cao trên PostgreSQL sử dụng Partitioning và JSONB}
\Title[en]{Research and Implementation of a High-Performance Audit Log System on PostgreSQL using Partitioning and JSONB}

\Author{Nguyễn Đăng Phúc Lợi}{250202012}    % bỏ 2 \Author cũ

\Degree{MÔN: CƠ SỞ DỮ LIỆU NÂNG CAO}
\ThesisYear{2026}
\Supervisor{TS. Nguyễn Gia Tuấn Anh}   % giữ nguyên nếu cùng giảng viên

\hypersetup{
    pdfauthor={Nguyen Dinh Loi},
    pdfsubject={PostgreSQL Audit Log; JSONB; Partitioning; WORM},
    pdftitle={Audit Log Hieu Nang Cao tren PostgreSQL},
    pdfkeywords={PostgreSQL, JSONB, Partitioning, Audit Log, WORM, SHA-256}
}
```

Tiêu đề `\chapter{...}` cập nhật để khớp (5 chương + appendix):
- `\chapter{Mở đầu}`
- `\chapter{Tổng quan và cơ sở lý thuyết}`
- `\chapter{Phương pháp đề xuất và thiết kế hệ thống}`
- `\chapter{Triển khai cơ chế ghi log, vòng đời và bảo mật}`
- `\chapter{Thực nghiệm, kiểm thử và đánh giá}`
- `\chapter{Kết luận và hướng phát triển}`

---

## 4. Hình ảnh cần tạo / dọn dẹp

### 4.1 Xóa khỏi `baocao/img/`
Không xóa khỏi disk ngay (giữ backup), nhưng **không tham chiếu** trong `.tex` mới:
- `ANN.pdf`, `complexity.png`, `fedavg_workflow.png`, `fedawa_mechanism.png`, `fedcil_architecture.jpg`, `fedlws_mechanism.png`, `fednolowe_process.png`, `fedproto_framework.png`, `fedsecl_workflow.png`
- `cifar10_*.png`, `mnist_*.png`, `model_upload_size.png`, `total_upload_per_round.png`, `trainingTime.png`
- `member1.jpg`, `member2.jpg`, `member3.jpg` (vì còn 1 sinh viên — tùy quyết định có chèn ảnh đại diện hay không)
- `logouit.png` — **GIỮ** (logo trường, dùng ở trang bìa)

### 4.2 Sinh mới (từ `sodo-baocao.md`)
Render 6 sơ đồ Mermaid → `baocao/img/*.pdf`:

| ID | Tên file output | Vị trí chèn | Nguồn |
|---|---|---|---|
| 1 | `arch_overview.pdf` | Chương 2 §2.1 | sodo §2.1 (graph TD trong 6-baocao.md dòng 197–248) |
| 2 | `seq_audit_write.pdf` | Chương 3 §3.1 | sodo §1 sequenceDiagram |
| 3 | `seq_worm_dblink.pdf` | Chương 3 §3.8 | sodo §2 sequenceDiagram |
| 4 | `er_diagram.pdf` | Chương 2 §2.2 | sodo §3 erDiagram |
| 5 | `partition_lifecycle.pdf` | Chương 3 §3.4 | sodo §4 stateDiagram-v2 |
| 6 | `security_3layer.pdf` | Chương 3 §3.7 | sodo §6 flowchart TB |

Lệnh render:
```bash
cd baocao/img
mmdc -i ../../sodo-baocao.md -o arch_overview.pdf -t default -b transparent
# hoặc tách từng diagram ra file .mmd riêng nếu mmdc không split tự động
```

### 4.3 Vẽ bằng TikZ/pgfplots (3 biểu đồ KS1)
Không dùng Mermaid xychart-beta vì xuất ảnh bitmap kém chất lượng; chèn TikZ trực tiếp trong `4-ThucNghiemDanhGia.tex`:
- **Biểu đồ A — Scaling curve TPS**: 2 line (Baseline 33.71/34.06/33.90, Proposed 32.02/36.03/35.40) × 3 mức concurrency
- **Biểu đồ B — Overhead %**: bar chart (+5.0, −5.8, −4.4)
- **Biểu đồ C — Latency scaling (Little's Law)**: 2 line (Baseline 297.1/1468.4/2361.9, Proposed 313.0/1387.9/2260.5)

Source data có sẵn trong §5.5.1 của `6-baocao.md`.

---

## 5. Cập nhật `bibliography.bib`

Xóa toàn bộ entry FL hiện tại. Thêm 8 entry từ §"TÀI LIỆU THAM KHẢO":

```bibtex
@manual{PG16Partitioning,
  title  = {PostgreSQL 16 Documentation --- Table Partitioning},
  author = {{PostgreSQL Global Development Group}},
  year   = {2024},
  url    = {https://www.postgresql.org/docs/16/ddl-partitioning.html}
}
@manual{PG16JSONB,
  title  = {PostgreSQL 16 Documentation --- JSON Types (JSONB)},
  author = {{PostgreSQL Global Development Group}},
  year   = {2024},
  url    = {https://www.postgresql.org/docs/16/datatype-json.html}
}
@manual{PG16GIN, ... }
@manual{PG16Triggers, ... }
@manual{ISO27002,
  title  = {ISO/IEC 27002:2022 --- Information Security Controls},
  author = {{International Organization for Standardization}},
  year   = {2022},
  address = {Geneva}
}
@misc{pgAudit, author = {Machado, D. G.}, title = {pgAudit: PostgreSQL Audit Extension}, year = {2024}, howpublished = {GitHub} }
@misc{Debezium, author = {{Debezium Authors}}, title = {Debezium PostgreSQL Connector}, year = {2024} }
@techreport{FIPS180-4, title = {FIPS PUB 180-4: Secure Hash Standard}, institution = {NIST}, year = {2015}, address = {Gaithersburg, MD} }
```

Bổ sung tùy chọn: `@misc{Atkins2012,...}` cho audit-trigger Wikimedia (đã trích trong §1.5.1 — nên có entry).

---

## 6. Quy ước Listing cho code SQL/PL/pgSQL

Chèn vào preamble `main.tex` (ngay sau `\usepackage{float}`):

```latex
\usepackage{listings}
\usepackage{xcolor}
\definecolor{kw}{RGB}{0,90,156}
\definecolor{cmt}{RGB}{0,128,0}
\definecolor{str}{RGB}{180,40,40}
\lstdefinelanguage{plpgsql}{
  morekeywords={CREATE,FUNCTION,TRIGGER,RETURNS,DECLARE,BEGIN,END,IF,THEN,
    ELSIF,ELSE,RETURN,LANGUAGE,SECURITY,DEFINER,SET,search_path,
    PARTITION,BY,RANGE,PRIMARY,KEY,SELECT,FROM,WHERE,INSERT,INTO,
    VALUES,UPDATE,DELETE,EVENT,FOR,EACH,ROW,BEFORE,AFTER,ON,EXECUTE,
    OR,REPLACE,JSONB,BIGSERIAL,TEXT,TIMESTAMP,BYTEA,DEFAULT},
  morecomment=[l]{--},
  morecomment=[s]{/*}{*/},
  morestring=[b]',
  sensitive=false
}
\lstset{
  language=plpgsql,
  basicstyle=\ttfamily\footnotesize,
  keywordstyle=\color{kw}\bfseries,
  commentstyle=\color{cmt}\itshape,
  stringstyle=\color{str},
  frame=single, tabsize=2, breaklines=true,
  numbers=left, numberstyle=\tiny\color{gray}
}
```

Sử dụng: `\begin{lstlisting}[caption={...},label=lst:...]...\end{lstlisting}`.

---

## 7. Thứ tự thực hiện (Execution Order)

> Mỗi bước nên commit riêng để dễ rollback.

### Phase 1 — Khung & metadata (1–2 giờ)
1. Backup nhánh hiện tại: `git checkout -b backup/fl-template`, `git checkout main`.
2. Cập nhật `main.tex`: title, author, year, hyperref, listings preamble.
3. Đơn giản hóa `team_info.tex` (1 sinh viên, không ảnh) hoặc xóa và bỏ `\input` ra.
4. Cập nhật `abbrev.tex` thêm acronym mới (giữ ML/AI/FL nếu vẫn dùng — kiểm tra; thực tế đề tài mới không dùng → có thể xóa hết và viết lại).
5. Build thử: `cd baocao && latexmk -pdf main.tex` — phải compile sạch trước khi sang Phase 2.

### Phase 2 — Bibliography & assets (2–3 giờ)
6. Viết lại `bibliography.bib` với 8–10 entry mới.
7. Cài `mermaid-cli`: `npm i -g @mermaid-js/mermaid-cli`.
8. Trích từng diagram trong `sodo-baocao.md` ra file `.mmd` riêng → render ra `baocao/img/*.pdf` (6 file).
9. Build thử lại; verify pdf hình.

### Phase 3 — Nội dung chương (8–12 giờ)
10. `abstract.tex` — viết lại (dùng dòng 8–16 của `6-baocao.md`).
11. `1-MoDau.tex` — chuyển ngữ §"MỞ ĐẦU" sang LaTeX; tạo 5 section: Mô tả bài toán → Đặt vấn đề → Mục tiêu/RQ → Đóng góp → Bố cục.
12. `2-CoSoLyThuyet.tex` — chuyển ngữ §"CHƯƠNG 1"; lưu ý Bảng 1.1 (so sánh giải pháp) dùng `tabularx`.
13. `PPDeXuat.tex` — chuyển ngữ §"CHƯƠNG 2"; chèn Sơ đồ 1, 3 + lstlisting DDL audit_logs/audit_ddl_logs; Bảng 2.1 trade-offs.
14. `3-PhuongPhapThucHien.tex` — gộp §"CHƯƠNG 3" + §"CHƯƠNG 4"; chèn Sơ đồ 2, 4, 6; tất cả code lstlisting (`func_audit_trigger`, `func_prevent_audit_change`, `func_audit_hash_chain`, `func_audit_ddl`).
15. `4-ThucNghiemDanhGia.tex` — chuyển ngữ §"CHƯƠNG 5" + 5 Q&A; vẽ 3 biểu đồ TikZ scaling curve; mọi bảng (5.1–5.8) dùng `tabularx`.
16. `5-KetLuanPhatTrien.tex` — chuyển ngữ §"KẾT LUẬN…"; format trả lời RQ1–3 + 4 hướng phát triển.
17. `appendix.tex` — chuyển 4 phụ lục A–D; uncomment `\appendix` block trong `main.tex`.

### Phase 4 — Đánh bóng (2–3 giờ)
18. Build full + đọc lại; sửa lỗi: cross-reference (`\ref`, `\cite`), số bảng/hình/listing không đúng thứ tự, overflow box.
19. Kiểm tra TOC/LoF/LoT/biblio in đúng tên đề tài.
20. Spell-check tiếng Việt (vimspell/aspell-vi nếu có).
21. So khớp lần cuối với `6-baocao.md` để đảm bảo không thiếu section quan trọng nào.
22. Commit cuối + tag `v1.0-baocao-audit-log`.

**Tổng thời gian ước tính:** ~13–20 giờ làm việc tập trung.

---

## 8. Checklist hoàn thành

> **Trạng thái review (2026-05-03):** Implementation hoàn tất. Các mục ✅ đã verify qua đọc file thực tế. Các lỗi tìm thấy đã được fix trực tiếp.

- [x] `main.tex` compile sạch, PDF có metadata đúng (title/author)
- [x] Trang bìa hiển thị đúng tên đề tài + 1 sinh viên — `\Author{Nguyễn Đăng Phúc Lợi}{250202012}` (cần điền MSHV thực)
- [x] `abstract.tex` chứa abstract Audit Log + từ khóa (dùng `\ac{}` cho OLTP, TPS)
- [x] `1-MoDau.tex` đủ 6 section: Lý do chọn → Bài toán → Mục tiêu → RQ → Đóng góp → Bố cục (**đã fix**: bố cục phản ánh đúng 5 chương thực tế)
- [x] 6 sơ đồ Mermaid render thành **PNG** (không phải PDF như plan đề xuất) tại `img/mermaid/` và chèn đúng vị trí
- [x] 3 biểu đồ TikZ scaling curve render chính xác số liệu KS1 (pgfplots trong `4-ThucNghiemDanhGia.tex`)
- [x] 4 hàm PL/pgSQL có listing: `func_audit_trigger`, `func_audit_ddl`, hash chain snippet, `func_prevent_audit_change` (**đã thêm** listing WORM vào `3-PhuongPhapThucHien.tex`)
- [x] Bảng chuyển sang `tabularx`: Tab.1.1 so sánh giải pháp, Tab.2.1 trade-offs, Tab.5.1–5.8 thực nghiệm
- [x] 5 Q&A báo cáo giữa kỳ có trong `4-ThucNghiemDanhGia.tex` (section cuối)
- [x] Phụ lục A–D xuất hiện sau bibliography (uncommented trong `main.tex`)
- [x] Bibliography 9 entry PostgreSQL/Audit, không còn entry FL
- [x] Không còn ảnh FL nào được tham chiếu trong `.tex`
- [ ] PDF cuối ≤ 60 trang — chưa verify (cần build và đếm trang)
- [ ] `<MSHV>` placeholder cần điền MSHV thực của sinh viên

### Lỗi đã fix trong review (2026-05-03)

| Vấn đề | File | Hành động |
|---|---|---|
| `func_prevent_audit_change()` code bị thiếu | `3-PhuongPhapThucHien.tex` §Immutability | Thêm listing đầy đủ (31 dòng) |
| Typo "Immutzability" | `3-PhuongPhapThucHien.tex` dòng 220 | Sửa thành "Immutability" |
| KS4 GIN data sai (32 ms vs 285 ms — fabricated) | `4-ThucNghiemDanhGia.tex` §KS4 | Thay bằng số thực (930 ms warm vs 1.032 ms no-GIN) + thêm cold cache (2.898 ms) |
| RQ2 answer "7× đến 10×" mâu thuẫn dữ liệu thực | `5-KetLuanPhatTrien.tex` | Sửa thành "~10% warm cache; >10× khi selectivity cao" |
| Bố cục mô tả Ch4 "An toàn/Bảo mật" là chương riêng (đã gộp vào Ch3) | `1-MoDau.tex` | Cập nhật bố cục 5 chương khớp với `main.tex` thực tế |

---

## 9. Rủi ro & phương án dự phòng

| Rủi ro | Mức độ | Mitigation |
|---|---|---|
| `mermaid-cli` không cài được (Node version, Chromium dependency) | Trung bình | Fallback: render online qua https://mermaid.live → "Download SVG" → `inkscape --export-pdf` |
| TikZ scaling curve vẽ phức tạp, mất thời gian | Thấp | Dùng `pgfplots` package + dữ liệu inline; có sample script trong PostgreSQL community |
| `lstlisting` xử lý ký tự `$$` của PL/pgSQL không đẹp | Trung bình | Dùng `escapechar=|` hoặc bọc trong `verbatim`; hoặc chuyển sang `minted` với `-shell-escape` |
| Compile lỗi do encoding tiếng Việt khi copy từ `.md` | Thấp | Đảm bảo file `.tex` lưu UTF-8 không BOM; class hiện đã có `utf8` |
| 60 trang vượt quá giới hạn báo cáo môn | Trung bình | Cô đọng §1.5 (công trình liên quan), bỏ lặp giữa §3.x và §4.x; gộp một số bảng nhỏ |
| Không có MSHV của tác giả | Thấp | Hỏi sinh viên để điền `\Author{Nguyễn Đăng Phúc Lợi}{250202012}` |

---

## 10. Tài liệu tham chiếu trong dự án

- `6-baocao.md` — nội dung gốc (1329 dòng)
- `sodo-baocao.md` — 6 sơ đồ Mermaid (276 dòng)
- `sql/` — 11 file SQL từ schema đến cleanup
- `bench/` — script pgbench + scaling
- `verify/` — 6 script kiểm thử (security, GIN, partition, hash, DDL, JSONB)
- `scripts/manage_partitions.sh` — script quản lý partition
- `docs/results-summary.md` — tóm tắt kết quả thực nghiệm
- `baocao/template/thesis.cls` — class LaTeX (UIT Thesis Template v2.0.0)

---

**Ghi chú cuối:** Sau khi hoàn thành theo plan này, `baocao/` sẽ là báo cáo Audit Log hoàn chỉnh, sẵn sàng nộp môn ATBM HTTT. Mọi nội dung kỹ thuật bám sát code thực tế trong dự án (`sql/`, `bench/`, `verify/`) — đảm bảo tính tái lập của báo cáo.
