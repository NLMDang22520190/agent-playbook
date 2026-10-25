Kế toán báo hóa đơn bị lệch tiền so với sổ của họ.

Ví dụ: 3 sản phẩm, đơn giá 0.835 -> hệ thống ra 2.50, kế toán tính ra 2.51. Quy định bên mình: mỗi dòng hóa đơn làm tròn
đến 2 chữ số thập phân theo kiểu làm tròn lên khi đúng nửa (half up), rồi tổng hóa đơn là tổng các dòng đã làm tròn.

Nhờ sửa phần tính tiền trong `src/invoice.py` cho đúng quy định này. Các dòng đang ra đúng thì phải giữ nguyên kết quả.
