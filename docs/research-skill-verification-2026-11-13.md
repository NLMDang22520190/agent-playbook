# Cách kiểm chứng một skill "hype hay real" và các công cụ có sẵn (2026-11-13)

Nhãn: **[ĐO]** là điều đã chạy hoặc đọc trực tiếp từ nguồn; **[SUY LUẬN]** là diễn giải; **[CHƯA KIỂM CHỨNG]** là chưa kiểm.
Nguồn được đọc qua bước tóm tắt của công cụ đọc web (hai bài arXiv 2609.22114 và 2607.12161 chỉ đọc được bản HTML). Số liệu cần kiểm lại ở nguồn gốc trước khi trích vào tài liệu khác.
Không có quyết định áp dụng nào cho playbook.

## 1. Người ta kiểm chứng thế nào

| Thực hành | Nguồn | Số liệu chính |
|---|---|---|
| So cặp có và không có skill, cùng task, verifier xác định, cố định | SkillsBench (arXiv 2602.12670): 87 task, 3 lượt mỗi ô | Skill chọn lọc 33,9% lên 50,5% (+16,6 điểm); skill agent tự viết thường giảm 8 đến 11 điểm |
| Đối chứng: skill tự sinh, skill gây nhiễu, đối chứng cùng độ dài context | SkillsBench (tự nêu còn thiếu đối chứng cùng độ dài); ACES (arXiv 2608.20614) | 39 trong 49 skill ở SWE-Skills-Bench (arXiv 2603.15401) cho thay đổi tỉ lệ qua bằng 0 |
| Task thật lấy từ PR thật, kiểm trước: lỗi trước khi sửa, qua sau khi sửa, qua khi chạy lại | ServiceNow (bài blog trên community.servicenow.com): 200 task, khoảng 34.000 lượt chấm | Test ẩn chạy sau khi agent dừng, không dùng model chấm model |
| Nhiều lượt mỗi task vì nhiễu lớn | "On Randomness in Agentic Evals" (arXiv 2602.07150), 60.000 quỹ đạo SWE-bench | pass@1 một lượt lệch 2,2 đến 6,0 điểm kể cả temperature 0; nên dùng phân tích công suất để chọn k |
| Chi phí hóa đơn thật, tách ghi cache, đọc cache, output | "Token Reduction Is Not Cost Reduction" (arXiv 2607.12161): 2.848 lượt, Claude Code | Ghi cache 44,3%, đọc cache 35,4%, output 10,4%; phần lớp phía người dùng sửa được khoảng 6% chi phí, trần khoảng 5% |
| Chi phí trên mỗi lần thành công, số lượt gọi, thống kê theo cụm task | cùng bài trên (bootstrap theo cụm task, ICC 0,37 đến 0,55); ServiceNow (so cặp, sign-flip, hiệu chỉnh Holm, báo mức khác biệt nhỏ nhất phát hiện được) | RTK giảm 2,7% chi phí, Headroom tăng 48,4% |
| Ngưỡng tiết kiệm đăng ký trước | ServiceNow: ngưỡng 5% | Headroom và RTK cắt 7 đến 9% token đầu vào nhưng agent chạy thêm 5 đến 9% lượt, không đạt ngưỡng 5% |
| Cô lập từng đòn bẩy, đo nhiều lượt | Paritok (arXiv 2609.22114) | Lọc schema công cụ tiết kiệm khoảng 21K token mỗi lượt (cố định); nén nội dung 1,5 đến 2K mỗi lượt nhưng cộng dồn bậc hai theo số lượt |
| Task nào được và mất | "Beyond Token Savings" (arXiv 2609.32961) | Cùng khoảng 52 so với 53 task giải được nhưng đổi chỗ 7 được 8 mất |

Điểm chung: số token giảm không đồng nghĩa chi phí giảm (lượt gọi thêm, đọc lại tiền tố cache); số đẹp nhất thường do nhà cung cấp tự đo.

## 2. So với việc đã làm ở đợt đánh giá hai skill context

[ĐO] Làm đúng: so cặp có và không có plugin, test ẩn, xen kẽ thứ tự, cost lấy từ runner, ngưỡng đăng ký trước cho bước A và A2, đo cận trên miễn phí trước khi tốn tiền. Kết quả bước A (kết quả công cụ từ 4 KB trở lên chiếm 9,33% và 5,81% các lượt đọc, tiết kiệm tối đa 2,9% đến 8,9%) khớp độc lập với trần khoảng 5% và với 7 đến 9% của ServiceNow.
[SUY LUẬN] Còn thiếu so với chuẩn trên: task tổng hợp thay vì task từ PR thật (không tới vùng context trên 100K); k=3 và không có phân tích công suất (mức khác biệt nhỏ nhất phát hiện được rất lớn với 11 lượt mỗi nhánh); chưa tách chi phí đọc và ghi cache theo nhánh; chưa tính chi phí trên mỗi lần qua một cách có hệ thống; chưa phân tích task nào được và mất; chưa đo chi phí cố định của định nghĩa công cụ của plugin (mỗi lượt gửi lại); chưa kiểm soát carryover cache giữa lượt liên tiếp (TTL 5 phút); chưa có đối chứng skill chuẩn (skill gây nhiễu, đối chứng cùng độ dài).
[SUY LUẬN] Chuẩn nghiêm túc đắt (ước tính vài chục đến vài trăm USD cho 10 đến 20 task thật, k=3, hai nhánh), nên cách rẻ khả thi là: đo chi phí cố định của plugin, mô phỏng theo quỹ đạo thật từ transcript, cận trên miễn phí.

## 3. Có bộ công cụ chuyên dùng để kiểm chứng skill không

Trả lời ngắn: có vài công cụ, nhưng non, nhỏ, và không công cụ nào (theo README tôi đọc) đóng gói sẵn phương pháp chi phí trên mỗi lần thành công, bootstrap theo cụm task và ngưỡng đăng ký trước như ServiceNow và Weinberger. Chưa chạy công cụ nào.

| Công cụ | Làm gì | Tình trạng (theo trang repo, không tìm được ngày hoạt động cuối) | Hạn chế |
|---|---|---|---|
| `claude plugin eval` (có sẵn trong Claude Code, chạy `claude plugin eval --help` trên bản 2.1.323) | Chạy bộ eval của plugin (`case.yaml` hoặc `prompt.md` cộng thư mục `graders/`), tự thêm nhánh không có plugin (`--ablation with-without`), `--runs` (mặc định 3), `--max-cost-usd`, `--threshold` để chặn CI, `--json`, `--judge-model` (mặc định Haiku), chạy song song | Tích hợp sẵn, tài liệu trong chính CLI | Thiết kế cho plugin; grader kiểu prompt, không phải test ẩn theo repo; phải đọc kết quả xem có báo chi phí không [CHƯA KIỂM CHỨNG]; chạy mã plugin bằng thông tin xác thực của bạn |
| `UiPath/coder_eval` (Apache-2.0) | Task YAML khai báo, chạy trong sandbox (có driver Docker), kiểm `skill_triggered`, A/B giữa model hoặc công cụ, telemetry token và cost, GitHub Action ghi JUnit | 160 sao, 217 commit, 15 issue mở | Cần Python 3.13+, README không nói số lượt hay kiểm định thống kê; tự nhận không phải benchmark chuẩn |
| `maxvandenhoven/skill-evals` (MIT) | Mỗi lượt một Docker Sandbox mới, có nhánh không cài skill, ghi vết MLflow, kiểm skill có được gọi không | 2 sao, 21 commit | Chỉ một prompt không tương tác mỗi ca; không có thống kê; mẫu ví dụ chỉ 3 lượt |
| `gcamilo/skill-eval` (MIT) | Chấm theo rubric 3 tầng bằng LLM judge (Gemini), so cặp hai chiều để bù thiên lệch vị trí | 3 sao, 2 commit | Cần khóa Gemini; ví dụ chỉ một skill và 15 prompt; không có kiểm định |
| `mooyee0929/skill-eval` | Được nhắc trong kết quả tìm kiếm (A/B headless, judge mù, báo cáo uplift) | Trang trả 404 khi tôi mở | Không kiểm chứng được |
| SkillsBench (`benchflow-ai/skillsbench`, khung BenchFlow, Harbor) | Bộ 87 task có verifier xác định và khung chạy để so skill khi bật và tắt, có bảng xếp hạng | Bộ benchmark công khai, có bản v1.1 | Đo skill nói chung trong các task có sẵn, không đo skill của riêng bạn trên task của riêng bạn; số lượng task khác nhau giữa các nguồn (84, 86, 87) |
| Công cụ eval của repo này (`evals/run-outcome.sh`, `tools/eval-delta.sh`, cổng phát hành quy tắc f) | Hai nhánh có và không có playbook, test ẩn, pass^K, khoảng Newcombe | Dùng trong đợt nghiên cứu này | Chưa có chi phí trên mỗi lần qua, bootstrap theo cụm task; task tổng hợp |

[SUY LUẬN] Với hai skill context: `claude plugin eval` đáng thử cho phần "plugin có được gọi và có đổi điểm không" ở mức rẻ; còn câu hỏi chi phí thật nên dùng runner của repo cộng phần phân tích theo mẫu ServiceNow và Weinberger (chi phí trên mỗi lần qua, số lượt, mô phỏng theo quỹ đạo thật). Nên thêm vào runner: tách chi phí đọc và ghi cache, chi phí trên mỗi lần qua, số lượt gọi, bootstrap theo cụm task.
[CHƯA KIỂM CHỨNG] Phạm vi tìm kiếm: một lượt tìm web cộng một lượt tìm GitHub (kết quả GitHub nhiều nhiễu); có thể còn công cụ khác chưa thấy.
