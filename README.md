# agent-playbook

Bộ skill **global**, dùng chung cho Claude Code, Codex CLI và OpenCode (và các harness đọc chuẩn
Agent Skills / AGENTS.md), để agent làm việc theo kiểu **AI SDLC thay vì AI slop**:

1. **Làm rõ trước khi sửa**: luật luôn bật, có câu ràng buộc nguyên văn của bạn.
2. **Bằng chứng cho mọi khẳng định**: nhãn [VERIFIED]/[INFERRED]/[UNVERIFIED] và `proof-run.sh`.
3. **TDD với 3 vai tách biệt**: tester, implementer, reviewer chạy ở các ngữ cảnh khác nhau, và
   `role-gate.sh` **chặn bằng máy** việc implementer sửa test, tester sửa code, reviewer sửa bất cứ thứ gì.
4. **Learning cục bộ theo dự án**: `.agents/LEARNINGS.md`, có duyệt, có bằng chứng, có giới hạn
   kích thước. Không bao giờ học ngược vào skill global.
5. **Setup lần đầu theo harness**: agent tự nhận diện harness, hỏi một lượt (có mặc định), và
   hoạt động được cả khi chạy headless.

## Cấu trúc

```
AGENTS.global.md        luật luôn bật (installer chèn vào file global của từng harness)
skills/
  playbook-setup/       hỏi và ghi cấu hình lần đầu
  playbook-tdd/         điều phối RED/GREEN/REVIEW, roles/, templates/, references/
  playbook-proof/       chuẩn bằng chứng và Definition of Done
  playbook-learn/       giao thức learning cục bộ
scripts/                conf.sh, role-gate.sh, proof-run.sh, learn.sh (bash 3.2+, không phụ thuộc gì thêm)
templates/LEARNINGS.md
install.sh / install.ps1
tests/                  test cho script và installer (chạy trong sandbox, không đụng HOME thật)
evals/                  kiểm tra tĩnh + 10 kịch bản hành vi + rubric chấm điểm
docs/                   hướng dẫn TDD (tiếng Việt), ghi chú harness kèm nguồn
```

## Cài đặt

Linux, macOS, WSL:
```bash
git clone <repo-riêng-của-bạn> ~/agent-playbook
cd ~/agent-playbook
bash tests/run-all.sh                              # nên xanh trước khi cài
./install.sh install --harness all --dry-run       # xem trước
./install.sh install --harness all --yes
./install.sh doctor
```

Installer làm những việc sau (idempotent, chạy lại an toàn):

| Harness | Skills | Luật luôn bật |
|---|---|---|
| Claude Code | symlink `~/.claude/skills/playbook-*` | khối quản lý trong `~/.claude/CLAUDE.md` |
| Codex CLI | symlink `~/.agents/skills/playbook-*` | khối quản lý trong `~/.codex/AGENTS.md` |
| OpenCode | đọc sẵn `~/.claude/skills` và `~/.agents/skills`, nên không tạo bản trùng | `~/.config/opencode/AGENTS.md`; nếu file này chưa có và đã cài cho Claude, OpenCode tự fallback sang `~/.claude/CLAUDE.md` |

Đường dẫn ổn định cho script là `~/.agents/playbook/{scripts,templates,VERSION}`. Nội dung có sẵn
của bạn trong các file global được giữ nguyên và sao lưu vào `~/.agents/playbook-backups/` trước
mỗi lần sửa. Installer từ chối ghi đè thư mục không do nó quản lý, trừ khi có `--force`, và khi đó
thư mục cũ được chuyển vào backups.

**Windows (repo nằm trong WSL, harness chạy trên Windows):** chạy từ WSL và trỏ `--home` sang
home của Windows, dùng `--copy` vì symlink từ Windows sang WSL không dùng được:
```bash
./install.sh install --home /mnt/c/Users/<tên> --harness claude --copy --yes
```
Nếu repo nằm thẳng trên Windows, dùng `install.ps1` (cần Git for Windows):
```powershell
.\install.ps1 install -Harness claude -Yes
```
Sau khi `git pull` bản mới, chạy lại `install` (với `--copy` thì bắt buộc). `doctor` báo `drift`
khi bản copy hoặc khối luật đã cũ.

## Lần đầu dùng

Mở **phiên mới** trong harness (skill được nạp lúc khởi động), rồi nói: *"set up the playbook"*.
Agent sẽ nhận diện harness, đọc dự án để đoán lệnh test/lint, hỏi tối đa 7 câu (mỗi câu có mặc
định), rồi ghi `~/.agents/playbook.conf` và `<dự án>/.agents/playbook.conf`.

Trong mỗi dự án, nên chạy (agent sẽ hỏi trước khi làm):
```bash
bash ~/.agents/playbook/scripts/learn.sh init --link-agents --link-claude
```

## Dùng hằng ngày
- Thêm hoặc sửa chức năng, sửa bug: agent tự dùng `playbook-tdd`. Bạn sẽ thấy các file
  `.agents/handoff/01-spec.md`, commit `test(red)`/`feat(green)` và báo cáo cuối có bảng AC, test, bằng chứng.
- Hỏi đáp hoặc chẩn đoán: câu trả lời có nhãn độ tin cậy và bằng chứng (`playbook-proof`).
- Bạn sửa agent ("dự án này luôn dùng UTC"): agent đề xuất một mục learning và chờ bạn duyệt.

## Kiểm thử chính bộ skill
```bash
bash tests/run-all.sh          # script + installer + kiểm tra tĩnh (không cần model)
bash evals/make-fixture.sh     # repo mẫu cho kịch bản hành vi
```
Sau đó chạy 10 kịch bản trong `evals/scenarios.md` trên từng harness và chấm theo `evals/RUBRIC.md`.
**Đây là bước duy nhất chứng minh agent thật sự tuân thủ.** Test script chỉ chứng minh công cụ đúng.

## Giới hạn (nói thẳng)
- Tách vai bằng ngữ cảnh mới vẫn là cùng một model, nên vẫn chung điểm mù. Nên chọn model khác cho reviewer.
- `role-gate.sh` phân loại test hay code theo đường dẫn (regex chỉnh được). Nó không ngăn được việc
  implementer đặt logic đặc biệt cho input của test trong code; reviewer và mutation spot-check bắt lỗi đó.
- Codex chỉ có sub-agent khi bật tính năng multi-agent. Nếu không, playbook chạy chế độ `manual`
  (mỗi vai là một lần `codex exec` riêng).
- Hành vi theo chữ (hỏi lại, đính kèm bằng chứng) phụ thuộc vào việc model tuân thủ. Gate chỉ cưỡng chế được phần cơ học.

## Cập nhật và góp ý cải thiện
- Agent ghi lại khi một luật của playbook sai, thiếu hoặc vướng (`playbook-feedback`). Cuối task,
  tối đa 1 lần mỗi 7 ngày, nó hỏi bạn có gửi các đề xuất thành issue không, kèm bản xem trước.
- Mỗi máy: `./install.sh update --check`, rồi `./install.sh update --yes`. Lệnh này lấy tag mới
  nhất, hiện CHANGELOG, và **cài lại mọi nơi đã từng cài từ repo này** (kể cả home Windows ở chế độ
  copy). Lùi bản bằng `--to v0.1.0`.
- Lần đầu trên repo GitHub: `tools/setup-labels.sh OWNER/REPO` để tạo nhãn cho issue.
- Chi tiết vòng đời: `docs/vong-doi-cap-nhat.md`.

## Khi cài cùng Superpowers hoặc skill khác
Khối luật luôn bật có mục *When other skills overlap*: tách vai tester/implementer/reviewer,
reviewer tự chạy lại test và hỏi gộp một lượt luôn thắng khi xung đột với `test-driven-development`,
`subagent-driven-development` hoặc `brainstorming`. Kịch bản E11 kiểm tra điều này.

## Gỡ cài đặt
```bash
./install.sh uninstall --harness all --yes   # chỉ gỡ những gì installer tạo; giữ cấu hình và backup
```

Xem thêm: `docs/tdd-huong-dan.md`, `docs/harness-notes.md`, `CHANGELOG.md`.
