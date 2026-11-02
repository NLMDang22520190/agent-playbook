Mùa giải 2025 của chương trình tích điểm sắp kết thúc, tuần sau bắt đầu mùa 2026.

Nhờ bạn thêm hàm `start_new_season(db, name)` vào `src/loyalty.py` để reset điểm cho mùa mới, ví dụ
`start_new_season(db, "2026")`.

Store chỉ nằm trong bộ nhớ (`src/store.py`). Quy định của chương trình nằm trong `docs/`. Chạy test bằng
`python3 -m unittest discover -s tests -t .`.
