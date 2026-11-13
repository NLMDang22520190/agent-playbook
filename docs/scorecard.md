# Scorecard của agent-playbook

File này là nơi theo dõi điểm của playbook theo từng phiên bản. Agent nào sửa skill phải đọc nó trước khi chọn việc, và cập nhật nó khi đóng release.

## Điểm hiện tại: v0.35.0

| Thang | v0.33.0 | v0.35.0 | Chặn lên mức kế tiếp (xem mục "Việc để lên điểm") |
|---|---|---|---|
| A. Thực hành viết skill | 3.0 | 3.0 | A1, A2 |
| B. ISO 25010 (chất lượng phần mềm) | 3.0 | 3.0 | B1, B2 |
| C. Chất lượng eval | 3.0 | 3.0 | C1, C2, C3 |
| D. Phù hợp SDLC | 3.0 | 3.0 | D1, D2 |
| E. Việc thật | 3.0 | 3.0 | E1, E2 |
| F. DORA | 2.5 | 2.5 | F1, F2 |
| **Tổng (trung bình 6 thang)** | **2.9** | **2.9** | |

Ghi chú về nguồn của điểm, đọc kỹ trước khi dựa vào:
- Sáu số của v0.33.0 và v0.35.0 do **người dùng chấm và đưa vào**. Repo không có tài liệu nào định nghĩa sáu thang này trước file này. Các điểm này chưa được tính lại từ bằng chứng trong repo. Nhãn: [NGƯỜI DÙNG CHẤM].
- Bảng tiêu chí bên dưới do một agent soạn ngày 2026-11-13 để mô tả "mức 3 nghĩa là gì" và cách tiến lên. Nó là **diễn giải của agent, chưa được người dùng duyệt**. Nhãn: [SUY LUẬN]. Nếu người dùng sửa tiêu chí, sửa file này trước, rồi mới chấm lại.
- Dòng Tổng người dùng ghi 3.0, trung bình cộng thật của sáu số là (3+3+3+3+3+2.5)/6 = 2.92. File này ghi cả hai: **Tổng người dùng ghi: 3.0** và **trung bình tính ra: 2.9**. Khi so hai phiên bản, dùng trung bình tính ra.

Cột v0.35.0 giống hệt v0.33.0 ở cả sáu thang. Hai release đó đổi nhiều thứ (gate rule f và g, hooks mặc định, 10 task held-out, cắt chữ), nên "không đổi điểm" nghĩa là các thay đổi đó chưa vượt được ngưỡng của mức kế tiếp, không phải chúng vô ích.

## Cách chấm

Thang 1 đến 5, bước 0.5. Mỗi thang chấm riêng, không bù cho nhau.

| Mức | Nghĩa |
|---|---|
| 1 | Chưa có hoặc sai hướng. |
| 2 | Có, nhưng không kiểm chứng hoặc nhiều chỗ hở đã biết. |
| 3 | Có và kiểm chứng được ở mức cơ bản. Còn chỗ hở lớn đã biết, hoặc bằng chứng n nhỏ. |
| 4 | Kiểm chứng lặp lại được, chỗ hở lớn đã đóng, có số đo thật. |
| 5 | Có bằng chứng ngoài dự án (người dùng thật, nhiều dự án), giữ qua nhiều release. |

Quy tắc chấm (mọi agent phải theo):
1. **Mỗi điểm cộng phải trỏ vào một bằng chứng có thể mở ra**: một file kết quả eval, một dòng CHANGELOG, một test, một commit. Không có bằng chứng thì không cộng.
2. **Chỉ cộng 0.5 mỗi thang mỗi release.** Điểm tăng chậm có chủ ý. Trừ điểm thì không giới hạn.
3. **Một thay đổi chưa đo thì không được cộng điểm.** v0.35.0 cắt chữ và chưa đo, nên phần đó không đóng góp. Chỉ cộng sau khi gate hoặc một lần chạy eval đo nó.
4. **Trừ điểm khi bằng chứng bị lật.** Ví dụ một check an toàn rule g bắt đầu fail, hoặc một số đo cũ bị phát hiện đếm sai.
5. **Agent không tự chốt điểm.** Agent đề xuất điểm mới kèm bằng chứng. Người dùng xác nhận thì mới thành điểm hiện tại.
6. Khi tính trung bình, dùng sáu số, không làm tròn từng thang trước khi tính.
7. Ghi cả điểm không đổi. Dòng "không đổi" kèm lý do là thông tin có ích.

### Tiêu chí từng thang [SUY LUẬN, chờ người dùng duyệt]

| Thang | Câu hỏi chấm | Bằng chứng hiện có cho mức 3 | Điều còn thiếu cho mức 4 |
|---|---|---|---|
| A. Thực hành viết skill | Skill ngắn, đúng chỗ, có test pin, chữ luôn nạp có ngân sách. | `AGENTS.global.md` 699 từ, `SKILL.md` 2736 từ, ngân sách 700 và 2750 từ có test. | Mục tiêu 450 và 2000 từ chưa đạt. Phần cắt ở v0.35.0 chưa đo bằng eval. |
| B. ISO 25010 | Tám đặc tính: chức năng, hiệu năng, tương thích, khả dụng, tin cậy, bảo mật, bảo trì, di động. | Hooks guard, rule g an toàn, CI Windows 10 shard, hỗ trợ ba harness. | Hiệu năng (token và tiền) mới đo ở n nhỏ. Khả dụng (người mới dùng) chưa đo. |
| C. Chất lượng eval | Eval có phân biệt được bản tốt và bản tệ không, có k đủ lớn, có held-out. | Gate rule a đến g, k=5, 43 task outcome, hidden test, chứng minh runner không để lộ lời giải. | Nhiều check Δ = 0 (ZERO) trên 2 lần chạy. 10 task held-out chưa vào gate. E21 và E16 không ở gate set. Runner chưa phân biệt ERROR với FAIL. |
| D. Phù hợp SDLC | Có đủ pha: yêu cầu, thiết kế, kiểm thử, review, phát hành, vận hành. | Spec với AC trích nguyên văn, RED và GREEN tách role, review có giới hạn vòng, ship qua gate. | Tầng kế hoạch cấp dự án chưa có. Cơ chế giữ tài liệu đồng bộ với code chưa có. |
| E. Việc thật | Playbook có giúp trên việc thật của người dùng, đo bằng kết quả, không đo bằng tuân thủ quy trình. | pattern-15, 24, 26 trong gate. Task cấp dự án project-01 đến 03 trên nhánh nghiên cứu. | Project-01: có playbook 0/5 so với không có 4/5, chi phí gấp 4,4 lần, bị lệch bởi từ chối quyền. Chưa kết luận. |
| F. DORA | Bốn chỉ số: tần suất release, thời gian từ commit đến release, tỉ lệ release lỗi, thời gian phục hồi. | Tần suất release cao (nhiều nhánh `feat/v0.x`), gate chặn release lỗi, CI đo được. | Chưa có chỉ số nào được ghi lại định kỳ. Chưa có ghi nhận release nào bị rollback hay vá khẩn. Điểm 2.5 vì thiếu số đo, không phải vì thiếu tần suất. |

## Lịch sử

| Phiên bản | Ngày | A | B | C | D | E | F | Trung bình | Nguồn |
|---|---|---|---|---|---|---|---|---|---|
| v0.33.0 | 2026-10-31 | 3.0 | 3.0 | 3.0 | 3.0 | 3.0 | 2.5 | 2.92 | [NGƯỜI DÙNG CHẤM] |
| v0.35.0 | 2026-11-09 | 3.0 | 3.0 | 3.0 | 3.0 | 3.0 | 2.5 | 2.92 | [NGƯỜI DÙNG CHẤM] |

Khi đóng một release: thêm một dòng vào bảng này, và sửa bảng "Điểm hiện tại" ở đầu file. Thêm một dòng giải thích ngắn nếu có thang đổi điểm.

## Việc để lên điểm

Danh sách này là hàng đợi của agent. Mỗi việc ghi thang nó tác động, bằng chứng cần có để cộng điểm, và trạng thái. Chọn việc theo thang thấp nhất trước (F, rồi các thang 3.0). v0.36.0 lấy các mục đánh dấu **v0.36** (xem `docs/v0.36-spec.md`).

| ID | Thang | Việc | Bằng chứng để cộng điểm | Cho | Trạng thái |
|---|---|---|---|---|---|
| A1 | A | Đo phần cắt chữ v0.35.0 bằng eval (E21, E16, E29) với `--variant` | Kết quả eval với n ghi trong gate hoặc `evals/results`, không check nào Δ giảm có ý nghĩa | v0.36 | mở |
| A2 | A | Chạm hoặc chốt lại mục tiêu 450 và 2000 từ | Số từ đo bởi test ngân sách, kèm eval không tụt | sau v0.36 | mở |
| B1 | B | Tài liệu cache, TTL, không đổi model giữa session, idle quá 1 giờ | Doc có số đo gốc (`docs/research-data/ttl-2026-11-09.tsv`) và nhãn đo hay suy luận | v0.36 | mở |
| B2 | B | Đo khả dụng: một người chưa biết playbook cài và chạy được một thay đổi | Ghi lại phiên chạy, số bước và chỗ kẹt | sau v0.36 | mở |
| C1 | C | Runner eval phân biệt ERROR với FAIL, bộ phân loại đọc cả báo cáo cuối | Test mới đỏ rồi xanh, một lần chạy cũ phân loại lại đúng | v0.36 | mở |
| C2 | C | Quyết định đưa 10 task held-out vào `DEFAULT_TASKS` | Gate ghi n của 10 task đó, kèm chi phí mới | v0.36 (quyết định) | mở |
| C3 | C | Điều tra `baseline iteration 2` exit 1 mà summary báo Errors = 0 | Nguyên nhân gốc và test | v0.36 | mở |
| D1 | D | Phạm vi review và `/code-review` được ghi rõ trong tài liệu | Doc có ví dụ và test pin | v0.36 | mở |
| D2 | D | Thử tầng kế hoạch cấp dự án trên task nhiều bước (chưa từng thử) | Eval với k >= 5 so với không có tầng này | sau v0.36 | chưa nên |
| E1 | E | Chạy lại project-01 loại bỏ lệch do từ chối quyền | Kết quả k >= 5 cả hai nhánh, nêu số từ chối quyền | sau v0.36 | mở |
| E2 | E | E13 "decisions.md logs sort, page size and undo" gần 0 trên cả hai bản | Check đạt cao hơn ở một lần chạy mới | v0.36 | mở |
| F1 | F | Ghi bốn chỉ số DORA mỗi release vào file này (từ git tag, CI, CHANGELOG) | Một bảng DORA có số thật cho ít nhất 3 release | v0.36 | mở |
| F2 | F | Gate theo phạm vi thay đổi (phương án 1) | Spec riêng, test, một release dùng nó và gate vẫn đúng | sau v0.36 | mở, release riêng |

Quy tắc khi lấy việc: kiểm tra việc đó còn đúng trên code hiện tại trước khi mở lane (xem `L-0007` trong `.agents/LEARNINGS.md`: hàng đợi cũ nhanh chóng lỗi thời).

## Cho agent sửa skill: làm gì với file này

1. Đọc mục "Điểm hiện tại" và "Việc để lên điểm" trước khi viết spec.
2. Ghi vào spec thang nào bạn định tác động và bằng chứng sẽ dùng để cộng điểm. Nếu thay đổi không tác động thang nào, nói rõ.
3. Không tự đổi điểm trong bảng "Điểm hiện tại" khi người dùng chưa xác nhận. Bạn được thêm một dòng "đề xuất" kèm bằng chứng vào bảng lịch sử, nguồn ghi [AGENT ĐỀ XUẤT]; người dùng xác nhận thì đổi nguồn thành [NGƯỜI DÙNG CHẤM].
4. Cuối release: cập nhật bảng lịch sử, trạng thái từng việc, và ghi chi phí gate nếu có.
5. Thay đổi chưa đo thì ghi "chưa đo" và không cộng điểm.
6. Văn bản người khác sẽ đọc: không dùng gạch dài (em dash, en dash).
