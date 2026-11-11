# Đánh giá hai công cụ tiết kiệm context: Context Mode và billion-context (2026-11-11)

Báo cáo theo handoff của người dùng. Nhãn: **[ĐO]** là số đo hoặc đọc trực tiếp từ mã nguồn/README; **[SUY LUẬN]** là diễn giải; **[CHƯA KIỂM CHỨNG]** là chưa kiểm.
Không cài đặt, không sửa cấu hình, không đưa khóa API vào công cụ nào. Mã nguồn của hai repo chỉ được clone nông vào thư mục tạm để đọc, không chạy.
Không có quyết định áp dụng nào cho playbook.

## 1. Context Mode (mksglu/context-mode)

[ĐO từ mã nguồn và README]
- Bản 2.1.7 trong `package.json`; giấy phép Elastic License 2.0; cần Node 24.15 trở lên (container nghiên cứu có Node 22); trên Windows cần Git for Windows.
- Hook trên Claude Code (`plugins/claude-code/hooks/claude-code.json`): `PreToolUse` và `PostToolUse` cho Bash, PowerShell, Read, Grep, WebFetch, Write, Edit, NotebookEdit; `SessionStart`; `UserPromptSubmit`. File `hook.mjs` là bản đóng gói nén (khoảng 155 KB), không đọc được như mã nguồn thường.
- Chặn hoặc chuyển hướng WebFetch, curl/wget, Read cả file trên 16.384 B, lệnh kiểu `cat`; output công cụ trên 4.096 B được lập chỉ mục vào SQLite cục bộ (`~/.context-mode/.../context.db`) và agent nhận các đoạn khớp nhất. Read có `offset` hoặc `limit` chạy bình thường.
- Tác giả tuyên bố không có telemetry. Grep trong `src` chỉ thấy URL tới GitHub, npm, nodejs.org và liên kết tài liệu `contextmode.ai`. Chưa kiểm toán đầy đủ.
- `ctx_execute` chạy mã với mạng và biến môi trường của người dùng; tài liệu khuyên giữ bật hỏi quyền.
- Benchmark: 99,4% là trung vị trên 36 dòng có output thô từ 10 KB, do tác giả đo (byte chia 4 cho token); tìm kiếm tiết kiệm 77,2%.
- ELv2: cho dùng và sửa; cấm cung cấp như dịch vụ lưu trữ, cấm bỏ qua chức năng khóa giấy phép, cấm xóa thông báo bản quyền.

[CHƯA KIỂM CHỨNG] Xung đột với hook guard của playbook (`scripts/guard-irreversible.sh`, cài mặc định từ v0.33) vì cùng matcher; ảnh hưởng của việc chặn Read file lớn lên luồng tester và reviewer; hành vi trên app desktop Windows.

## 2. billion-context (ranxianglei/billion-context)

[ĐO từ mã nguồn và README]
- Bản 0.1.213; MIT cộng điều khoản bắt buộc ghi công (trang chủ, tài liệu hoặc trang About, kèm liên kết repo) cho sản phẩm hiển thị cho người dùng cuối.
- Tự cập nhật (`src/update.ts`): tải tarball từ npm rồi giải nén đè lên bản đang cài; mặc định trễ ngẫu nhiên 15 phút đến 48 giờ; tắt mặc định chỉ trong container; tắt bằng `--no-auto-update`. Thêm vào đó nó thăm dò gói `billion-context-advisories`.
- Lưu lượng OAuth subscription cần "chế độ MITM mặc định": proxy dùng `HTTPS_PROXY` cộng `NODE_EXTRA_CA_CERTS` với CA riêng, tức giải mã TLS.
- Tư thế gốc cho Claude ghi khối managed settings gồm đổi `ANTHROPIC_BASE_URL` và `DISABLE_AUTO_COMPACT=1`, tức tắt compact có sẵn của Claude Code.
- README ghi tab Code của Claude Desktop tự đặt `ANTHROPIC_BASE_URL` và bỏ qua proxy hoàn toàn trong khi `DISABLE_AUTO_COMPACT=1` vẫn áp dụng, nên phiên desktop không có nén của họ và mất auto-compaction. Kiểm trên Windows 11 ngày 2026-10-06; bản CC 2.1.301 trở lên có thể đã khác.
- Dump body request mặc định tắt; không có mục telemetry riêng; mã gọi npm, GitHub, API upstream; `package.json` có thêm `mysql2` (chưa rõ lý do).
- Con số của tác giả (cache hit 95 đến 97%, giảm chi phí 58,3% ở ContextBench, 71,1% ở LongMemEval-S) chưa kiểm độc lập và chưa có số đo của chúng ta.

[CHƯA KIỂM CHỨNG] Kho khoảng 80 MB, chỉ đọc cấu hình, phần cập nhật, xác thực và danh sách host; chưa kiểm toán toàn bộ. Cách gỡ sạch khối managed settings.

## 3. Đo trước khi cài [ĐO, giới hạn rõ]

Script `docs/research-data/toolshare.py` đọc một transcript Claude Code và tính tỉ lệ byte của kết quả công cụ. Trên transcript của session nghiên cứu này (chỉ byte văn bản, không tính system prompt hay thinking):

| Chỉ số | Giá trị |
|---|---|
| Output công cụ so với tổng văn bản | 74,7% (300.509 B trong 402.427 B) |
| Số kết quả công cụ | 80 |
| Kết quả trên 4 KB | 17, tổng 243.544 B (81% byte output) |
| Kết quả trên 16 KB | 5, tổng 159.081 B |

Giới hạn: session nặng WebFetch (155.710 B) nên không đại diện cho phiên TDD đọc repo; đơn vị là byte không phải token. Chỉ cho thấy phần Context Mode có thể nhắm tới là lớn ở loại session này.

## 4. Chưa làm

- Thử hook của Context Mode bằng payload giả (không qua API): bị bộ phân loại tự động của Claude Code chặn vì là mã tải từ bên ngoài; không lách. Muốn làm cần người dùng thêm quy tắc cho phép, hoặc làm trên máy người dùng.
- Phép đo ba nhánh (baseline, Context Mode, billion-context) trên project-01 và project-02, k=5, khoảng 30 lần chạy, ước tính 9 đến 24 USD **[SUY LUẬN]** theo bảng chi phí ở handoff mục 4. Cần người dùng nêu trần mới; còn khoảng 0,6 USD trong trần 22.
- billion-context là proxy nên khóa API luôn đi qua nó, mâu thuẫn với ràng buộc "không đưa khóa vào công cụ"; muốn thử cần khóa tạm có hạn mức chi tiêu nhỏ.

## 5. Khuyến nghị [SUY LUẬN]

1. Context Mode: có thể thử có kiểm soát trên nhánh riêng, bật hỏi quyền, ghi lại xung đột với guard, đo token trước và sau trên một tác vụ lặp lại được.
2. billion-context: chưa cài trên máy chính. Nếu thử, chỉ trong container, khóa tạm hạn mức nhỏ, ghim phiên bản, tắt tự cập nhật, tự xem tarball trước khi cài, và không dùng với app desktop khi chưa xác nhận phiên desktop có qua proxy.
3. Playbook: tối đa một mục "công cụ tùy chọn, chưa kiểm chứng" trong tài liệu, sau khi đo xong. Không làm skill, không tích hợp mặc định.
