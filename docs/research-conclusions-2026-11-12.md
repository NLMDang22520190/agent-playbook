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

## 6. Cập nhật sau các đợt A/B tổng hợp và bước A (2026-11-12, buổi chiều)

Dữ liệu: `docs/research-local-results-2026-11-12.md` (việc 4b đến 4d và bước A), `docs/research-data/context-mode-ab-result-*`, `docs/research-data/addressable-share/`.

**Context Mode: kết luận cuối là không đưa vào playbook.**

1. [ĐO] 11 lượt chạy có plugin và 11 lượt baseline qua 5 đợt (khoảng 4,27 USD): baseline qua 10/11 (2,231 USD, 0,223 USD mỗi lần qua), cm qua 8/11 (2,035 USD, 0,254 USD mỗi lần qua); Fisher một phía p khoảng 0,29 (tính tay), không có ý nghĩa. Số lần gọi `ctx_*` là 0, 0, 0, 1 và 5 theo từng đợt (6 tổng); ở project-07 (pha 1) cm dùng `ctx_execute` 5 lần nhưng tool-result của cm lớn hơn baseline (23,7 so với 17,5 KB), peak context tương đương (52K so với 50K), cost 0,280 so với 0,303 USD (k=1).
2. [ĐO] Peak context của mọi benchmark tổng hợp chỉ 50K đến 59K, trong khi trên hai dự án thật của người dùng 68,4% và 97,9% lượt gọi có context trên 100K. Benchmark tổng hợp không tới được vùng cần đo (project-05, 06, 07; ceiling 15 USD, dừng sau pha 1 theo điều kiện đã đặt).
3. [ĐO] Bước A (`addressable-share.js`, chạy bởi người dùng trên transcript thật, 0 USD). Dự án A: 56.036 lượt gọi, 11,4 tỷ token đầu vào, kết quả công cụ từ 4 KB trở lên chiếm 9,33% các lượt đọc (từ 16 KB: 3,32%), mọi kết quả công cụ 14,6%; cắt 50% đến 95% chỉ tiết kiệm tối đa 4,7% đến 8,9%. Dự án B: 811 lượt gọi, 335 triệu token, 5,81% (từ 16 KB: 2,49%), tối đa 2,9% đến 5,5%. Theo ngưỡng đã đăng ký trước (dưới 10%: dừng) cả hai đều dưới ngưỡng; dự án A sát ngưỡng.
4. [SUY LUẬN] Trần lý thuyết thấp hơn trong thực tế vì model hiếm khi gọi `ctx_*` và việc cắt hoàn hảo bỏ qua chuyện phải hỏi lại. Ước lượng thô độ lớn: theo đơn giá khoảng 0,34 USD mỗi triệu token đầu vào quy đổi (một lượt chạy, project-07), 11,4 tỷ token tương ứng khoảng 3.900 USD quy đổi theo giá API, nên 4,7% đến 8,9% là khoảng 180 đến 350 USD quy đổi trong toàn bộ lịch sử của dự án A; không phải chi phí thực trên gói của người dùng.
5. [CHƯA KIỂM CHỨNG] Hành vi ở context trên 100K trong một A/B (vì benchmark tổng hợp không tới được và bước A cho thấy trần thấp, không đáng chi tiền).

**Tiền:** trần 15 USD cho đánh giá hai công cụ context: đã dùng khoảng 4,27 USD, còn khoảng 10,7 USD chưa dùng. Bước B (so sánh cặp tình huống tốt nhất) không chạy vì bước A dưới ngưỡng.

**billion-context: chưa kết luận, và bước A không áp dụng.** Bước A chỉ đo kết quả công cụ (mục tiêu của Context Mode), chiếm 12% đến 15% các lượt đọc; khoảng 85% còn lại là tiền tố tĩnh và hội thoại. billion-context nén lịch sử hội thoại, nên cận trên của nó cần phép đo riêng. Bước A2 (`docs/research-data/history-share.js`, 0 USD) tính phần chi phí đến từ việc đọc lại lịch sử cũ hơn N lượt gọi và phần cold restart, chỉ từ trường `usage` và timestamp của transcript. Chưa chạy trên dữ liệu của người dùng. Ngưỡng đã đăng ký trước, theo con số chính "tỉ lệ chi phí đọc lại lịch sử cũ hơn 50 lượt gọi": dưới 10% dừng; từ 25% trở lên mới đáng thử có khóa tạm; giữa là vùng xám. Chạy với hai bộ hệ số (`--read-mult 0.1 --write-mult 1.25` mặc định, và `--read-mult 0.05 --write-mult 2`), vì con số thay đổi theo hệ số.
[ĐO] Chạy thử một lần trên một transcript đám mây của chính tác giả (182 lượt, 2 compaction, 158 lượt context trên 100K): con số chính 11,0% với hệ số mặc định và 6,1% với hệ số thứ hai; cold restart chiếm 17,0% đến 30,5% chi phí (6 lần). Không đại diện cho công việc của người dùng, chỉ để kiểm tra script.

**Danh sách ứng viên v0.36 (thay mục 7 ở mục 3):** ghi chú công cụ tùy chọn nên viết là "Context Mode đã thử: trần lý thuyết 4,7% đến 8,9% trên khối lượng công việc thật, không có lợi ích đo được ở A/B, không khuyến nghị; billion-context chưa thử (cần khóa tạm và cô lập), cận trên của nó đang chờ bước A2". Các mục khác giữ nguyên.
