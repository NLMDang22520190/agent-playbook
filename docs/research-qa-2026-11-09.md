# Câu hỏi và kết quả nghiên cứu (2026-11-09 đến 2026-11-11)

Sổ ghi các câu hỏi người dùng đã đặt trong session này và câu trả lời hiện có. Chi tiết và nguồn nằm ở `docs/research-handoff.md` (R7, R9, R10) và
`docs/research-addendum-2026-11-09.md`. Nhãn: **[ĐO]** là số đo hoặc tính lại từ dữ liệu thật; **[SUY LUẬN]** là diễn giải; **[CHƯA KIỂM CHỨNG]** là chưa có bằng chứng đủ.
Không có quyết định áp dụng nào; P1' vẫn "experimental, not adopted".

## Mục tiêu

Chất lượng đầu ra và chi phí; tốc độ không phải yếu tố chính. Bốn câu hỏi gốc: token tiêu vào đâu, tách vai nhiều model so với một model, SDD so với TDD cho playbook, loop engineering có đáng không.

## A. Hỏi về công cụ và nguồn

| Câu hỏi | Trả lời |
|---|---|
| Đọc được bài và video Facebook không? | Không. Facebook không trả thân bài cho khách chưa đăng nhập, chỉ tiêu đề và khoảng 200 ký tự mô tả. Người dùng dán nội dung vào thì đọc được. Video thì không xem được. |
| Bài "Software Engineer năm 2027" nói gì? | **[CHƯA KIỂM CHỨNG]** nguồn thứ cấp, không có số liệu: dùng phiên tự động kiểm tra dependency, rà Issue và PR theo bộ quy tắc để Agent tự merge; người chỉ quyết định tính năng. Không dùng thuật ngữ "loop engineering". Việc "Peter" là Peter Steinberger là **[SUY LUẬN]**. |

## B. Sửa số liệu cũ (tính lại từ `docs/research-data/runs.tsv`)

**[ĐO]** 57 dòng, tổng 20,89 USD (trần 22). Trung vị số chẵn trong handoff cũ lấy số giữa trên thay vì trung bình hai số giữa. Đã sửa: project-01 tự chọn (A) 0,733 USD và 226 s; Lite 0,295 USD và 90 s (Lite giảm chi phí khoảng 60%, nhưng chưa chứng minh được chất lượng không kém hơn). Bảng theo số lần gọi Agent chỉ tính A (11 lần): 0 lần 0,30 USD (0/3 qua hết), 1 đến 3 lần 0,79 USD (1/5), từ 4 lần 1,28 USD (1/3).

## C. Prompt cache, TTL, compact, giữ sống

**C1. Skill đánh thức session mỗi 50 phút để giữ cache có được không, tradeoff là gì?**

- **[ĐO] thí nghiệm TTL** (`claude -p --resume`, Sonnet 5.5, container này, cache 1 giờ, dữ liệu `docs/research-data/ttl-2026-11-09.tsv`): phiên B đánh thức mỗi 54 phút. Lần B2 đọc 35.200 token và chỉ ghi mới 63, dù phần 28k token đầu ghi từ 108 phút trước. Mỗi lần đọc làm mới TTL, nên chu kỳ 54 phút giữ sống được. Đối chứng không giữ sống (idle 2h02m): đọc 0, ghi lại 35.218 token. Mỗi lần giữ sống ở context 35k tốn khoảng 0,03 đến 0,07 USD.
- **[SUY LUẬN từ hệ số giá, chưa kiểm]** một lần giữ sống rẻ hơn cold restart khoảng 20 đến 40 lần; hòa vốn khoảng 16 đến 32 giờ idle. Giữ sống làm `idleCompaction` không kích hoạt.
- **[ĐO] cron trong container cloud:** hai job hàng giờ (CronCreate) đều biến mất trước lần chạy đầu (kiểm sau hơn 15 giờ và hơn 33 giờ), session có vẻ khởi động lại khi idle. **[SUY LUẬN]** cron không giữ cache sống được trong session cloud này; chỉ chắc dùng được khi Claude Code mở trên máy người dùng.
- **Tradeoff theo tài liệu:** cron chỉ chạy khi Claude Code mở và idle; hết hạn sau 7 ngày; job hàng giờ có jitter tới 30 phút (offset cố định theo từng job, có thể vượt TTL 1 giờ); mỗi lần đánh thức gửi lại toàn bộ context.
- **[CHƯA KIỂM CHỨNG]** cache đọc được tính vào hạn mức gói subscription thế nào; jitter thật của `/loop` và cron; giữ sống trên app desktop Windows và session cloud; vì sao B1 ghi lại khoảng 7k token thay vì đọc.
- Giới hạn: một phiên mỗi nhánh, chỉ `claude -p` trong container, Sonnet 5.5.

**C2. Thay vào đó, tự sinh handoff cho session mới khi idle 55 phút thì sao?** Chưa thí nghiệm. **[SUY LUẬN]** tránh được chi phí giữ sống nhưng mất một phần ngữ cảnh và buộc người dùng copy sang session mới; có thể rẻ hơn khi idle rất lâu. Cần so với `idleCompaction` (tự compact khoảng 1 giờ idle, context từ 200k token) trước khi tự viết.

**C3. Tài liệu nói gì về TTL?** **[ĐO từ tài liệu]** TTL 5 phút mặc định, 1 giờ ghi 2x giá input; đọc 0,1x (Opus 5.5 và Sonnet 5.5: 0,05x, cần kiểm lại ở trang pricing). Claude Code chỉ yêu cầu 1 giờ cho hội thoại chính trên gói subscription; API key, usage credits, cloud: 5 phút; sub-agent và compaction: 5 phút trừ khi đặt. Mỗi model có cache riêng. `/compact` rẻ khi cache ấm, đắt khi chết.

**C4. Số liệu từ máy người dùng.** **[ĐO]** báo cáo `/usage` desktop (Opus 5.5): 14,7M đọc cache, 459,4k ghi cache, 234 input không cache, khoảng 97% input từ cache. Hai dòng `Cost` và `Wall` mâu thuẫn nên không dùng. `claude -p "hello"` trên Opus 5.5: khoảng 21k ghi vào cache 1 giờ, 0,173 USD.

## D. `/code-review` và vòng review hai agent

**D1. Review chỉ diff của commit gần nhất, giới hạn 3 vòng thì sao?** **[ĐO từ tài liệu]** `/code-review` không có vòng lặp nội bộ, chỉ báo cáo; commit cuối là `HEAD~1..HEAD`, một commit là `abc^..abc`; có `--fix`, `--comment`, `--max-findings`; effort `low` ít dương tính giả hơn. Luật repo: tối đa 2 vòng mỗi lane hoặc slice, từ vòng 3 chỉ sửa MAJOR do chính thay đổi gây ra. **[SUY LUẬN, chưa đo]** chỉ review commit cuối rẻ hơn nhưng có thể bỏ sót tương tác với code cũ. Cách cân bằng: vòng 1 xem toàn bộ thay đổi, các vòng sau xem commit sửa cộng danh sách phát hiện còn mở, vòng cuối xem lại toàn bộ một lần.

## E. Việc còn lại

- Người dùng đo hạn mức gói bằng `/usage` trên app desktop (mốc trước và sau 20 đến 30 tin nhắn ngắn trên context lớn).
- Đo jitter thật bằng `/loop` trên terminal hoặc app trên máy người dùng.
- Mở PR cho nhánh nghiên cứu nếu người dùng muốn; chưa có PR.
- Mục 6 của handoff (10 case); case 1, 2, 4, 9, 3, 6 cần trần chi tiêu mới (còn khoảng 0,6 USD trong trần 22).
