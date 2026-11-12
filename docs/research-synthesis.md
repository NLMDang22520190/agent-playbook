# Tổng hợp nghiên cứu: quy trình phát triển với agent, chi phí và chất lượng

Phạm vi: bốn câu hỏi của người dùng (chi phí token, chia role nhiều model, SDD so với TDD, loop engineering), kèm những gì đã đo trong
phiên làm việc ngày 2026-11-03 đến 2026-11-04 và những gì chưa đo. Nhãn: **[ĐO]** là số tính từ dữ liệu trong phiên này,
**[SUY LUẬN]** là diễn giải của người viết, **[CHƯA KIỂM CHỨNG]** là nguồn thứ cấp hoặc chưa đọc được nguồn gốc.

Giới hạn chung (đọc trước): hầu hết thí nghiệm có k từ 2 đến 5, nên khoảng tin cậy rộng; chưa có số liệu chất lượng ngoài
"qua hay không qua hidden test"; chưa quy ra tiền (chưa có bảng giá đã kiểm); chỉ một họ task (cửa hàng nhỏ, Node) và một model
(Sonnet 5.5) ở các so sánh chính.

## 1. Chi phí token đi đâu

Nguồn: transcript của hai session cloud (v0.34 release và v0.35 prep), đọc bằng `tools/usage-report.js`. Mỗi lần gọi API được
đếm một lần theo message id. Cột output bị đếm thiếu nên bỏ qua. Hai session KHÔNG cùng cấu hình: v0.34 chạy sub-agent bằng
Sonnet (tester, implementer), Haiku (mechanical) và Opus (reviewer); v0.35 chạy toàn Opus.

| | v0.34 release | v0.35 prep |
|---|---|---|
| Lần gọi API (luồng chính / sub-agent) | 1.615 (473 / 1.142) | 1.060 (338 / 722) |
| Ghi cache | 15,93M | 7,94M |
| Đọc cache | 344,0M | 219,4M |
| Cold restart (gọi sau nghỉ trên 60 phút, ghi trên 100k) | 4 lần, 2,15M, khoảng 14% tổng ghi | 6 lần, 3,15M, khoảng 40% tổng ghi |

Theo role (phần trăm trên tổng của session):

| Role | v0.34 ghi / đọc | v0.35 ghi / đọc |
|---|---|---|
| Orchestrator (luồng chính, Opus) | 17% / 59% | 51% / 60% |
| Implementer | 43% / 19% (Sonnet) | 17% / 16% (Opus) |
| Tester | 28% / 14% (Sonnet) | 16% / 15% (Opus) |
| Reviewer | 8% / 6% (Opus) | 14% / 6% (Opus) |
| Mechanical | 1% / 1% (Haiku) | không có |

Điều rút ra:

- **[ĐO]** Orchestrator chiếm khoảng 60% lượng đọc cache ở cả hai session; mỗi lần gọi luồng chính đọc trung bình 390k đến 430k token.
  Không có compaction nào (ngưỡng 901.600, context cao nhất khoảng 689k).
- **[ĐO]** Quay lại sau chỗ nghỉ dài làm cache hết hạn và ghi lại toàn bộ context (550k đến 680k token mỗi lần). Chỗ nghỉ của các
  lần này từ 4 đến 16 giờ, trong khi cache sống 1 giờ. Nguyên nhân hết hạn là suy luận từ khoảng trống thời gian **[SUY LUẬN]**.
- **[ĐO]** Đổi model giữa session làm mất cache: ở session này, lần gọi đầu sau `/model` ghi lại 93.896 token và đọc 0.
- **[ĐO]** Sub-agent khởi động nào cũng ghi cache mới: ở v0.34, sub-agent chiếm 83% lượng ghi cache.
- **[ĐO]** Haiku (role mechanical) chỉ chiếm khoảng 1% khối lượng; đổi `mechanical` hay `reviewer_light` sang Haiku gần như không đổi tổng.
- **[ĐO]** Reviewer chỉ 6% đến 8% lượng đọc, nên giữ reviewer ở model mạnh gần như không làm tăng tổng chi phí.
- Chưa so được Sonnet với Opus ở tester và implementer: hai session làm hai loại việc khác nhau.

## 2. Chia role nhiều model có đáng không

Bằng chứng trong repo (docs/delta-audit.md và evals/results): reviewer Sonnet rẻ hơn khoảng 20% nhưng tỉ lệ dùng sub-agent tụt
3/3 xuống 1/3 (Run 32a, bị loại); ở Run 50 tổng chi phí giảm từ 53,79 xuống 48,30 USD mà các kiểm tra chính không giảm, nên
Sonnet thành reviewer mặc định. Chưa có lần đo nào so "một model chạy suốt" với "nhiều vendor".

Bằng chứng mới trong phiên (task cấp dự án, hidden test, không có playbook):

| Model | Qua tất cả hidden test | Chi phí mỗi lần chạy |
|---|---|---|
| Sonnet 5.5 | 5/8 (project-01, hai đợt) | khoảng 0,18 USD |
| Haiku 5.5 | 1/3 | khoảng 0,02 USD |

**[SUY LUẬN]** k nhỏ nên không phân biệt được hai model về chất lượng, nhưng Haiku rẻ hơn khoảng mười lần mỗi lần chạy. Ở cả hai
model, chỗ rớt thường là cùng một chỗ (báo cáo doanh thu, chỗ ẩn thứ hai), không phải năng lực viết code.

Về bài thí nghiệm bạn đọc (điều phối Opus, dev DeepSeek, review Sol): kết quả "task khó thì chia role tốt hơn" trộn ít nhất bốn biến
(chia context, đa dạng model, có vòng review, tốn nhiều compute hơn). Muốn kết luận cần các nhánh đối chứng: một model solo cùng
ngân sách token, cùng model chia vai, rồi mới đến nhiều vendor; chấm bằng hidden test, không bằng đọc mù.

## 3. SDD so với TDD: bổ sung hay thay thế

**Kết luận: bổ sung, không thay thế [SUY LUẬN].** Hai thứ ở hai tầng: SDD quyết định đặc tả nằm ở đâu; TDD ép code theo đặc tả
bằng test trước, vai tách biệt và gate qua git. Playbook đã là SDD ở cấp một thay đổi (`01-spec.md`: Source, Understanding, Impact,
Oracle, AC trích nguyên văn có dẫn nguồn, Non-goals, Slices). Phần thiếu là tầng cấp dự án (business flow, roadmap) và việc giữ
tài liệu đồng bộ với code.

Bằng chứng từ bộ task cấp dự án (cửa hàng nhỏ, Sonnet 5.5):

- **[ĐO]** Có playbook so với không, trên project-01, k=5 mỗi bên: quy tắc nêu rõ 5/5 so với 4/5; báo cáo doanh thu (chỗ ẩn thứ hai)
  0/5 so với 4/5; chi phí trung vị 0,80 so với 0,18 USD (gấp 4,4 lần).
- **[ĐO]** Cả 13 lần chạy đều phát hiện chỗ ẩn thứ hai (0 lần bỏ sót). Khác biệt là hành động: nhánh có playbook nêu ra và để
  người dùng quyết (7/8 lần), nhánh không có thì sửa (4/5). Tức là ở các task này **phát hiện không phải nút thắt**, nên một tầng
  kế hoạch giúp phát hiện nhiều hơn khó cải thiện kết quả.
- **Mâu thuẫn trong playbook**: luật "change only what was asked" đối chọi luật "việc đảo ngược được thì tự chọn mặc định và ghi lại"
  khi một thay đổi làm sai một hành vi có tài liệu ở nơi khác. Đề xuất P1' (hệ quả có tài liệu bảo chứng thành AC; headless sửa nhỏ
  nhất và ghi DECISION; vấn đề có sẵn từ trước vẫn là "found, not fixed") đã được viết và thử một lần: project-01 qua 2/3 so với
  1/3, hai task còn lại ở trần cho cả hai bên, đối chứng không bị phình phạm vi (n=2). **Chưa kết luận** (khoảng tin cậy
  [-0,32; +0,72]). Phần thân quy tắc nằm trong mẫu spec và chỉ 1/8 lần chạy mở mẫu đó, nên liều yếu. Commit P1' ghi rõ "chưa áp dụng".
- **[ĐO]** Ở project-02, playbook hiện tại đã tự sửa hệ quả 3/3 lần khi hệ quả là một đoạn code lặp lại logic; "để lại và báo" chỉ
  xảy ra ở loại hệ quả là báo cáo tài chính có tài liệu riêng.

Chưa thử: nhánh có tầng kế hoạch (business flow, roadmap) đúng nghĩa.

## 4. Loop engineering

**[CHƯA KIỂM CHỨNG]** Nguồn chỉ là đoạn trích của kết quả tìm kiếm; hai trang chính (adtmag.com, machinelearningmastery.com)
vẫn không truy cập được từ container dù người dùng đã mở mạng (có thể thay đổi cấu hình chỉ áp dụng cho session mới).

Ý chính theo các nguồn: thiết kế vòng lặp lặp lại (plan, act, verify, decide) có **luật dừng rõ ràng** thay vì nhắc agent từng lượt;
thuật ngữ nổi lên giữa tháng 6/2026 (Peter Steinberger, Addy Osmani); biến thể "Ralph loop" lặp prompt đến khi test và linter
đạt. Một nguồn thứ cấp trích mức cải thiện từ khoảng 40% lên 60% nhờ vòng kiểm chứng (chưa kiểm chứng). Các nguồn không thống nhất
ranh giới với "harness engineering" và một nguồn nói thuật ngữ này một phần là khẩu hiệu sản phẩm.

So với playbook: playbook đã có vòng lặp **có chặn** (Phase 2 theo slice, tranh chấp quá 2 vòng thì hỏi người dùng, giới hạn vòng
review trong `references/release.md`, mục "Stop and ask the user when"). Chưa có: vòng lặp không cần người chạy theo lịch. Rủi ro
chi phí là có thật: ở v0.34, giai đoạn sửa CI là cụm có nhiều lần gọi và nhiều lần đọc cache nhất. **Chưa có thí nghiệm nào về
loop engineering**; không nên đưa vào trước khi có số đo chi phí trên mỗi task đạt.

## 5. Phát hiện mới về chi phí (miễn phí, từ dữ liệu có sẵn)

Trên project-01, cùng task, cùng nhánh có playbook, 14 lần chạy:

| Số lần gọi Agent | Số lần chạy | Chi phí trung vị | Qua tất cả hidden test |
|---|---|---|---|
| 0 | 4 | 0,30 USD | 1/4 |
| 1 đến 3 | 5 | 0,79 USD | 1/5 |
| 4 trở lên | 5 | 1,28 USD | 2/5 |

**[ĐO]** Chi phí tăng gấp bốn lần theo số sub-agent, và tỉ lệ qua test không tăng theo (n rất nhỏ, và các lần chạy khác bộ điều kiện
quyền). **[SUY LUẬN]** Số lần khởi động sub-agent (chọn Full hay Lite, số slice, số vòng review) là đòn bẩy chi phí rõ nhất trong
dữ liệu, và cũng là đòn bẩy ít nguy hiểm nhất cho chất lượng nếu tester và implementer vẫn tách. Project-02 (hệ quả đơn giản): 6/6
qua với 1 đến 3 sub-agent, khoảng 0,43 USD. Project-03 (Lite, 0 sub-agent): 4/4 qua, khoảng 0,17 USD.

## 5b. Đo đòn bẩy: chạy Lite thay vì để agent tự chọn mức (Sonnet 5.5, có playbook)

Nhánh L thêm "Quick one, please." vào đầu prompt, nên playbook chạy Lite theo luật người dùng nói "quick". Kiểm tra điều trị: nhãn
Lite có ở 10/10 lần chạy và 0 lần gọi Agent. Đối chứng F là các lần chạy cùng cây playbook (A) và cùng adapter, để agent tự chọn.

| Task | Nhánh | Lần chạy | Qua hết | Chi phí trung vị | Chi phí trên mỗi lần qua | Thời gian trung vị |
|---|---|---|---|---|---|---|
| project-01 | Lite | 6 | 1/6 | 0,295 USD | 1,74 USD | 90 s |
| project-01 | F | 6 | 2/6 | 0,733 USD | 2,59 USD | 226 s |
| project-02 | Lite | 4 | 4/4 | 0,19 USD | 0,20 USD | 47 s |
| project-02 | F | 3 | 3/3 | 0,42 USD | 0,42 USD | 115 s |

- **[ĐO]** Chi phí mỗi lần chạy giảm khoảng 2,2 đến 2,5 lần, thời gian giảm khoảng 2,5 lần; chi phí trên mỗi lần qua giảm 33% (project-01) và 52% (project-02).
- **[ĐO]** Các hành vi lõi không tụt: rules, invariants và trang đơn qua 10/10 lần Lite ở project-01 và project-02. Chỗ rớt của Lite
  là cùng chỗ cũ: báo cáo doanh thu (1 sửa, 5 nêu), và ghi quyết định ở project-01 (4/6 so với 7/8 của nhánh F, n nhỏ).
- **Quy tắc quyết định đặt trước** (không thấp hơn quá 0,25 ở cận dưới và giảm chi phí trên mỗi lần qua ít nhất 30%): chi phí đạt ở cả hai task;
  chất lượng **chưa chứng minh** được: chênh lệch tỉ lệ qua của project-01 là -0,17 với khoảng [-0,56; +0,30], của project-02 là 0,00 với [-0,49; +0,56].
  Khoảng tin cậy rộng vì n nhỏ, nên không thể khẳng định không kém hơn.
- **[SUY LUẬN]** Ở loại task này (một module nhỏ, vài file, hidden test), mức Full không cho thấy lợi ích chất lượng đo được so với Lite, trong khi tốn gấp 2 đến 3 lần.
  Đây không phải bằng chứng rằng Full vô ích: các task này có thể quá dễ để lộ giá trị của reviewer độc lập (đúng như Run 25 đã ghi
  về corpus cũ). Với task lớn hơn hoặc khó hơn, chưa có số đo.
- Hai task này vốn thuộc nhóm Full theo luật của playbook (tiền, nhiều file); ép Lite là "người dùng ghi đè", nên kết quả nói về việc Lite
  có đủ không, chưa nói về việc nên đổi luật chọn mức.

## 6. Đã làm ra những gì (trên nhánh `claude/serene-galileo-4sr31t`)

| Thứ | Vị trí | Dùng để |
|---|---|---|
| Báo cáo token theo role, model, đoạn, cold restart | `tools/usage-report.js` (37 assertion) | Đo trước khi tối ưu; `--prices FILE` thêm USD, `--json` cho script |
| Bộ task cấp dự án | `evals/tasks-project/` (3 task, mỗi task có tự kiểm và bản vá sai) | Chạy bằng `--tasks-dir`, không đụng corpus bị ghim |
| Phân loại sửa, nêu, bỏ sót | `evals/tasks-project/outcome-classes.js` (12 assertion) | Tách "phát hiện nhưng chờ quyết định" khỏi "bỏ sót" |
| Adapter cho container không có quyền ghi | `evals/tasks-project/claude-cloud-adapter.sh` | Chọn HOME riêng cho nhánh có playbook; có phanh `.pb-eval-stop` |
| P1' (thử nghiệm, chưa áp dụng) | commit `ff671ad` | Hoàn lại bằng `git revert` |

Cách chạy mẫu: xem `evals/tasks-project/README.md`. Hai biến thể playbook chạy song song bằng hai thư mục HOME riêng
(`install.sh install --home DIR --copy`), không cần `--variant`.

## 7. Bẫy đã gặp (để người sau khỏi lặp lại)

- Adapter mặc định `claude -p` không có cờ quyền: trong container mọi thao tác ghi bị từ chối, agent không làm được gì, và runner
  chấm **FAIL thay vì ERROR** nên trông như task khó. Nên phân biệt hai trường hợp này trong runner.
- Chế độ bỏ qua quyền cho agent con bị bộ phân loại tự động của Claude Code từ chối ("Create Unsafe Agents"); không nên lách.
- `--allowedTools` nhận danh sách biến thiên và nuốt mất prompt nếu prompt là đối số cuối; đưa prompt qua stdin.
- Bộ phân loại đọc lượt trả lời cuối của transcript; nếu agent kết thúc bằng một lượt theo dõi thì có thể phân loại sai.
- File kết quả JSON của runner chỉ được ghi ở cuối; kill runner là mất bản tóm tắt.
- Lần đầu mình đếm nhầm chuỗi kiểm tra liều điều trị (P1'), và hai báo cáo token ban đầu bị lẫn dữ liệu của hai session vì cùng
  ghi vào một thư mục; đã kiểm tra lại từ file gốc.
- Các suite `test-guard-restore-r9`, `r12` và `symlink` thất bại trong container này kể cả khi bỏ thay đổi skill (đã thử); chưa điều tra.

## 8. Chi tiêu

Khoảng 20,9 USD trên trần 22 USD (cộng cột cost_usd của docs/research-data/runs.tsv, không phải số của runner; con số 20,3 báo trước đó thiếu các lần chạy đang dở khi phanh dừng). Chi phí mỗi lần chạy: không có
playbook 0,04 đến 0,23 USD; có playbook 0,13 đến 1,66 USD tùy task và số sub-agent. Ước tính ban đầu "1 đến 2 USD" cho một so sánh
có playbook là sai: nhánh có playbook tốn nhiều hơn mức 2 đến 2,5 lần mà các eval cũ cho thấy.

## 9. Khuyến nghị xếp theo mức tin cậy

| # | Khuyến nghị | Bằng chứng | Đánh đổi |
|---|---|---|---|
| 1 | Đừng để session có context lớn nằm chờ quá 1 giờ; ghi handoff rồi mở phiên mới | Cold restart 14% và 40% tổng ghi cache **[ĐO]** | Mất ngữ cảnh chưa ghi ra file; phụ thuộc chất lượng handoff |
| 2 | Chọn model ở đầu session, không đổi giữa chừng | Đo trực tiếp **[ĐO]** | Không có |
| 3 | Dùng Lite (một context) cho task cỡ nhỏ khi người dùng đồng ý; giới hạn số lần khởi động sub-agent | Lite giảm chi phí mỗi lần chạy 2,2 đến 2,5 lần và chi phí trên mỗi lần qua 33% đến 52%, hành vi lõi không tụt **[ĐO, n nhỏ, chưa chứng minh không kém hơn]** | Mất reviewer độc lập; chưa đo ở task lớn hoặc khó |
| 4 | Giao việc canh CI và đọc log cho sub-agent, chỉ nhận bản tóm tắt | Luồng chính đọc 105M trong giai đoạn sửa CI ở v0.34 **[SUY LUẬN]** | Mất chi tiết; sub-agent khởi động tốn cache |
| 5 | Không tối ưu Haiku cho `mechanical` và `reviewer_light` | Chỉ khoảng 1% khối lượng **[ĐO]** | Không có |
| 6 | Giữ reviewer ở model mạnh | 6% đến 8% lượng đọc **[ĐO]** | Không có |
| 7 | Coi SDD là tầng bổ sung tuỳ chọn, chưa đưa vào mặc định | Phát hiện không phải nút thắt ở các task đã đo **[ĐO]** | Chưa thử tầng kế hoạch đúng nghĩa |
| 8 | Chưa đưa loop engineering không người vào | Nguồn thứ cấp, không có số đo **[CHƯA KIỂM CHỨNG]** | Có thể bỏ lỡ lợi ích |
| 9 | Sửa runner: phân biệt "agent bị từ chối quyền" với "agent làm sai" | Đã làm sai kết quả hiệu chỉnh một lần | Thay đổi nhỏ ở runner |

## 10. Câu hỏi còn mở

1. Ở task lớn hoặc khó hơn, reviewer độc lập và sub-agent có đem lại chất lượng đo được không (ở các task nhỏ thì chưa thấy)?
2. P1' có Δ > 0 khi liều đủ mạnh (câu cốt lõi nằm trong `SKILL.md`) và k đủ lớn không?
3. Cắt cold restart bằng handoff có làm tụt chất lượng không (cần đo trên session thật có chỗ nghỉ dài)?
4. Kết quả có giữ khi đổi model chính (Opus) hoặc loại task (không phải cửa hàng)?
5. Quy ra tiền: cần bảng giá hiện hành rồi chạy `usage-report.js --prices`.
