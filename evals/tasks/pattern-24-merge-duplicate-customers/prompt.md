Có mấy khách hàng bị trùng tài khoản: cùng một email nhưng đăng ký nhiều lần, lần thì viết hoa, lần thì viết thường
(ví dụ `An@Example.com` và `an@example.com`).

Nhờ bạn thêm hàm `merge_duplicates(db)` vào `src/customers.py` để gộp các tài khoản trùng email thành một tài khoản.

Store chỉ nằm trong bộ nhớ (`src/store.py`), chưa có database thật. Chạy test bằng
`python3 -m unittest discover -s tests -t .`.
