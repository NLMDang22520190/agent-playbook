# Đọc transcript A/B Context Mode, task project-05-tax-exempt-noisy (2026-11-12)

Nhãn: [ĐO] [SUY LUẬN] [CHƯA KIỂM CHỨNG]. Chỉ đọc dữ liệu có sẵn (C:/Users/Lenovo/pbeval/cm-ab-out2/*.runs/*.log), không chạy thêm lượt claude, không tốn tiền (tổng đã chi 2,988 USD trên trần 5).
Script: docs/research-data/cm-transcript-timeline.js. Đoạn trích đã bỏ đường dẫn cá nhân: docs/research-data/cm-ab-transcript-excerpts/.

## Bảng theo lượt

| Lượt | Qua test ẩn | Lần chạy test (số, byte output) | Đọc hoặc sửa src/invoice.js | Grep "tax" trong src sau Grep đầu | Khoảng trống dài nhất |
|---|---|---|---|---|---|
| baseline-1 | có | 4: 762, 59 (lỗi quyền), 134, 134 | Read và Edit | có | 8,0 s |
| baseline-2 | có | 4: 59 (lỗi), 130 (lỗi), 100 (lỗi), 24.418 (npm test đầy đủ) | Read và Edit | có | 4,8 s |
| baseline-3 | có | 3: 763, 59 (lỗi), 134 | Read và Edit | có | 4,9 s |
| cm-1 | có | 3: 873, 59 (lỗi), 134 | Read và Edit | có | 6,0 s |
| cm-2 | KHÔNG (trượt invoice-exempt.f2p) | 4: 140 (lỗi), 1.031 (lỗi), 183, 148 | không | không | 4,5 s |
| cm-3 | KHÔNG | 3: 1.554, 59 (lỗi), 134 | không | không | 261,4 s |

## (a) Vì sao tool-result chỉ 6 đến 7 KB

[ĐO] Agent có chạy `npm test`, nhưng gần như luôn cắt output bằng `| tail -15` hoặc `| grep -E "^ℹ (pass|fail)"`, nên mỗi lần chỉ 59 đến 1.554 B. Chỉ một lần duy nhất (baseline-2) chạy `npm test` đầy đủ: 24.418 B, và đó là lần lớn nhất trong 6 lượt. Không có lần nào gần 65 KB.
[ĐO] Mâu thuẫn với handoff/thiết kế task: "npm test in khoảng 65 KB" không được chứng minh bởi transcript; bằng chứng duy nhất là 24.418 B (có thể output khác trên Windows, hoặc con số 65 KB lấy từ nơi khác; chưa kiểm).
[SUY LUẬN] Task chưa kiểm tra được điều nó muốn kiểm tra (output lớn vào context), vì agent tự cắt output; plugin cũng không có cơ hội can thiệp vì không có Read file trên 16 KB trong lượt nào.

## (b) Vì sao cm-2 và cm-3 bỏ sót src/invoice.js

[ĐO] Điểm rẽ nhánh nằm ở bước 1 và 4. Cả 4 lượt qua (baseline-1..3, cm-1) gọi Grep đầu với `output_mode: files_with_matches` (kết quả 178 B), rồi gọi Grep thứ hai `tax` trong `src/**` (417 B), nên thấy invoice.js và đọc, sửa nó. cm-2 và cm-3 gọi Grep đầu với `output_mode: content` (2.333 B, trả cả dòng khớp), không gọi Grep `tax` thứ hai, nên không bao giờ mở src/invoice.js. Không lượt nào đọc docs/invoicing.md (không lượt nào đọc docs/).
[ĐO] Kết quả Grep đầu của cm-3 có `tests/invoice.test.js` với `inv.vatCents, order.totals.taxCents`, một manh mối về invoice mà agent không theo.
[ĐO] Thông báo plugin trong transcript chỉ là một: SessionStart additionalContext, nguyên văn: "This session may have run before. Call mcp__plugin_context-mode_context-mode__ctx_resume for a summary of what happened." Cả 3 lượt cm đều nhận, không lượt nào gọi ctx_resume hay công cụ ctx nào. Không thấy PreToolUse deny hay UserPromptSubmit trong log (log stream-json chỉ ghi sự kiện SessionStart).
[SUY LUẬN] Thông báo SessionStart không nói gì về grep, về invoice hay về cách tìm file; không có cơ chế thấy được trong transcript khiến agent đổi sang `output_mode: content`. Việc chọn `content` có thể là biến động ngẫu nhiên của model (2 trên 3 lượt cm, 0 trên 4 lượt còn lại). Nhưng 2/3 so với 0/4 cũng không loại được chuyện plugin nạp thêm mô tả công cụ làm lệch lựa chọn; không thể phân biệt bằng dữ liệu này.

## (c) Vì sao cm-3 mất 298 giây

[ĐO] 261,4 s nằm giữa lần Bash bị từ chối quyền (bước 8) và lệnh Write (bước 9), và trong khoảng đó transcript ghi 7 sự kiện `api_retry` với độ trễ tăng dần (564, 595, 1.194, 2.199, 4.901, 8.365, 18.571 ms, lỗi "unknown"). Đây là API gặp lỗi và thử lại, không phải công cụ hay hook chậm.
[SUY LUẬN] Thời gian chờ nằm ở phía API/mạng, không liên quan plugin. Tổng các độ trễ retry trong log chỉ khoảng 36 s, nên phần còn lại của 261 s chưa giải thích được (chưa kiểm chứng; có thể thời gian mỗi lần gọi bị treo trước khi báo lỗi).

## Kết luận

[ĐO] Transcript KHÔNG cho thấy plugin thay đổi hành vi qua bất kỳ công cụ nào: 0 lần gọi ctx_*, một thông báo SessionStart duy nhất bị bỏ qua.
[SUY LUẬN] Nguyên nhân gần nhất của việc bỏ sót là lựa chọn `output_mode: content` ở Grep đầu rồi không grep tiếp, không phải plugin chặn hay đổi nội dung. Giả thuyết "plugin làm agent bỏ sót invoice.js" chưa được ủng hộ trực tiếp bởi transcript; giả thuyết "biến động của agent" khớp hơn nhưng với k=3 (2/3 so với 0/4) cũng chưa chứng minh được.
[CHƯA KIỂM CHỨNG] Có tác động gián tiếp của plugin (mô tả công cụ thêm vào context làm lệch lựa chọn Grep) hay không. Cần k lớn hơn (ít nhất 10 mỗi nhánh) và theo dõi riêng lựa chọn `output_mode`. Cũng chưa so với các lượt project-02 trước (cm 3/3 ở project-01 và project-02): task đó không gây bỏ sót, nên không có tiền lệ.

## Probe hook (việc phụ)

[ĐO] Đã sửa docs/research-data/context-mode-hook-probe.sh: dùng `winp()` (cygpath -m nếu có, nếu không giữ nguyên) cho plugin, HOME, CLAUDE_PROJECT_DIR và payload. Chạy lại một lần, Node v24.20.0, plugin C:/Users/Lenovo/pbeval/context-mode/plugins/claude-code, payload giả, không gọi API:
1. Read cả file 40.000 B: deny ("context-mode: 40000-byte file, over the one-read limit. Run ...ctx_execute(language, code, file=...) and print only the answer.")
2. Read có limit 50: cho qua (rỗng).
3. Bash `cat big.md`: cho qua (rỗng), khác README.
4. Bash `git status`: cho qua.
5. Bash `git checkout abc -- db/schema.sql`: cho qua.
Giống kết quả chạy tay trước đó. Thư mục tạm của script đã xóa. C:/Users/Lenovo/.context-mode chưa xóa, để người dùng quyết.

## Thêm: transcript project-06-long-session (K=1, 2026-11-12)

Đoạn trích đã làm sạch: docs/research-data/cm-ab-transcript-excerpts/project-06-timeline-{baseline-1,cm-1}.txt.

[ĐO] cm-1 trượt `invoice-exempt` và `refunds-report`; baseline qua. Trong cm-1 không có lệnh nào đọc hoặc sửa `src/invoice.js`, và không có lệnh nào đọc hoặc sửa `src/reports.js` (hai file mà test ẩn cần). Baseline sửa `invoice.js` (bước 9) và ghi `reports.js` (bước 18).
[ĐO] Điểm rẽ nhánh nằm ở bước 1: cả hai nhánh mở đầu bằng một lệnh Bash ghép nhằm đọc toàn bộ `src/*.js` và `docs/*.md`. Của baseline (`git ls-files; cat package.json; cat docs/*.md; cat src/*.js; ...`) chạy được và trả 2.294 B, sau đó lệnh thứ 4 cat cả `src/reports.js`, `src/invoice.js`. Của cm-1 (`cd . && git ls-files && cat package.json && cat src/*.js && cat docs/*.md && ...`) bị bộ phân loại quyền Bash từ chối ("contains multiple operations", 194 B lỗi). Sau đó cm-1 chỉ đọc lẻ `pricing.js`, `orders.js`, `order-page.js` và các file docs, không bao giờ cat `src/*.js` nữa, nên không thấy `invoice.js` và `reports.js`.
[SUY LUẬN] Nguyên nhân gần nhất là lệnh khám phá đầu tiên của cm-1 bị từ chối quyền do cách viết ghép (`cd . && ...`), không phải do plugin: nhãn từ chối là "subcommandResults"/quy tắc quyền Bash, và thông báo plugin duy nhất vẫn là SessionStart ctx_resume (198 B). Không thể loại trừ hoàn toàn việc plugin ảnh hưởng đến cách model viết lệnh, nhưng không có bằng chứng.
[ĐO] Dùng `ctx_execute` đúng 1 lần (bước 29, sau khi code xong), để đọc `logs/payments.log` bằng JavaScript; kết quả 461 B. Trong baseline phần việc tương đương (bước 24 đến 26) dùng `node -e` và script Node, kết quả 883 B và 258 B, tức cũng cắt output. Chênh lệch tool-result KB (28,9 so với 12,0) chủ yếu do baseline có hai lần cat file lớn ở bước 1 đến 5 (2.294, 2.372, 2.174, 4.737, 10.511 B), không phải nhờ ctx_execute.
[SUY LUẬN] Hai lần liên tiếp cm trượt `invoice-exempt` đều có cùng cơ chế gần nhất: agent không mở `invoice.js` vì khám phá mã nguồn bị thu hẹp (lần 1 do chọn `output_mode: content` ở Grep, lần 2 do lệnh cat bị từ chối quyền). Cả hai đều là biến động ở bước khám phá, không có chứng cứ về cơ chế từ plugin. Vẫn k=1, chưa đủ để kết luận.
[CHƯA KIỂM CHỨNG] Có hay không việc plugin làm model chọn cách khám phá khác đi; cần k lớn hơn và kiểm soát việc từ chối quyền (ví dụ cho phép `cd` và lệnh ghép giống nhau ở hai nhánh) trước khi so sánh chất lượng.
