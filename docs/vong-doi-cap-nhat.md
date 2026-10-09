# Vòng đời cập nhật playbook

```
Phiên làm việc (Claude / Codex / OpenCode, máy nào cũng được)
  └─ skill playbook-feedback: ghi đề xuất có bằng chứng (thụ động, không ngắt việc)
       └─ cuối task, tối đa 1 lần mỗi feedback_interval_days: xem trước → bạn duyệt → feedback.sh submit
            └─ issue trên repo private (kiểm tra trùng, nhãn harness/kind/source)
Bạn triage (hằng tháng)
  └─ agent soạn PR: thay đổi skill + kịch bản eval tương ứng
       └─ CI (Ubuntu + macOS) chạy tests/run-all.sh → bạn review → merge
            └─ tăng VERSION, cập nhật CHANGELOG, tag vX.Y.Z, push tag
Mỗi máy
  └─ install.sh update --check  (cron / Task Scheduler / thủ công)
       └─ install.sh update --yes → checkout tag → cài lại mọi target đã ghi trong .install-targets → doctor
            (lùi bản: install.sh update --to vX.Y.Z --yes)
Hằng quý: kiểm lại docs/harness-notes.md theo tài liệu chính thức, chạy đủ E1–E12 trên mỗi harness
```

## Nguyên tắc
- **Cập nhật theo bằng chứng, không theo lịch.** Lịch chỉ để rà soát.
- **Một thay đổi hành vi = một kịch bản eval** (thêm mới hoặc sửa). Không có eval thì không merge.
- **Ngân sách:** `run-checks.sh` chặn description quá dài, SKILL.md quá 300 dòng, khối always-on
  quá 60 dòng. Thêm luật thì cân nhắc bỏ luật.
- **Không sửa skill đã cài trực tiếp:** bị ghi đè khi update và không đến được máy khác.
- **Máy phát triển** (nơi bạn sửa repo) dùng `git pull` + `install.sh install`. `update` sẽ
  checkout tag (detached HEAD), phù hợp cho máy chỉ dùng.

## Phát hành một bản mới (trên máy phát triển)
```bash
bash tests/run-all.sh                     # phải xanh
# sửa VERSION + CHANGELOG.md
git commit -am "release: vX.Y.Z" && git tag -a vX.Y.Z -m vX.Y.Z
git push origin main vX.Y.Z               # CI chạy trên tag
```

## Nhắc cập nhật tự động (tuỳ chọn)
Linux / WSL (cron, mỗi thứ Hai 9h):
```
0 9 * * 1 $HOME/agent-playbook/install.sh update --check >> ~/.agents/playbook-update.log 2>&1
```
Claude Code có hook `SessionStart` có thể chạy `install.sh update --check` và in một dòng
thông báo. Thêm hook là thay đổi cấu hình harness, nên chỉ làm khi bạn yêu cầu.
