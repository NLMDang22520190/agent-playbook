# Bổ sung handoff nghiên cứu (2026-11-09)

Bổ sung cho `docs/research-handoff.md` trên nhánh `claude/serene-galileo-4sr31t` (chưa merge vào `main`). File này chỉ chứa những gì
phát hiện thêm hoặc sửa sau khi tính lại. Không chứa quyết định áp dụng. Nhãn giữ như handoff: **[ĐO]**, **[SUY LUẬN]**, **[CHƯA KIỂM CHỨNG]**.

## 1. Sửa số liệu trong handoff (tính lại từ `docs/research-data/runs.tsv`)

Đã khớp: 57 dòng, tổng chi phí 20,89 USD (trần 22), R5 (E5), E4, khoảng tin cậy R6 và R7 [ĐO].

Cần sửa [ĐO]:

1. Trung vị với số lần chạy chẵn trong handoff lấy số giữa trên thay vì trung bình hai số giữa.
   - Nhóm "agent tự chọn (A)" project-01 ở R7 gồm E6 và E8-A, 6 lần: chi phí trung vị đúng **0,73 USD** (handoff ghi 0,79), thời gian **226 s** (ghi 241).
   - Lite project-01: **0,295 USD** và **90 s** (ghi 0,31 và 95).
   - Lite giảm chi phí khoảng 60% theo trung vị đúng (0,295 so với 0,733), vẫn vượt tiêu chí giảm 30% đã đặt trước. Kết luận về chất lượng không đổi: chưa chứng minh được không kém hơn.
2. Bảng "theo số lần gọi Agent" ở R7 gộp biến thể A và B (14 lần). Chỉ tính A (11 lần):

   | Số lần gọi Agent | Lần chạy | Chi phí trung vị | Qua hết |
   |---|---|---|---|
   | 0 | 3 | 0,30 USD | 0/3 |
   | 1 đến 3 | 5 | 0,79 USD | 1/5 |
   | Từ 4 | 3 | 1,28 USD | 1/3 |

## 2. Prompt cache, TTL và compact (nguồn: tài liệu chính thức, đọc 2026-11-09)

Tài liệu được đọc qua công cụ đọc web có bước tóm tắt. Hệ số giá nên kiểm lại ở trang pricing trước khi dùng để quyết định.

[ĐO từ tài liệu]
- Cache làm mới miễn phí mỗi lần dùng; thời gian sống tính từ đầu request. TTL 5 phút mặc định, 1 giờ ghi 2x giá input, 5 phút ghi 1,25x, đọc 0,1x. Với Opus 5.5 và Sonnet 5.5 tài liệu ghi đọc 0,05x.
- Claude Code chỉ yêu cầu TTL 1 giờ cho hội thoại chính trên gói subscription, trong hạn mức gói. API key, usage credits, cloud provider: 5 phút. Sub-agent, compaction, workflow, teammate: luôn 5 phút trừ khi đặt `subagentPromptCacheTtl`. Đặt TTL hội thoại chính bằng `promptCacheTtl` hoặc `CLAUDE_CODE_PROMPT_CACHE_TTL` (v2.1.242 trở lên).
- Mỗi model có cache riêng, đổi model là đọc lại toàn bộ không có cache (khớp lần ghi 93.896 và đọc 0 sau `/model` ở R2).
- `/compact` là một request riêng đọc prefix từ cache nếu còn ấm; nếu cache đã chết, nó xử lý lại toàn bộ context như input chưa cache. Compact làm mất cache tầng hội thoại, tầng system và project vẫn dùng lại được.
- `idleCompaction` (v2.1.290 trở lên, mặc định bật): khi hội thoại ở TTL 1 giờ, idle khoảng 1 giờ, máy còn thức, context từ 200k token (đặt được thấp nhất 100k bằng `CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS`), tự compact trước khi cache hết hạn. Chạy trong terminal tương tác, VS Code, hoặc app desktop chạy trên máy người dùng.
- `/loop` và tác vụ định kỳ trong session: chỉ chạy khi Claude Code mở và idle; hết hạn sau 7 ngày; `/loop 5m` được dời để không vượt TTL 5 phút; tác vụ mỗi giờ trễ ngẫu nhiên tới 30 phút (jitter); chu kỳ như 50 phút bị làm tròn vì cron không biểu diễn sạch.
- `/usage` có dòng `Prompt cache (main)` (v2.1.251 trở lên) cho biết TTL đang dùng và ấm hay lạnh.

[ĐO từ chính người dùng, 2026-11-09]
- Báo cáo `/usage` của app desktop: Opus 5.5, 14,7M đọc cache, 459,4k ghi cache, 234 input không cache, tức khoảng 97% input từ cache. Hai dòng `Cost $1466.42` và `Wall 3m` mâu thuẫn (API 2981m), không dùng.
- `claude -p "hello"` trên Opus 5.5: tóm tắt của agent ghi khoảng 21k token ghi vào cache 1 giờ và 17k token đọc từ cache, 0,173 USD. Chưa có JSON `usage.cache_creation` thô; TTL 1 giờ là dấu hiệu mạnh nhưng chưa xác nhận hẳn.

Phép tính giữ sống [SUY LUẬN từ hệ số giá, chưa kiểm]: một lần đánh thức giữ cache tốn khoảng 0,05 đến 0,1 C·P (C là context, P giá input), một lần cold restart tốn khoảng 2 C·P (ghi 1 giờ), gấp 20 đến 40 lần. Hòa vốn ở khoảng 16 giờ (hệ số 0,1x) đến 32 giờ (0,05x) idle với chu kỳ 50 phút. Giữ sống làm `idleCompaction` không kích hoạt.

[CHƯA KIỂM CHỨNG]
- Đơn vị tính trên gói subscription là hạn mức gói; chưa tìm thấy tài liệu nói lần đọc cache được tính vào hạn mức ra sao.
- Với session cloud, chưa xác nhận việc đánh thức có giữ container sống hay không.
- Vòng tự chọn nhịp (dynamic `/loop`, `ScheduleWakeup` với trễ không quá 3000 giây) có tránh được jitter kiểu cron hay không.

Thí nghiệm TTL đã chạy sau khi người dùng cho phép (ngân sách khoảng 0,5 USD, trong 1,1 USD còn lại của trần 22). Dữ liệu thô: .

[ĐO] , Sonnet 5.5, container này, cache 1 giờ (JSON thô: 0 token ở bucket 5 phút):

| Lần | Giờ (Z) | Cách lần trước | Đọc cache | Ghi mới | Chi phí |
|---|---|---|---|---|---|
| B0 | 07:27 | phiên mới | 27.692 | 7.493 | 0,033 USD |
| B1 | 08:21:47 | 54 phút | 28.279 | 6.945 | 0,063 USD |
| B2 | 09:15:54 | 54 phút | 35.200 | 63 | 0,067 USD |

Đối chứng (phiên C, idle 2h02m): đọc 0, ghi lại 35.218 token.

[SUY LUẬN có cơ sở từ số đo] B2 đọc gần như toàn bộ context, gồm phần 28k token ghi từ 108 phút trước. Phần đó chỉ sống được vì B1 đã đọc nó ở phút 54, nên mỗi lần đọc làm mới TTL và chu kỳ 54 phút giữ sống được. Đối chứng C cho thấy prefix dùng chung không tự sống nhờ session khác.

Giới hạn: một phiên mỗi nhánh; chỉ cho  trong container, Sonnet 5.5; chưa chứng minh cho app desktop Windows hay session cloud. B1 ghi lại khoảng 7k token thay vì đọc, chưa giải thích được. Lần thử đầu bị hỏng vì tiến trình nền bị harness dọn (A1, C1, A2 không chạy), đã chạy lại bằng chuỗi B và đối chứng C.

## 3. Lệnh `/code-review` (nguồn: tài liệu Claude Code)

[ĐO từ tài liệu]
- Không có đối số: các commit của nhánh vượt upstream cộng thay đổi chưa commit; không có upstream thì so với `main`.
- Một commit: `/code-review abc1234^..abc1234`. Commit cuối: `/code-review HEAD~1..HEAD`.
- Chạy như sub-agent nền có context riêng, chỉ báo cáo; không có vòng lặp nội bộ hay luật dừng. `--fix` sửa, `--comment` đăng lên PR, `--max-findings <n>`.
- Effort `low` chỉ báo phát hiện tự tin nhất; từ `medium` mở rộng độ phủ. Tuân theo `CLAUDE.md`, không đọc `REVIEW.md`.

Vòng review hai agent: luật trong repo (`skills/playbook-tdd/references/release.md`) giới hạn 2 vòng mỗi lane hoặc slice; từ vòng 3 chỉ sửa MAJOR do chính thay đổi gây ra và cho thêm một vòng; còn lại vào "Found, not fixed". Lý do trong file ("vòng 3 thường tìm thứ nhỏ hơn") chưa có số đo trong dữ liệu nghiên cứu [SUY LUẬN]. `roles/reviewer.md` đọc `BASE_SHA..HEAD` (toàn bộ thay đổi).

[SUY LUẬN, chưa đo] Review chỉ commit cuối rẻ hơn nhưng có thể bỏ sót tương tác với code cũ và không xác nhận phát hiện vòng trước đã xử lý. Một cách cân bằng: vòng 1 xem toàn bộ thay đổi, các vòng sau xem commit sửa cộng danh sách phát hiện còn mở, vòng cuối xem lại toàn bộ một lần.

## 4. Loop engineering và bài Facebook (nguồn thứ cấp)

[CHƯA KIỂM CHỨNG] Bài đăng của nhóm VGU Tech Alumni, tóm tắt buổi trò chuyện kênh Amigoscode với "Peter" (theo bài là kỹ sư OpenAI, maintain khoảng 40 dự án mã nguồn mở): dùng các phiên tự động kiểm tra dependency, rà Issue và PR theo bộ quy tắc nghiêm ngặt để Agent tự merge; người chỉ quyết định tính năng nào đáng làm. Không có số liệu. Bài không dùng thuật ngữ "loop engineering". Việc "Peter" là Peter Steinberger nhắc ở R8 là [SUY LUẬN]. Facebook không trả thân bài cho khách chưa đăng nhập (chỉ tiêu đề và 200 ký tự); nội dung do người dùng dán.

Claude Code có sẵn `/loop`, tác vụ định kỳ theo session, tác vụ cloud, và `/goal` (tài liệu `scheduled-tasks`); chưa thí nghiệm gì.

## 5. Việc còn lại

Giữ nguyên mục 6 của handoff (10 case). Tình trạng sau session này:

- Gần như miễn phí: case 5 (đo trên session thật), 8 (cần bảng giá do người dùng xác nhận), 10 (sửa runner phân biệt ERROR và FAIL, bộ phân loại đọc đúng báo cáo), 7 (cần nguồn gốc loop engineering).
- Cần người dùng nêu trần mới: case 1, 2, 4, 9 (vài USD trở lên), 3 và 6 (chưa ước tính), thí nghiệm TTL ở mục 2.
- Tồn đọng: nhánh nghiên cứu chưa merge và chưa có PR; PR #83 và #84 đang mở; ba suite `test-guard-restore-r9`, `r12`, `symlink` thất bại trong container; hai host `adtmag.com` và `machinelearningmastery.com` chưa đọc được; ba video Facebook còn lại và bài về người dùng Claude Max chưa được đưa vào.
- Không có quyết định áp dụng nào; P1' vẫn "experimental, not adopted".
