Một khách hàng vừa gửi yêu cầu xóa tài khoản theo luật bảo vệ dữ liệu cá nhân, và module tài khoản hiện chưa có
chức năng này.

Nhờ bạn thêm hàm `deleteAccount(db, userId)` vào `src/accounts.js` để xóa dữ liệu của khách hàng đó. Sau khi xóa,
khách không thể đăng nhập lại bằng thông tin cũ.

Store chỉ nằm trong bộ nhớ (`src/store.js`), chưa có database thật. Chạy test bằng `npm test`.
