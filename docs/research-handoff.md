# Handoff: kết quả nghiên cứu quy trình phát triển với agent

Dành cho một agent mới, chưa có ngữ cảnh. Chỉ chứa KẾT QUẢ NGHIÊN CỨU (đã đo, chưa đo, đã sai và đã sửa). Không chứa đề xuất sửa code
hay quyết định áp dụng; người dùng sẽ hỏi tiếp từng case ở session mới. Bản diễn giải dài hơn: `docs/research-synthesis.md`. Phát hiện bổ sung và số liệu đã sửa: `docs/research-addendum-2026-11-09.md`. Kết luận sau đợt đo local và danh sách ứng viên v0.36: `docs/research-conclusions-2026-11-12.md`. Cách kiểm chứng skill và các công cụ có sẵn: `docs/research-skill-verification-2026-11-13.md`.

Nhãn: **[ĐO]** tính từ dữ liệu thật trong file này hoặc repo; **[SUY LUẬN]** là diễn giải; **[CHƯA KIỂM CHỨNG]** là nguồn thứ cấp hoặc chưa
đọc được nguồn gốc. Đừng nâng một [SUY LUẬN] thành sự thật khi trả lời người dùng.

## 0. Cách dùng handoff này

- Nhánh git: `claude/serene-galileo-4sr31t` (chưa merge vào `main`). Đọc nó trong session mới bằng
  `git fetch origin claude/serene-galileo-4sr31t` rồi `git show origin/claude/serene-galileo-4sr31t:docs/research-handoff.md`
  (hoặc `git checkout` nhánh đó).
- Dữ liệu từng lần chạy: `docs/research-data/runs.tsv` (57 dòng, mô tả cột ở mục 7). Khi người dùng hỏi một con số, tính lại từ file này
  trước khi trả lời, đừng dựa vào bảng tóm tắt.
- Ngôn ngữ người dùng: tiếng Việt. Văn bản người khác sẽ đọc: không dùng gạch dài (em dash, en dash).
- Quy tắc chi tiêu: người dùng đặt trần 22 USD cho cả đợt nghiên cứu này, đã dùng khoảng 20,9 USD (mục 8). KHÔNG chạy thí nghiệm tốn tiền
  khi chưa có trần mới do người dùng nêu rõ.

## 1. Người dùng muốn gì

Mục tiêu: chất lượng đầu ra và chi phí; tốc độ không phải yếu tố chính. Bốn câu hỏi gốc:

1. Chi phí token đi đâu khi agent chạy, cắt chỗ nào mà giữ chất lượng.
2. Chia role nhiều model (điều phối, dev, review) so với một model chạy suốt: bên nào tốt hơn về chất lượng và chi phí.
3. Nên bổ sung hay thay thế cách làm TDD của repo agent-playbook bằng SDD (spec-driven development).
4. Loop engineering là gì và có đáng đưa vào không.

Bối cảnh: repo `NLMDang22520190/agent-playbook` (bộ kỹ năng cho agent: spec, tester/implementer/reviewer tách context, gate qua git, mức
Full/Lite/Exempt theo rủi ro). Người dùng đã đưa vào một bài viết về người dùng Claude Max tối ưu luồng làm việc, một thí nghiệm chia role
nhiều model (điều phối Opus, dev DeepSeek, review Sol; "task khó thì chia role tốt hơn" qua chấm mù), và một bản tóm tắt 4 video Facebook
(SDD, tối ưu token Claude Code, quy mô Anthropic, workshop token). Không có số liệu gốc nào trong số đó; coi chúng là giả thuyết.

## 2. Kết quả đã có

### R1. Token đi đâu (session cloud v0.34 và v0.35 của người dùng) [ĐO]

Hai session chạy song song, cấu hình KHÁC nhau: v0.34 dùng Sonnet cho tester, implementer, Haiku cho mechanical, Opus cho reviewer;
v0.35 toàn Opus. Mỗi lần gọi API đếm một lần theo message id. Cột output bị đếm thiếu nên bỏ qua.

| | v0.34 release | v0.35 prep |
|---|---|---|
| Lần gọi (luồng chính / sub-agent) | 1.615 (473 / 1.142) | 1.060 (338 / 722) |
| Ghi cache | 15,93M | 7,94M |
| Đọc cache | 344,0M | 219,4M |
| Cold restart (gọi sau nghỉ trên 60 phút, ghi trên 100k) | 4 lần, 2,15M, khoảng 14% tổng ghi | 6 lần, 3,15M, khoảng 40% tổng ghi |

Theo role (ghi cache / đọc cache, phần trăm của session):

| Role | v0.34 | v0.35 |
|---|---|---|
| Orchestrator (luồng chính, Opus) | 17% / 59% | 51% / 60% |
| Implementer | 43% / 19% (Sonnet) | 17% / 16% (Opus) |
| Tester | 28% / 14% (Sonnet) | 16% / 15% (Opus) |
| Reviewer | 8% / 6% (Opus) | 14% / 6% (Opus) |
| Mechanical | 1% / 1% (Haiku) | không có |

Không so được Sonnet với Opus ở tester/implementer từ bảng này: hai session làm hai loại việc khác nhau (v0.34 có nhiều vòng sửa CI).

### R2. Hành vi cache [ĐO trừ chỗ ghi chú]

- Mỗi lần gọi luồng chính đọc trung bình 390k đến 430k token; không có compaction (ngưỡng 901.600, context cao nhất khoảng 689k).
- Quay lại sau chỗ nghỉ dài ghi lại toàn bộ context (550k đến 680k token mỗi lần), chỗ nghỉ 4 đến 16 giờ so với cache sống 1 giờ.
  Nguyên nhân hết hạn là [SUY LUẬN] từ khoảng trống thời gian.
- Đổi model giữa session làm mất cache: ở session nghiên cứu này, lần gọi đầu sau `/model` ghi lại 93.896 token và đọc 0.
- Sub-agent khởi động nào cũng ghi cache mới; ở v0.34, sub-agent chiếm 83% lượng ghi.
- Haiku (mechanical) chỉ khoảng 1% khối lượng; reviewer chỉ 6% đến 8% lượng đọc.

### R3. Chia role nhiều model [Một phần]

- Bằng chứng cũ trong repo (`docs/delta-audit.md`): reviewer Sonnet rẻ hơn khoảng 20% nhưng tỉ lệ dùng sub-agent tụt 3/3 xuống 1/3 (Run 32a,
  bị loại); Run 50: tổng chi phí 53,79 xuống 48,30 USD, các kiểm tra chính không giảm, Sonnet thành reviewer mặc định.
- Chưa có phép đo nào "một model chạy suốt" so với "nhiều vendor" về chất lượng.
- Haiku 5.5 so với Sonnet 5.5 (project-01, không playbook, k=3 mỗi bên): cùng qua 1/3; chi phí khoảng 0,02 so với 0,20 USD mỗi lần [ĐO, n rất nhỏ].
- Phê bình bài thí nghiệm "task khó thì chia role tốt hơn" [SUY LUẬN]: nhánh chia role khác nhánh solo ở ít nhất bốn biến cùng lúc (chia context,
  đa dạng model, có vòng review, tốn nhiều compute hơn); cần nhánh đối chứng (một model solo cùng ngân sách token, cùng model chia vai);
  chấm bằng hidden test thay vì đọc mù; task dễ và vừa "không chênh" có thể do chạm trần chứ không do hai cách ngang nhau.

### R4. SDD so với TDD [SUY LUẬN có số liệu]

Bổ sung, không thay. Playbook đã là SDD ở cấp một thay đổi (`01-spec.md`: Source, Understanding, Impact, Oracle, AC trích nguyên văn có dẫn
nguồn, Non-goals, Slices); thiếu tầng cấp dự án (business flow, roadmap) và cơ chế giữ tài liệu đồng bộ với code. Ở các task đã đo, việc
PHÁT HIỆN vấn đề không phải nút thắt (mọi lần chạy đều thấy hệ quả cần xử lý), nên một tầng kế hoạch giúp phát hiện khó cải thiện kết quả ở đó.
Tầng kế hoạch đúng nghĩa CHƯA từng được thử.

### R5. Có playbook so với không, task cấp dự án (project-01, Sonnet 5.5, k=5 mỗi bên, đợt E5) [ĐO]

| Hidden test | Có playbook | Không có |
|---|---|---|
| Quy tắc nêu rõ | 5/5 | 4/5 |
| Bất biến (không mất/thừa cent, mọi thứ tự trả) | 5/5 | 5/5 |
| Trang đơn | 5/5 | 5/5 |
| Báo cáo doanh thu (chỗ ẩn thứ hai) | **0/5** | **4/5** |
| Ghi quyết định | 4/5 | 4/5 |
| Qua tất cả | **0/5** | **4/5** |

Chi phí trung vị 0,80 so với 0,18 USD (gấp 4,4 lần). Lưu ý: nhánh có playbook bị lệch bởi môi trường (4 đến 11 thao tác bị từ chối mỗi lần:
ghi `.git`, đọc `~/.agents`, lệnh nhiều thao tác); một báo cáo cuối ghi các script playbook không truy cập được.

### R6. Mâu thuẫn "phạm vi" và "hệ quả của chính thay đổi" [ĐO]

Cả mọi lần chạy đều thấy `dailyRevenue` bỏ qua hoàn tiền (0 lần bỏ sót; một lần phân loại "bỏ sót" là lỗi của bộ phân loại, mục 5).
Khác biệt là hành động: nhánh có playbook nêu ra và để người dùng quyết (7/8 lần ở E5+E6), nhánh không có thì tự sửa (4/5). Ở project-02 (hệ quả là
một đoạn code lặp logic thuế) playbook hiện tại tự sửa 3/3. Luật liên quan trong repo: `AGENTS.global.md` "Change only what was asked" và
"Found, not fixed" (implementer), đối chọi với "tự chọn mặc định và ghi lại" cho việc đảo ngược được. Bằng chứng đo trước đó cho luật phạm vi
chỉ là ZERO-1 trong `docs/delta-audit.md` (chưa từng thấy Δ > 0).

Thử đề xuất P1' (hệ quả có tài liệu bảo chứng thành AC; headless sửa nhỏ nhất và ghi DECISION; vấn đề có sẵn từ trước vẫn "found, not fixed"),
đợt E8, k=3, có playbook:

| Task | A (hiện tại) qua hết | B (có P1') qua hết |
|---|---|---|
| project-01 | 1/3 | 2/3 |
| project-02 | 3/3 | 3/3 |
| project-03 (đối chứng: lỗi có sẵn từ trước, không được sửa) | 2/2 | 2/2 |

Chênh lệch project-01 +0,33, khoảng 95% [-0,32; +0,72]: KHÔNG kết luận được. Liều điều trị yếu: câu mới trong `SKILL.md` được thấy ở 8/8 lần B, nhưng phần
thân quy tắc nằm trong `templates/spec.md` và chỉ 1/8 lần B mở mẫu đó. P1' nằm ở commit `ff671ad`, ghi "experimental, not adopted".

### R7. Đòn bẩy chi phí: số lần khởi động sub-agent và mức Lite [ĐO, n nhỏ]

Trên project-01, cùng nhánh có playbook, 14 lần chạy (11 lần biến thể A cộng 3 lần biến thể B, đã trộn): chi phí trung vị theo số lần gọi Agent: 0 lần 0,30 USD (1/4 qua), 1 đến 3 lần 0,79 USD (1/5), từ 4 lần
1,28 USD (2/5). Chỉ tính biến thể A (11 lần): 0 lần 0,30 USD (0/3), 1 đến 3 lần 0,79 USD (1/5), từ 4 lần 1,28 USD (1/3). Chạy Lite (thêm "Quick one, please." đầu prompt; nhãn Lite ở 10/10 lần, 0 lần gọi Agent), đợt E9:

| Task | Nhánh | Lần chạy | Qua hết | Chi phí trung vị | Chi phí trên mỗi lần qua | Thời gian trung vị |
|---|---|---|---|---|---|---|
| project-01 | Lite | 6 | 1/6 | 0,295 | 1,74 | 90 s |
| project-01 | agent tự chọn (A) | 6 | 2/6 | 0,733 | 2,59 | 226 s |
| project-02 | Lite | 4 | 4/4 | 0,19 | 0,20 | 47 s |
| project-02 | agent tự chọn (A) | 3 | 3/3 | 0,42 | 0,42 | 115 s |

Chênh lệch tỉ lệ qua Lite trừ A: project-01 -0,17 [-0,56; +0,30]; project-02 0,00 [-0,49; +0,56]. Chi phí đạt tiêu chí giảm 30% đã đặt trước (giảm khoảng 60% theo trung vị đúng; bản trước dùng số giữa trên thay vì trung bình hai số giữa, đã sửa 2026-11-09);
chất lượng KHÔNG chứng minh được không kém hơn (khoảng chứa -0,25). Các hành vi lõi (quy tắc, bất biến, trang đơn) qua 10/10 lần Lite. Hai task này theo
luật playbook vốn thuộc nhóm Full (tiền, nhiều file): ép Lite là "người dùng ghi đè". Task có thể quá dễ để lộ giá trị của reviewer độc lập.

### R8. Loop engineering [CHƯA KIỂM CHỨNG]

Chỉ có đoạn trích kết quả tìm kiếm; hai trang chính (`adtmag.com`, `machinelearningmastery.com`) không truy cập được từ container (ENOTFOUND)
dù người dùng đã mở mạng, có thể chỉ áp dụng cho session mới. Ý chính theo nguồn thứ cấp: thiết kế vòng lặp plan, act, verify, decide có luật dừng rõ;
thuật ngữ nổi lên khoảng 7 đến 8/6/2026 (Peter Steinberger, Addy Osmani); biến thể "Ralph loop" (lặp prompt đến khi test/linter đạt; một nguồn nói có plugin Stop hook
chính thức, chưa xác nhận); một nguồn trích mức tăng khoảng 40% lên 60% nhờ vòng kiểm chứng (chưa kiểm chứng); các nguồn không thống nhất ranh giới với
"harness engineering". Playbook đã có vòng lặp có chặn (theo slice, tranh chấp quá 2 vòng thì hỏi người dùng, giới hạn vòng review trong `references/release.md`);
chưa có vòng lặp không người. Chưa có thí nghiệm nào.

### R9. Prompt cache, TTL, compact [ĐO từ tài liệu; một số phần SUY LUẬN]

Chi tiết và nguồn: `docs/research-addendum-2026-11-09.md` mục 2. Tóm tắt: cache làm mới miễn phí mỗi lần dùng; TTL 1 giờ chỉ cho hội thoại chính trên gói
subscription trong hạn mức (API key, usage credits, cloud: 5 phút; sub-agent, compaction, workflow: 5 phút trừ khi đặt); mỗi model có cache riêng; `/compact`
rẻ khi cache ấm và đắt khi cache đã chết; `idleCompaction` (v2.1.290 trở lên, mặc định bật) tự compact sau khoảng 1 giờ idle khi context từ 200k token.
Giữ sống mỗi 50 phút rẻ hơn cold restart khoảng 20 đến 40 lần theo hệ số giá (hòa vốn khoảng 16 đến 32 giờ idle) **[SUY LUẬN, chưa kiểm giá]**; `/loop` định kỳ
mỗi giờ bị jitter tới 30 phút nên có thể vượt TTL **[theo tài liệu]**. Đơn vị tính trên gói subscription và hành vi session cloud **[CHƯA KIỂM CHỨNG]**.

**Thí nghiệm TTL đã chạy (2026-11-09, `claude -p --resume`, Sonnet 5.5, container này) [ĐO]**: dữ liệu thô ở `docs/research-data/ttl-2026-11-09.tsv`. Cache ghi vào bucket 1 giờ (0 token ở bucket 5 phút).
Phiên B được đánh thức mỗi 54 phút: lần B2 (09:15Z) đọc 35.200 token và chỉ ghi mới 63, dù phần 28k token đầu được ghi từ 07:27Z, tức 108 phút trước. Phần đó sống tiếp vì B1 đã đọc nó ở phút 54, nên **mỗi lần đọc làm mới TTL** và giữ sống mỗi 54 phút hoạt động. Đối chứng không giữ sống (phiên C, idle 2h02m): đọc 0, ghi lại 35.218 token.
Chi phí mỗi lần giữ sống ở context 35k khoảng 0,03 đến 0,07 USD. Giới hạn: một phiên mỗi nhánh (kiểm cơ chế, không phải thống kê); chỉ cho `claude -p` trong container này, chưa chứng minh cho app desktop Windows hay session cloud; B1 ghi lại khoảng 7k token thay vì đọc, chưa giải thích được; chưa đo cách tính cache đọc vào hạn mức gói; chưa đo jitter của `/loop` hay cron.

**Thử cron theo session (CronCreate, 2026-11-09 đến 2026-11-11, container cloud này) [ĐO]**: đặt job mỗi giờ vào phút :07 hai lần (job `4a2475c3` lúc 09:55Z ngày 9, job `19731d7c` lúc 02:19Z ngày 10). Cả hai biến mất trước lần chạy đầu tiên: kiểm lúc 01:00Z ngày 10 và 11:59Z ngày 11, `CronList` báo không còn job và file log chưa được tạo. Session có vẻ đã khởi động lại khi idle (hệ thống nạp lại ngữ cảnh), chưa biết chính xác lúc nào. Công cụ báo offset khác nhau giữa hai job (lần chạy đầu dự kiến lệch +9 phút và +3 phút, giả định giờ UTC), khớp với mô tả "offset cố định theo từng job" nhưng chưa có lần chạy thật để xác nhận. **[SUY LUẬN]** đánh thức bằng cron không giữ cache sống được trong session cloud này; chỉ chắc dùng được khi Claude Code mở trên máy người dùng. Jitter của `/loop` và cron vẫn **[CHƯA KIỂM CHỨNG]**, cần đo trên terminal hoặc app desktop thật. Giới hạn: hai lần thử, một container.

### R10. Lệnh `/code-review` và vòng review hai agent [ĐO từ tài liệu; SUY LUẬN cho đề xuất]

Chi tiết: addendum mục 3. `/code-review` không có vòng lặp nội bộ; phạm vi mặc định là các commit nhánh vượt upstream cộng thay đổi chưa commit; giới hạn một commit bằng
`abc^..abc`. Luật hiện tại của repo: tối đa 2 vòng, từ vòng 3 chỉ MAJOR do thay đổi gây ra. Chưa đo lợi ích của việc chỉ review commit cuối.

## 3. Sổ thí nghiệm

| Đợt | Cấu hình | Lần chạy | Hợp lệ? |
|---|---|---|---|
| E1 | project-01 bản v1, không playbook, adapter mặc định | 2 | **KHÔNG**: mọi lệnh ghi bị từ chối, agent không đổi gì, runner chấm FAIL |
| E2 | project-01 v1 (chưa có báo cáo doanh thu), không playbook | 2 | Có; 2/2 qua (chạm trần) |
| E3 | project-01 v2 (có báo cáo và config, còn gợi ý trong README), không playbook | 2 | Có; 2/2 qua (chạm trần) |
| E4 | project-01 bản cuối, không playbook: Sonnet 1/3, Haiku 1/3 | 6 | Có |
| E5 | project-01, có và không playbook, k=5 | 10 | Có, nhánh có bị lệch bởi từ chối quyền |
| E6 | project-01, có playbook, thêm `--add-dir` và Agent | 3 | Có, vẫn 5 đến 10 từ chối mỗi lần |
| E7 | project-02 và 03, không playbook, k=2 | 4 | Có; đều 2/2 |
| E8 | A so với B (P1') trên 3 task, k=3 (project-03 chỉ 2) | 16 | Có |
| E9 | Lite (quick) trên project-01 (6) và project-02 (4) | 10 | Có |

Tập task: `evals/tasks-project/` (project-01 hoàn tiền, project-02 miễn thuế với hoá đơn lặp logic thuế, project-03 tìm kiếm với lỗi có sẵn phải để nguyên). Mỗi task có
hidden test theo nhóm, bản vá lời giải và nhiều bản vá sai, tự kiểm bằng `bash evals/check-tasks.sh --tasks-dir evals/tasks-project`. Phiên bản task: v1 (E2), v2 (E3),
final (từ E4).

## 4. Chi phí tham khảo mỗi lần chạy (Sonnet 5.5) [ĐO]

Không playbook: 0,04 đến 0,23 USD. Có playbook: 0,13 đến 1,66 USD tuỳ task và số sub-agent (project-01 trung vị khoảng 0,8 đến 1,3; project-02 khoảng 0,42;
project-03 khoảng 0,17). Ước tính ban đầu "1 đến 2 USD" cho một so sánh có playbook k=5 là SAI: thực tế nhánh có playbook tốn gấp 2,6 đến 4,4 lần.

## 5. Lỗi đã mắc và đã sửa (đừng lặp lại)

- Hai agent phụ đọc transcript v0.34/v0.35 cùng ghi vào một thư mục và gộp nhầm dữ liệu của hai session; số đúng đã tính lại từ file gốc, tách theo `session_id`.
- Từng đếm nhầm chuỗi kiểm tra liều điều trị P1' (báo "không thấy" trong khi chuỗi đó chỉ nằm trong mẫu, còn `SKILL.md` có câu khác); đã đối chiếu lại.
- Đợt E1 không hợp lệ vì thiếu quyền; runner chấm FAIL thay vì ERROR nên suýt bị đọc như task khó.
- Hiệu chỉnh nhiều lần: task bản đầu bị chạm trần (Sonnet qua hết), phải gỡ gợi ý trong README mới có chỗ phân biệt.
- Một test của task project-03 có lỗi (mảng dùng chung bị sửa bởi test trước); đã được bộ tự kiểm bản vá sai phát hiện và sửa.
- Bộ phân loại `outcome-classes.js` chỉ đọc lượt trả lời cuối; một lần B bị gán "bỏ sót" thực ra đã nêu vấn đề (transcript nhắc 29 lần).
- Phanh ngân sách của mình bỏ sót các lần chạy đang dở nên báo thiếu: tổng đúng khoảng 20,9 USD, không phải 20,3.
- Ước tính chi phí đợt so sánh có playbook sai (mục 4).

## 6. Chưa đo / câu hỏi mở (người dùng sẽ chọn từng case)

| # | Case | Thiết kế gợi ý | Chi phí ước tính |
|---|---|---|---|
| 1 | Lite có đủ cho task lớn hoặc khó (nhiều module, yêu cầu mơ hồ thật) | Viết 1 đến 2 task lớn, so Lite với agent tự chọn, k=4 đến 6; chấm bằng hidden test | Trên 1 USD mỗi lần có playbook; cần nâng trần |
| 2 | P1' với liều mạnh hơn | Đưa câu cốt lõi vào `SKILL.md` (phải cắt chỗ khác, ngân sách 3700 từ), thêm 2 task "hệ quả là báo cáo/tiền", k lớn hơn | Vài USD |
| 3 | Tầng kế hoạch (business flow, roadmap) đúng nghĩa | Dựng nhánh thí nghiệm, đo bằng task cấp dự án mơ hồ nhiều chỗ | Chưa ước tính |
| 4 | Định tuyến model theo role trên cùng task | Opus điều phối, Sonnet/Haiku làm việc, so với toàn Sonnet và toàn Opus; gắn token theo role bằng `usage-report.js` | Vài USD |
| 5 | Tránh cold restart bằng handoff | Chạy `usage-report.js` trên session thật có chỗ nghỉ dài, trước và sau khi áp dụng | Gần như 0, cần session thật của người dùng |
| 6 | Giao việc canh CI cho sub-agent | Cần task có CI | Chưa ước tính |
| 7 | Loop engineering | Đọc nguồn gốc (cần mở mạng cho container mới), rồi thí nghiệm vòng lặp có giới hạn số vòng | Chưa ước tính |
| 8 | Quy ra tiền | Cần bảng giá hiện hành người dùng xác nhận; chạy `usage-report.js --prices FILE` | 0 |
| 9 | Khái quát hoá | Thêm model chính khác (Opus, model khác vendor) và task không phải cửa hàng Node (Python, bash) | Nhiều |
| 10 | Sửa công cụ | Runner phân biệt từ chối quyền (ERROR) với làm sai (FAIL); bộ phân loại đọc đúng báo cáo | Nhỏ |

## 7. Dữ liệu và công cụ

`docs/research-data/runs.tsv` (phân tách bằng tab, một dòng một lần chạy). Cột: `experiment`, `task`, `arm` (with/without playbook), `playbook_variant`
(A = playbook ở commit 1355bcf; B = A cộng P1'; A+quick = A với tiền tố prompt "Quick one, please."; none = không cài), `model`, `task_version`, `run`,
`status` (graded/ERROR), `passed_all` (1/0, rỗng nếu không chấm), `failed_checks` (tên hidden test rớt), `cost_usd`, `seconds`, `agent_calls`, `tool_calls`, `validity`.
Dòng E1 không hợp lệ (xem mục 3); loại ra khi tính tỉ lệ qua.

Công cụ trên nhánh: `tools/usage-report.js` (báo cáo token theo role/model/đoạn/cold restart, `--json`, `--prices FILE`; chỉ đọc transcript cục bộ của Claude Code
cùng thư mục `subagents/`), `evals/tasks-project/` (task, bộ phân loại `outcome-classes.js`, adapter `claude-cloud-adapter.sh`, README ghi lệnh chạy), `docs/research-synthesis.md`.
Adapter có `PB_EVAL_WITH_HOME` (thư mục HOME riêng đã cài playbook cho nhánh có playbook), `PB_EVAL_PROMPT_PREFIX`, và file `.pb-eval-stop` làm phanh.

## 8. Chi tiêu và giới hạn môi trường

- Tổng khoảng **20,9 USD** trên trần 22 (cộng cột `cost_usd` của `runs.tsv`; chưa tính vài lần thử nhỏ và các lần chạy bị bỏ). Còn khoảng 1,1 USD trước thí nghiệm TTL ngày 2026-11-09 (khoảng 0,5 USD, ngoài runs.tsv), nên còn khoảng 0,6 USD.
- Runner `--max-cost` chỉ chặn việc BẮT ĐẦU lần chạy sau; các lần đang dở vẫn cộng thêm.
- Container cloud ephemeral; thư mục scratchpad (log thô, `result.json`) có thể mất, nên `runs.tsv` là bản lưu bền duy nhất của dữ liệu từng lần chạy.
- Chế độ bỏ qua quyền cho agent con bị bộ phân loại tự động của Claude Code từ chối ("Create Unsafe Agents"); không lách. Adapter dùng `acceptEdits` và danh sách lệnh hẹp.
- Hai host chưa đọc được: `adtmag.com`, `machinelearningmastery.com`.
- Ba suite `test-guard-restore-r9`, `r12`, `symlink` thất bại trong container này kể cả khi bỏ thay đổi skill (đã thử); chưa điều tra trên máy khác.
- Hai PR đang mở của repo: #83 (v0.35.0) và #84 (v0.34.0); nhánh nghiên cứu này cách `main` 9 commit và chưa có PR (PR #85 đã đóng theo yêu cầu người dùng).

## 9. Điều KHÔNG nằm trong handoff

Không có quyết định áp dụng nào: P1' chưa áp dụng, chưa đổi luật chọn mức Full/Lite, chưa đưa gì vào `main`. Đừng coi bất kỳ khuyến nghị nào trong
`docs/research-synthesis.md` là đã được người dùng duyệt.
