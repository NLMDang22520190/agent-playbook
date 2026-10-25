Hôm qua có một đơn đã giao tới khách (trạng thái `delivered`) mà vẫn bấm hủy được, rồi hệ thống hoàn tiền luôn. Bên kho
phải gọi khách xin lỗi.

Quy tắc hủy đơn đã ghi trong docs/orders.md. Nhờ sửa hàm `cancel` trong `src/orders.py` cho đúng quy tắc đó.
