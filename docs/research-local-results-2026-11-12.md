# Kết quả session local (2026-11-12)

Nhãn: [ĐO] [SUY LUẬN] [CHƯA KIỂM CHỨNG]. Model session: claude-sonnet-5-5 (gói Team).

## Việc 1. Hạn mức gói và cache đọc

Mốc 0 (get_usage, lúc 5-hour limit còn 56 phút trước khi reset):

[ĐO] 5-hour limit 8% (resetsAt 2026-11-12T03:00:00.916Z); Weekly all models 29%; Weekly Fable 0%; extraUsage tắt.
[ĐO] Context session: 85.788 / 1.000.000 token (9%), Messages 31.918, System tools 23.442, MCP tools 11.040, System prompt 9.537, Skills 8.323, Memory 1.528.
[ĐO] get_usage không có dòng Prompt cache (main), không phải /usage của terminal.
[SUY LUẬN] Context đã trên mốc 50k yêu cầu nên không nạp thêm; mỗi tin "ok" sẽ đọc cache khoảng 86k token.
[SUY LUẬN] Phần trăm làm tròn 1%; 25 tin x 86k = khoảng 2,2M token đọc cache có thể không đủ phân giải. Cửa sổ 5 giờ có thể reset ở 03:00Z, lẫn vào mốc 1 nếu đo trễ.

Mốc 1 (get_usage, 02:04:38Z, sau khi nhận đủ 25 tin "ok"):

[ĐO] 5-hour limit 8% (resetsIn 55m); Weekly all models 29%; Weekly Fable 0%; extraUsage tắt. Giống hệt mốc 0.
[ĐO] Context 91.130 token (mốc 0: 85.788); Messages 37.260.
[ĐO] Tin đến theo từng lô (1, 2, 3 riêng; 4 đến 12; 13 đến 20; 21 đến 25), nên số lượt gọi API thực tế có thể ít hơn 25. Mỗi lượt đọc cache khoảng 86k đến 91k token.
[SUY LUẬN] Phần trăm gói không đổi sau khoảng 25 lượt x ~90k, tức tối đa khoảng 2M token đọc cache, mà không nhúc nhích 1%. Phù hợp với giả thuyết cache đọc ít hoặc không tính vào hạn mức, nhưng độ phân giải 1% chưa loại trừ được phần đóng góp nhỏ. Không kết luận chắc.
[CHƯA KIỂM CHỨNG] Chưa có dòng Prompt cache (main) của /usage terminal; chưa đo bằng cách đo lặp ở khối lượng lớn hơn.

## Việc 2. Jitter cron thật

[ĐO] 2026-11-12 02:05Z (09:05 giờ máy, UTC+7) CronCreate job df5e91b9 với cron "7 * * * *". Công cụ báo lần chạy đầu 09:33 giờ máy, tức trễ 26 phút so với giờ danh nghĩa 09:07 (độ lệch cố định theo job, tối đa 50% chu kỳ, trần 30 phút theo mô tả công cụ).
[CHƯA KIỂM CHỨNG] Giờ chạy thật của các lần sau; chưa biết có chạy khi máy sleep. Job chỉ chạy khi REPL rảnh và chết khi session thoát (tự hết hạn sau 7 ngày). Mỗi lần chạy ghi vào docs/research-data/cron-jitter.log. Trạng thái: đang chờ, cần ít nhất 3 lần chạy (khoảng 3 giờ).
[SUY LUẬN] Jitter trần 30 phút làm chu kỳ danh nghĩa 50 phút có thể thành tối đa ~80 phút giữa hai lần chạy liền nhau nếu độ lệch cố định đổi; nhưng độ lệch là cố định theo job nên khoảng cách giữa hai lần chạy liên tiếp vẫn xấp xỉ chu kỳ. Cần dữ liệu thật để xác nhận.

[ĐO] Bổ sung việc 1, từ `node tools/usage-report.js --json` trên transcript của chính session này (02:03Z đến 02:24Z): 29 lượt gọi API, cache_read 2.896.991, cache_write 76.454, input 74, output 9.468, model claude-sonnet-5-5, không có cold restart. Hai mốc get_usage nằm trong khoảng này, nên phần đọc cache giữa hai mốc là một phần của 2,9M (khoảng 25 lượt, mỗi lượt ~90k) mà hạn mức 5 giờ vẫn 8% và hạn mức tuần vẫn 29%.
[SUY LUẬN] 2,9M token đọc cache cho 0 điểm phần trăm. Nếu cache đọc tính theo giá đầy đủ, mức này gần chắc đã làm nhích ít nhất 1%; kết quả nghiêng về cache đọc tính nhẹ hoặc không tính. Chưa đủ để nói chắc vì không biết trọng số của gói Team và làm tròn 1%.

## Việc 3. Giữ cache sống trên desktop

[CHƯA KIỂM CHỨNG] Chưa chạy được trong khuôn khổ session này: cần ít nhất một lần đánh thức cách lần gọi trước khoảng 50 phút, trong khi session đang idle. Công cụ sẵn có (CronCreate) chỉ chạy khi REPL rảnh và có jitter đến 30 phút (xem việc 2), nên chu kỳ 50 phút danh nghĩa có thể vượt 60 phút.
[ĐO] Công cụ kiểm có chạy: `tools/usage-report.js` đọc được transcript desktop (cột segments có idle_before_minutes, cold_restarts đếm lần ghi lại cache sau khoảng nghỉ trên 60 phút). Hiện: 1 segment, 0 cold restart.
Kế hoạch: sau mỗi lần cron df5e91b9 (hàng giờ, phút :07 danh nghĩa) chạy, chạy lại `node tools/usage-report.js --json <transcript>` và đọc segments, cold_restarts; lượt gọi ngay sau lần đánh thức có cache_write nhỏ (dưới vài nghìn) nghĩa là cache còn ấm. Chưa có số.

## Việc 4. A/B Context Mode

[ĐO] Phát hiện: `C:\Users\Lenovo\pbeval\cm-ab.sh` KHÔNG tồn tại (brief nói có). Tôi chạy đúng lệnh trong handoff mục 3.4, không có file phụ: `CM_PLUGIN=C:/Users/Lenovo/pbeval/context-mode/plugins/claude-code K=3 BUDGET=3.5 OUT_DIR=C:/Users/Lenovo/pbeval/cm-ab-out bash docs/research-data/context-mode-ab/run-ab.sh` (PATH có py3shim). Không bị bộ phân loại chặn. Log: C:/Users/Lenovo/pbeval/cm-ab.log; dữ liệu: docs/research-data/context-mode-ab-result/.
[ĐO] Chi phí: 2,106 USD cost_usd (trần 5 USD, mặc định 3,5). 6 lượt chạy (3 baseline, 3 cm, xen kẽ), hai task.
[ĐO] "Plugin loaded" = 3 ở nhánh cm trên cả hai task, 0 ở baseline (đúng).
[ĐO] ctx tool calls (total) = 0 ở nhánh cm: plugin nạp được nhưng model không gọi công cụ ctx nào. Các chuỗi ctx_* trong transcript chỉ nằm trong danh sách công cụ và thông báo SessionStart.
[ĐO] `baseline iteration 2` kết thúc exit 1 nhưng summary báo Errors = 0 (summary vẫn tính đủ 3 lượt baseline); chưa điều tra nguyên nhân.

summary.md (nguyên văn):

| Task | Arm | Runs graded | Errors | Passed all hidden tests | Median cost USD | Median seconds | Median input-side tokens | Median cache write | Median turns | Plugin loaded (runs) | ctx tool calls (total) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| project-01-order-flow | baseline | 3 | 0 | 2/3 | 0.215 | 67 | 233529 | 28159 | 11.0 | 0 | 0 |
| project-01-order-flow | context-mode | 3 | 0 | 3/3 | 0.227 | 83 | 350559 | 17793 | 25.0 | 3 | 0 |
| project-02-tax-exempt | baseline | 3 | 0 | 3/3 | 0.126 | 47 | 445782 | 8883 | 19.0 | 0 | 0 |
| project-02-tax-exempt | context-mode | 3 | 0 | 3/3 | 0.115 | 42 | 302513 | 8141 | 16.0 | 3 | 0 |

[SUY LUẬN] Khác biệt chi phí (0,215 so 0,227; 0,126 so 0,115) nằm trong nhiễu với k=3; vì model không dùng công cụ ctx, nhánh cm chủ yếu đo ảnh hưởng của việc nạp plugin (thêm mô tả công cụ vào context), không phải lợi ích của Context Mode. Không kết luận Context Mode có lợi hay hại. Task nhỏ (file dưới 16 KB), không đại diện cho phiên TDD thật.
[ĐO] Tác dụng phụ: plugin tạo C:/Users/Lenovo/.context-mode (chỉ mục SQLite của các lần chạy thử). Tôi chưa xóa; người dùng tự quyết.

## Việc 5. Probe hook Context Mode

[ĐO] Chạy `docs/research-data/context-mode-hook-probe.sh` như viết: 5/5 ca trả rỗng, kể cả ca lẽ ra bị chặn. Nguyên nhân (suy ra từ thử lại): trên Git Bash đường dẫn `/tmp/...` không phải đường dẫn Windows mà node hiểu, nên hook không thấy file. [SUY LUẬN] Script cần cygpath -m cho đường dẫn trong payload trên Windows (sửa script: chưa làm).
[ĐO] Chạy lại với đường dẫn Windows (payload giả, không gọi API), Node v24.20.0:
- Read cả file 40.000 B: deny, "context-mode: 40000-byte file, over the one-read limit. Run ...ctx_execute(language, code, file=...) and print only the answer."
- Read có limit 50: cho qua (rỗng).
- Bash `cat big.md`: cho qua (rỗng), khác README.
- Bash `git status`: cho qua.
- Bash `git checkout abc -- db/schema.sql`: cho qua.
[ĐO] Trong phiên thật (6 lượt cm của việc 4): không thấy lần deny nào của hook; các is_error trong transcript là lỗi quyền Bash (xuất hiện cả ở baseline), không phải deny của context-mode. Task có file nhỏ nên không có ca Read trên 16 KB; chưa có bằng chứng về "đường vòng" của tester/reviewer với file lớn.
[CHƯA KIỂM CHỨNG] Hành vi trong phiên TDD thật có tester/reviewer đọc file lớn; hook PostToolUse/UserPromptSubmit.

## Việc 6. billion-context

Bỏ qua: chưa có khóa tạm có hạn mức nhỏ từ người dùng.

## Việc 7. Danh sách thay đổi playbook v0.36 (SUY LUẬN, chưa duyệt)

Từ kết quả việc 1 đến 5 và các file nghiên cứu trước đó:
1. [SUY LUẬN] Thêm tài liệu về cache/TTL (bucket 1 giờ, mỗi lần đọc làm mới, gấp chu kỳ giữ sống 54 phút; một phiên mỗi nhánh), kèm giới hạn: chưa chứng minh trên desktop Windows (việc 3 chưa đo).
2. [SUY LUẬN] Khuyến nghị không đổi model giữa session và cảnh báo idle quá 1 giờ gây cold restart (14% đến 40% lượng ghi).
3. [SUY LUẬN] Ghi chú giữ sống phải nêu jitter cron: lần chạy đầu của job hàng giờ bị đẩy 26 phút (việc 2), nên chu kỳ 50 phút không bảo đảm dưới 60 phút. Chưa có đủ 3 lần đo.
4. [SUY LUẬN] Không nói cache đọc "miễn phí" với hạn mức gói: chỉ có một điểm đo (2,9M cache_read, 0 điểm phần trăm, độ phân giải 1%).
5. [SUY LUẬN] Sửa công cụ eval: runner phân biệt ERROR với FAIL (baseline iteration 2 exit 1 mà summary báo 0 lỗi), bộ phân loại đọc cả báo cáo.
6. [SUY LUẬN] Sửa `context-mode-hook-probe.sh` để chạy trên Windows (cygpath -m); ghi chú `cat` không bị chặn và hook chỉ chặn Read cả file trên 16 KB.
7. [SUY LUẬN] Context Mode: chưa đưa vào playbook. A/B hiện chỉ cho biết plugin nạp được và chi phí chung không đổi đáng kể, model không gọi công cụ ctx trên task nhỏ. Cần task có file lớn trước khi kết luận.
8. [SUY LUẬN] Chỉ ghi tài liệu về phạm vi review và `/code-review`. Chưa nên: P1', ép Lite, tầng kế hoạch, định tuyến model, loop engineering.
9. Mỗi bản phát hành cần gate khoảng 150 lần chạy trả tiền (theo `CHANGELOG.md`); cần người dùng đặt trần riêng.

## Việc 2, cập nhật sau 3 lần đo

[ĐO] Nguồn: docs/research-data/cron-jitter.log. Job df5e91b9, cron "7 * * * *", giờ máy +0700.
- nominal 09:07, thật 09:33:21 (trễ 26 phút 21 giây)
- nominal 10:07, thật 10:33:17 (trễ 26 phút 17 giây)
- nominal 11:07, thật 11:33:17 (trễ 26 phút 17 giây)
Khoảng cách giữa các lần chạy: 59 phút 56 giây và 60 phút 00 giây.
[ĐO] Trong 3 lần đo, session không idle lâu và máy không sleep (không có khoảng trống), nên chưa trả lời được "có chạy khi máy sleep không".
[SUY LUẬN] Độ lệch cố định theo job (khoảng 26 phút), nên khoảng cách giữa hai lần chạy liên tiếp vẫn bằng chu kỳ danh nghĩa. Với chu kỳ 50 phút, khoảng cách thật sẽ gần 50 phút, không vượt TTL 1 giờ. Chỉ dựa trên 3 điểm của một job; "*/50" chưa được đo, và cron chỉ chạy khi REPL rảnh.
[CHƯA KIỂM CHỨNG] Hành vi khi máy sleep hoặc session đang bận lâu.

## Việc 4b. A/B Context Mode, task có output lớn (project-05-tax-exempt-noisy)

[ĐO] Lệnh: `TASKS=project-05-tax-exempt-noisy CM_PLUGIN=C:/Users/Lenovo/pbeval/context-mode/plugins/claude-code K=3 BUDGET=2.5 OUT_DIR=C:/Users/Lenovo/pbeval/cm-ab-out2 bash docs/research-data/context-mode-ab/run-ab.sh` (nhánh đã fast-forward tới c92a5a1). Không bị chặn. Chi phí 0,882 USD; tổng hai đợt 2,988 USD (trần 5). Dữ liệu: docs/research-data/context-mode-ab-result-noisy/.

| Task | Arm | Graded | Errors | Passed all hidden | Median cost USD | Median s | Median input-side tok | Median cache write | Median tool-result KB | Median turns | Plugin loaded | ctx tool calls |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| project-05-tax-exempt-noisy | baseline | 3 | 0 | 3/3 | 0.161 | 45 | 405677 | 21740 | 6.6 | 17.0 | 0 | 0 |
| project-05-tax-exempt-noisy | context-mode | 3 | 0 | 1/3 | 0.085 | 50 | 369542 | 6223 | 7.4 | 13.0 | 3 | 0 |

[ĐO] Plugin nạp ở cả 3 lượt cm, nhưng ctx tool calls = 0 lần nữa: model vẫn không dùng công cụ ctx. Tool-result KB hai nhánh gần nhau (6,6 so với 7,4), nên plugin không làm giảm output công cụ vào context ở đợt này.
[ĐO] Nhánh cm chỉ qua 1/3 bài ẩn. Lượt cm-2 trượt FAIL_TO_PASS tests/invoice-exempt.f2p.test.js; diff của cm-2 và cm-3 không sửa src/invoice.js, còn cm-1 (qua) có sửa invoice.js. Baseline 3/3.
[SUY LUẬN] Chi phí thấp hơn của nhánh cm (0,085 so 0,161) đi cùng việc bỏ sót invoice.js, nên có thể là làm ít hơn chứ không phải tiết kiệm thật. Chưa chứng minh plugin gây ra việc bỏ sót: k=3, một nhánh trượt 2 lần, baseline 3/3 là khác biệt có thể do nhiễu. Không đủ cơ sở kết luận Context Mode có lợi hoặc hại.
[CHƯA KIỂM CHỨNG] Cơ chế (vì sao cm bỏ sót invoice.js); cần lặp với k lớn hơn.
