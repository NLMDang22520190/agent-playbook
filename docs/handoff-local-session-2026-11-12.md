# Agent handoff cho session local (2026-11-12)

Dành cho một agent mới chạy trên MÁY CỦA NGƯỜI DÙNG (Claude Code desktop hoặc terminal, Windows có Git Bash hoặc WSL), chưa có ngữ cảnh.
Session cloud trước đó không làm được vài việc (xem mục 4); session local được giao đúng những việc đó.
Chỉ chứa kết quả nghiên cứu và việc cần làm. KHÔNG chứa quyết định áp dụng cho playbook.

## 0. Đọc trước khi làm

- Repo: `NLMDang22520190/agent-playbook`. Nhánh nghiên cứu: `claude/serene-galileo-4sr31t` (chưa merge vào `main`, chưa có PR). Nhánh phụ: `claude/research-handoff-7q3o80` (chỉ bản sao các file docs mới).
- Đọc theo thứ tự: `docs/research-handoff.md` (gốc, mục R1 đến R10), `docs/research-qa-2026-11-09.md` (câu hỏi và kết quả), `docs/research-addendum-2026-11-09.md`, `docs/research-context-tools-2026-11-11.md`, `docs/research-data/runs.tsv` và `docs/research-data/ttl-2026-11-09.tsv`.
- Lệnh: `git fetch origin claude/serene-galileo-4sr31t` rồi `git checkout claude/serene-galileo-4sr31t` (hoặc `git show origin/claude/serene-galileo-4sr31t:<đường-dẫn>`).
- Người dùng nói tiếng Việt. Văn bản người khác sẽ đọc: không dùng gạch dài (em dash, en dash).
- Nhãn bắt buộc: **[ĐO]** (số đo hoặc đọc trực tiếp từ nguồn), **[SUY LUẬN]**, **[CHƯA KIỂM CHỨNG]**. Không nâng suy luận thành sự thật.
- Khi người dùng hỏi một con số, tính lại từ `runs.tsv` trước khi trả lời.

## 1. Mục tiêu của người dùng

Chất lượng đầu ra và chi phí; tốc độ không quan trọng. Câu hỏi đang mở: (a) token tốn ở đâu và cắt chỗ nào; (b) chia vai nhiều model hay một model; (c) SDD so với TDD; (d) loop engineering có đáng không; (e) giữ cache sống hay handoff khi idle; (f) vòng review hai agent giới hạn 3 vòng và chỉ review diff commit cuối; (g) Context Mode và billion-context có đáng đưa vào playbook không; (h) danh sách thay đổi cho playbook v0.36.

## 2. Kết quả chính đã có (chi tiết và giới hạn nằm trong các file ở mục 0)

- **[ĐO] Token và cache:** chi phí chủ yếu là đọc cache context lớn (v0.34: 344M đọc so với 15,9M ghi); sub-agent chiếm 83% lượng ghi; cold restart sau idle quá 1 giờ chiếm 14% đến 40% lượng ghi (R1, R2).
- **[ĐO] TTL (`claude -p --resume`, Sonnet 5.5, container cloud):** cache ghi vào bucket 1 giờ; mỗi lần đọc làm mới TTL; chu kỳ giữ sống 54 phút giữ được cache (B2 đọc 35.200 token, ghi mới 63); không giữ sống thì sau 2h02m đọc 0 và ghi lại 35.218. Một phiên mỗi nhánh. Chưa chứng minh trên app desktop Windows.
- **[ĐO] Cron theo session** (CronCreate) trong container cloud: hai job hàng giờ biến mất trước lần chạy đầu khi session khởi động lại. Jitter thật của `/loop` và cron: CHƯA đo.
- **[ĐO] Sửa số:** trung vị số chẵn trong handoff cũ sai; Lite project-01 là 0,295 USD và 90 s, nhóm tự chọn 0,733 USD và 226 s (giảm khoảng 60% chi phí, chất lượng chưa chứng minh không kém hơn).
- **[ĐO] R5:** có playbook qua hết 0/5, không có 4/5 trên project-01, chi phí gấp 4,4 lần, nhánh có playbook bị lệch bởi từ chối quyền. Chưa kết luận.
- **[ĐO từ mã nguồn] Context Mode** (mksglu/context-mode, 2.1.7, ELv2, cần Node 24.15 trở lên): hook PreToolUse chặn Read cả file trên 16.384 B (xác nhận bằng payload giả: deny và chỉ dẫn dùng `ctx_execute`); `cat` file 22 KB KHÔNG bị chặn trong thử nghiệm, khác README. Hook `git checkout <commit> -- file` cho qua.
- **[ĐO từ mã nguồn] billion-context** (ranxianglei, 0.1.213, MIT cộng điều khoản ghi công): tự cập nhật bằng cách tải tarball từ npm rồi giải nén đè (tắt bằng `--no-auto-update`); lưu lượng OAuth subscription cần chế độ MITM (CA riêng); tư thế gốc cho Claude ghi `DISABLE_AUTO_COMPACT=1` và đổi `ANTHROPIC_BASE_URL`; README nói tab Code của Claude Desktop bỏ qua proxy mà vẫn mất auto-compaction (kiểm trên Windows 11, ngày 2026-10-06, bản mới có thể khác).
- **[ĐO] Trên transcript session cloud nghiên cứu:** output công cụ chiếm 74,7% byte văn bản; 17 trong 80 kết quả (trên 4 KB) chiếm 81% byte output. Session nặng WebFetch, không đại diện cho phiên TDD.
- **[SUY LUẬN]** Context Mode đáng thử có kiểm soát; billion-context chưa nên cài trên máy chính; playbook chưa tích hợp gì.

## 3. Việc giao cho session local (theo thứ tự ưu tiên)

1. **Đo hạn mức gói (không tốn tiền, bắt buộc là máy người dùng):** mở session mới, nạp context từ 50k token, chạy `/usage` (mốc 0: % session, % weekly, dòng `Prompt cache (main)`), gửi 20 đến 30 tin nhắn ngắn ("ok") mỗi tin chờ trả lời xong, chạy `/usage` lần nữa (mốc 1). Kết luận cache đọc có tính vào hạn mức gói hay không. Ghi nguyên văn hai báo cáo, số tin nhắn, kích thước context, model.
2. **Đo jitter `/loop` hoặc cron thật trên máy:** đặt tác vụ hàng giờ, ghi giờ danh nghĩa và giờ chạy thật trong ít nhất 3 lần; ghi cả việc có chạy khi máy sleep hay không. Chưa đo là chu kỳ 50 phút có vượt TTL 1 giờ hay không.
3. **Giữ sống trên desktop:** kiểm bằng `/usage` (dòng `Prompt cache (main)`) và `tools/usage-report.js` (trên nhánh nghiên cứu, chỉ đọc transcript cục bộ) xem một lần đánh thức ở phút 50 có giữ cache ấm không.
4. **Chạy A/B Context Mode:** `docs/research-data/context-mode-ab/` (README ở đó). Lệnh: `CM_PLUGIN=<context-mode>/plugins/claude-code K=3 BUDGET=3.5 bash docs/research-data/context-mode-ab/run-ab.sh`. Script CHƯA từng chạy; xem "Plugin loaded" khác 0 trước khi tin kết quả. Trần chi tiêu cho đợt này: 5 USD do người dùng đặt (script mặc định dừng ở 3,5). Dán `summary.md` cho người dùng và ghi vào repo với nhãn [ĐO].
5. **Chạy lại probe hook Context Mode trong phiên thật** (khác payload giả): xem `cat` có bị chặn không, và Read file lớn của tester/reviewer có thêm đường vòng không. Script payload giả: `docs/research-data/context-mode-hook-probe.sh`.
6. **billion-context: chỉ khi người dùng đưa khóa tạm có hạn mức chi tiêu nhỏ**, ghim phiên bản, tắt tự cập nhật, xem tarball trước khi cài, và KHÔNG thử trên app desktop khi chưa xác nhận phiên desktop có qua proxy. Không cài trên máy chính.
7. **Danh sách playbook v0.36 (SUY LUẬN, chưa duyệt):** đưa vào tài liệu về cache/TTL, khuyến nghị không đổi model giữa session, khuyến nghị về idle quá 1 giờ, ghi chú giữ sống kèm giới hạn, sửa công cụ eval (runner phân biệt ERROR với FAIL, bộ phân loại đọc cả báo cáo); chỉ ghi tài liệu cho phạm vi review và `/code-review`. Chưa nên: P1', ép Lite, tầng kế hoạch, định tuyến model, loop engineering. Mỗi bản phát hành cần gate khoảng 150 lần chạy trả tiền (theo `CHANGELOG.md`); cần người dùng đặt trần riêng.

## 4. Những gì session cloud KHÔNG làm được (đừng lặp lại)

- Bộ phân loại tự động của Claude Code chặn chạy mã tải từ bên ngoài (`hook.mjs`, `claude -p --plugin-dir`) kể cả khi người dùng cho phép bằng lời; phải có quy tắc trong cài đặt quyền. Đừng lách.
- Container cloud không tạo được proxy kiểu MITM (thông tin xác thực do host quản lý).
- Facebook không trả thân bài cho khách chưa đăng nhập; người dùng phải dán nội dung. Không xem được video.
- Cron theo session mất khi session cloud khởi động lại.
- Hai host `adtmag.com` và `machinelearningmastery.com` chưa đọc được.

## 5. Ràng buộc

- Chi tiêu: trần cũ 22 USD, đã dùng khoảng 20,9 (runs.tsv) cộng khoảng 0,5 (TTL, ngoài runs.tsv); trần mới 5 USD do người dùng đặt riêng cho đánh giá hai công cụ context. Không chạy thí nghiệm tốn tiền ngoài các trần này.
- Không cài đặt, không sửa cấu hình, không chạy lệnh ghi hệ thống khi người dùng chưa xác nhận (trừ việc người dùng đã cho phép rõ ở mục 3).
- Không đưa khóa API hay dữ liệu nhạy cảm vào công cụ thử nghiệm.
- Không tạo PR khi người dùng chưa yêu cầu. Push chỉ lên nhánh được chỉ định; ghi kết quả vào `docs/` của nhánh nghiên cứu.
- Kết quả có thể mâu thuẫn README chính thức của hai công cụ: tin README và báo lại chỗ lệch.
- Khi dùng heredoc trong shell để ghi file có dấu backtick, dùng heredoc có nháy đơn (`<<'EOF'`), nếu không shell sẽ thực thi nội dung trong backtick (đã xảy ra một lần ở session cloud).

## 6. Việc còn tồn đọng khác

Nhánh nghiên cứu cách `main` nhiều commit, cần rebase nếu mở PR. PR #83 (v0.35.0) đang mở, PR #84 (v0.34.0) đã merge. Ba suite `test-guard-restore-r9`, `r12`, `symlink` thất bại trong container cloud, chưa điều tra trên máy khác. Ba video Facebook còn lại và bài về người dùng Claude Max chưa đưa vào. Mục 6 của handoff gốc (10 case) vẫn mở; case 1, 2, 4, 9, 3, 6 cần trần chi tiêu mới.
