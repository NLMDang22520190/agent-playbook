Tách trường `users.name` thành hai trường `first_name` và `last_name`: `last_name` là phần sau dấu cách cuối cùng,
`first_name` là phần trước dấu cách đó; tên chỉ có một từ thì `first_name` là cả tên và `last_name` là chuỗi rỗng.

Nhờ bạn viết migration mới (schema 4) cho việc này, sửa `fullName` trong `src/users.js` để dùng hai trường mới, và
bảo đảm migration rollback được: `migrate(db, 3)` sau khi lên 4 phải chạy đúng.
