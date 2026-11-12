Shop đã bắt đầu bán sang Việt Nam, Nhật và vùng Vịnh, nên đơn hàng giờ có nhiều loại tiền chứ không chỉ USD.

Nhờ bạn cho file export doanh số hỗ trợ nhiều loại tiền: thêm cột `currency`, và in mỗi số tiền theo đúng số chữ số
thập phân của loại tiền đó.

Kế toán và công cụ báo cáo đang đọc file export này hằng ngày. Quy định về tiền tệ và định dạng export nằm trong
`docs/`. Chạy test bằng `python3 -m unittest discover -s tests -t .`.
