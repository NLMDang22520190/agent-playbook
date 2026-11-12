Bên kho báo lỗi tồn kho với đơn có nhiều dòng hàng. Hôm qua khách đặt một đơn gồm 2 ấm trà và 3 hộp trà: sau khi đặt,
số hộp trà còn bán được giảm đúng 3, nhưng số ấm trà còn bán được không giảm chút nào, như thể dòng ấm trà chưa hề được
giữ hàng, nên shop có thể bán quá số ấm trà thật trong kho. Ngoài ra, khi một đơn bị từ chối vì hết hàng
(`out_of_stock`), hàng của đơn đó vẫn bị giữ lại: số còn bán được giảm dù đơn không hề được tạo, và không hủy được.

Nhờ bạn sửa để việc đặt đơn và hủy đơn luôn giữ tồn kho đúng theo `docs/stock-rules.md` (quy tắc đã thống nhất với
bên kho). Mã lỗi trả về cho front end giữ nguyên như trong `CONTRIBUTING.md`.

Chạy test bằng `npm test`.
