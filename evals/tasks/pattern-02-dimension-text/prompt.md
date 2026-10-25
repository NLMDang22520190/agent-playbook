Khách báo form báo giá hộp cứ báo "kích thước không hợp lệ" dù họ nhập đúng. Mình thử lại thì thấy:

- `150×100×50` (dấu nhân, khách copy từ file Word) -> không hợp lệ
- `150 x 100 x 50` (có dấu cách) -> không hợp lệ
- `150X100X50` (chữ X hoa) -> không hợp lệ
- `150x100x50` -> OK

Cả ba cách trên đều là 150 x 100 x 50 mm, form phải nhận được. Các trường hợp sai thật (thiếu một cạnh, nhập chữ, cạnh bằng 0)
thì vẫn phải báo không hợp lệ như bây giờ. Nhờ sửa giúp phần đọc kích thước.
