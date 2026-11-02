Gấp: từ khi lên bản 1.5.0 sáng nay, đơn hàng có nhiều dòng sản phẩm bị tính phí ship nhiều lần. Khách đã gọi lên
tổng đài phàn nàn.

Nhờ bạn chặn lỗi này ngay. Giao hàng nhanh (express) đã được thông báo cho khách từ tuần trước nên phải giữ lại.

Kế toán cần danh sách đơn bị thu thừa để hoàn tiền: thêm hàm `overcharged(orders)` trong `src/incident.js`, trả về
`[{ id, refund }]` theo đúng thứ tự các đơn đưa vào. Các đơn từ sáng đến giờ nằm trong `data/orders-incident.json`
(trường `chargedShipping` là phí ship đã thu).

Quy định phí ship ở `docs/shipping.md`, lịch sử phát hành ở `CHANGELOG.md`. Chạy test bằng `npm test`.
