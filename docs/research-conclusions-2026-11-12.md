# Kết luận nghiên cứu sau đợt đo local (2026-11-12) và danh sách ứng viên cho playbook v0.36

Tổng hợp các kết quả của `docs/research-local-results-2026-11-12.md`, `docs/research-cm-transcripts-2026-11-12.md` và `docs/research-context-tools-2026-11-11.md`, sau khi tính lại từ dữ liệu thô.
Nhãn: **[ĐO]** là số đo hoặc đọc trực tiếp từ nguồn; **[SUY LUẬN]** là diễn giải; **[CHƯA KIỂM CHỨNG]** là chưa kiểm.
Không có quyết định áp dụng nào; P1' vẫn "experimental, not adopted". Danh sách ở mục 3 chưa được người dùng duyệt.

## 1. Đính chính

1. **Số "khoảng 65 KB" của task project-05 phụ thuộc phiên bản Node.** [ĐO] Cùng repo, `node --test` ra 64.882 B với Node 22 (định dạng TAP, như container cloud) và 24.983 B với Node 24 (định dạng spec, như máy người dùng). Ước tính ban đầu lấy từ Node 22.
2. **Số lượt chạy có plugin Context Mode là 9, không phải 12.** [ĐO] Đợt một 6 lượt (3 mỗi task), đợt hai 3 lượt. Lần trước báo nhầm 12.
3. **"baseline iteration 2 exit 1 mà báo 0 lỗi" không phải lỗi của runner.** [ĐO] Theo phần mô tả đầu `evals/run-outcome.sh`, exit 1 nghĩa là có ít nhất một lần FAIL (ở đợt một, lượt baseline-2 trượt hai test ẩn của project-01). Runner đã phân biệt ERROR (exit 4) với FAIL đúng. Mục "sửa runner phân biệt ERROR với FAIL" trong danh sách v0.36 của file kết quả local (mục 5) dựa trên chẩn đoán sai và nên bỏ. Chỉ còn việc làm rõ dòng thông báo trong `run-ab.sh` (đã sửa).
4. **Phần "cache đọc có tính vào hạn mức gói không" chưa phân biệt được.** [SUY LUẬN] Một điểm đo: 2,9M token đọc cache, 0 điểm phần trăm, độ phân giải 1%. Cả phiên (đọc, ghi cache và output) quy theo trọng số giá cũng chỉ cỡ 0,4M token quy đổi, chưa biết có chạm 1% hay không. Câu "nghiêng về không tính" trong file local nên đọc là "chưa phân biệt được".

## 2. Kết luận theo câu hỏi

**Giữ cache sống (R9).** [ĐO] Cơ chế hoạt động: mỗi lần đọc làm mới TTL, chu kỳ 54 phút giữ được cache (`claude -p`, container, Sonnet 5.5, một phiên mỗi nhánh). [ĐO] Cron theo session trên máy người dùng có độ lệch cố định theo job (26 phút ở job :07) và khoảng cách giữa hai lần chạy 59 phút 56 giây và 60 phút 00 giây (3 điểm, một job). [SUY LUẬN] Chu kỳ hàng giờ thuần không có biên an toàn vì khoảng cách bằng đúng TTL 1 giờ (tính từ đầu request); cần chu kỳ ngắn hơn 60 phút, ví dụ mỗi 30 phút (hai job lệch nhau hoặc `*/30`), và `*/50` cho khoảng cách 50 rồi 10 phút. Chi phí mỗi giờ khi đó gấp đôi tính toán 50 phút. Cron theo session trong container cloud mất khi session khởi động lại. [CHƯA KIỂM CHỨNG] Giữ sống trên desktop, máy sleep, REPL bận lâu.

**Hạn mức gói và cache đọc.** Chưa phân biệt được (xem mục 1, điểm 4).

**Context Mode** (9 lượt có plugin, khoảng 3 USD cho hai đợt). [ĐO] Plugin nạp được; model không gọi công cụ `ctx_*` lần nào; thông báo duy nhất của plugin là SessionStart ("This session may have run before. Call ...ctx_resume...") và bị bỏ qua; hook từ chối Read cả file trên 16 KB trong payload giả (hai môi trường), còn `cat` không bị chặn trong cả hai (khác README). Ở task có output lớn (project-05, 24 KB khi chạy đầy đủ), agent tự cắt output (`| tail -15`, `| grep`) nên tool-result trung vị chỉ 6,6 KB (baseline) và 7,4 KB (cm); không có Read file trên 16 KB nào. Nhánh cm qua 1/3 so với baseline 3/3; hai lượt trượt không sửa `src/invoice.js` vì dùng `output_mode: content` ở Grep đầu rồi không grep tiếp (2 lượt cm so với 0 trên 5 lượt còn lại, Fisher một phía p khoảng 0,14); lượt cm-3 mất 298 giây do 7 lần `api_retry`. Chi phí trên mỗi lần qua: cm khoảng 0,40 USD (0,399 USD cho 1 lần qua), baseline khoảng 0,16 USD (0,483 USD cho 3 lần qua); chi phí thấp của các lượt trượt chỉ do làm ít việc hơn.
[SUY LUẬN] Không có bằng chứng lợi ích ở task cỡ agent, vì agent không để output lớn lọt vào context và model không dùng công cụ của plugin. Chưa chứng minh được plugin gây ra việc bỏ sót (k=3, có thể là biến động của model; tác động gián tiếp của mô tả công cụ chưa loại trừ; cần k từ 10 mỗi nhánh). Một đợt nữa với task ép output lớn dự kiến vẫn cho 0 lần gọi `ctx_*`, nên dừng đo ở đây (đã chi 2,988 USD trên trần 5).

**billion-context.** [ĐO từ mã nguồn, không chạy] Tự cập nhật từ npm, chế độ MITM cho gói subscription, `DISABLE_AUTO_COMPACT=1`, app desktop có thể bỏ qua proxy. [CHƯA KIỂM CHỨNG] Mọi số đo (cần khóa tạm). [SUY LUẬN] Chưa nên cài trên máy chính.

## 3. Danh sách ứng viên cho v0.36 (SUY LUẬN, chưa duyệt)

Đưa vào, chỉ tài liệu hoặc sửa công cụ, rút lại được:

| # | Mục | Căn cứ |
|---|---|---|
| 1 | Tài liệu cache/TTL: bucket 1 giờ, mỗi lần đọc làm mới TTL, sub-agent và compaction 5 phút trừ khi đặt, mỗi model một cache | R1, R2, R9; kiểm lại hệ số giá ở trang chính thức trước khi viết |
| 2 | Khuyến nghị không đổi model giữa session | R2: sau `/model` ghi lại 93.896 token, đọc 0 (một lần đo) |
| 3 | Khuyến nghị về idle quá 1 giờ: để `idleCompaction` làm việc hoặc viết handoff trước khi nghỉ dài | R1: cold restart 14% đến 40% lượng ghi; handoff khi idle chưa so với `idleCompaction` |
| 4 | Ghi chú giữ sống: cơ chế hoạt động, chu kỳ phải ngắn hơn 60 phút, cron có độ lệch cố định, mất khi session cloud khởi động lại, chi phí hạn mức gói chưa biết | mục 2 |
| 5 | Sửa công cụ eval: bộ phân loại `outcome-classes.js` đọc cả báo cáo chứ không chỉ lượt cuối (mục 5 của handoff gốc) | lỗi đã ghi |
| 6 | Tài liệu phạm vi review và `/code-review` kèm các cờ, không thay reviewer; vòng review 3 lượt và chỉ commit cuối chỉ ghi là gợi ý thử nghiệm | R10, chưa đo |
| 7 | Ghi chú "công cụ tùy chọn": Context Mode đã thử, không có lợi ích đo được ở task cỡ agent, chưa khuyến nghị; billion-context chưa thử, kèm các rủi ro đã nêu | mục 2 |

Bỏ khỏi danh sách trước: mục "sửa runner phân biệt ERROR với FAIL" (runner đã đúng, mục 1 điểm 3).

Chưa nên: P1', ép Lite, tầng kế hoạch, định tuyến model theo role, loop engineering, giữ sống tự động.

## 4. Điều kiện trước khi làm v0.36

- Mỗi bản phát hành cần gate đã commit, khoảng 150 lần chạy trả tiền (theo `CHANGELOG.md`); cần người dùng đặt trần riêng. Chưa đọc luật cụ thể xem thay đổi chỉ gồm tài liệu có phải qua gate không.
- Nhánh nghiên cứu cách `main` nhiều commit, chưa có PR, cần rebase nếu mở PR. PR #83 (v0.35.0) đang mở.
- [ĐO] Sau khi thêm task project-05 và các script, `tests/test-outcome-classes.sh` qua 12/12 và `tests/test-outcome-corpus.sh` qua 917, 0 lỗi, 1 bỏ qua (chạy 2026-11-12 trong container). Ba suite `test-guard-restore-r9`, `r12`, `symlink` vẫn thất bại trong container, chưa điều tra trên máy khác.
- Còn tồn đọng: cách đo hạn mức gói ở khối lượng lớn hơn, giữ sống trên desktop và máy sleep, billion-context (cần khóa tạm), `C:/Users/Lenovo/.context-mode` của người dùng chưa xóa.

## 5. Chi tiêu

Trần cũ 22 USD: khoảng 20,9 USD (runs.tsv) cộng khoảng 0,5 USD (TTL, ngoài runs.tsv). Trần riêng 5 USD cho đánh giá hai công cụ context: đã dùng 2,988 USD (2,106 cộng 0,882, `cost_usd` quy đổi trên gói Team), còn khoảng 2,0 USD. Không chạy thêm nếu chưa có yêu cầu mới.
