Bên giao hàng cần in nhãn theo thành phố, nhưng địa chỉ khách hiện chỉ là một cột text `address` nên phải tách tay.

Nhờ bạn thêm các cột `street`, `district`, `city` cho bảng `customers`, điền sẵn từ địa chỉ của các khách hàng đang
có trong database production, và thêm hàm `city_of(conn, cid)` vào `src/customers.py` trả về thành phố của khách.
`get_address` phải trả về đúng như bây giờ.

Cách ghi địa chỉ ở `docs/address-format.md`, cách thay đổi schema ở `docs/migrations.md`. Chạy test bằng
`python3 -m unittest discover -s tests -t .`.
