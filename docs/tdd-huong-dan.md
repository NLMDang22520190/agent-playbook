# Hướng dẫn TDD cho người mới (và cách playbook dùng nó)

## 1. TDD là gì, trong một câu
Viết **một test nhỏ cho một hành vi** trước, **thấy nó đỏ**, viết **code ít nhất** để nó xanh,
rồi **dọn code** trong khi test vẫn xanh. Lặp lại.

Tại sao phải thấy đỏ? Một test chưa từng đỏ có thể là test không kiểm tra gì cả (assert sai chỗ,
mock hết mọi thứ). Thấy nó đỏ đúng lý do là bằng chứng nó đang đo đúng thứ cần đo.

## 2. Vòng lặp, với ví dụ cụ thể
Yêu cầu: "Giỏ hàng áp mã giảm 10%".

**RED**: test cho hành vi đầu tiên.
```js
test('applies a 10% coupon to the cart total', () => {
  const cart = { items: [{ price: 100, qty: 1 }] };
  expect(totalWithCoupon(cart, { type: 'percent', value: 10 })).toBe(90);
});
```
Chạy và thấy đỏ: `totalWithCoupon is not a function`. Đây là đỏ đúng lý do, vì hàm chưa có.
Nếu đỏ vì sai đường dẫn import thì là đỏ **sai** lý do. Sửa cho đúng rồi chạy lại.

**GREEN**: code ít nhất.
```js
function totalWithCoupon(cart, coupon) {
  const t = cart.items.reduce((s, i) => s + i.price * i.qty, 0);
  return t - t * coupon.value / 100;
}
```
**REFACTOR**: nếu có trùng lặp với `total()` sẵn có thì tái sử dụng nó, chạy lại, vẫn xanh.

**Hành vi tiếp theo** (lát sau): mã hết hạn bị từ chối, giảm không vượt quá tổng, làm tròn tiền...
Mỗi hành vi là một vòng RED, GREEN, REFACTOR riêng.

## 3. Năm lỗi người mới hay mắc
1. **Viết hết test rồi mới code** (lát ngang). Test viết theo phỏng đoán, và không thấy được từng cái đỏ.
2. **Test cách làm thay vì kết quả**: assert "hàm X được gọi 2 lần" thay vì "tổng là 90". Refactor là gãy.
3. **Mock mọi thứ**: test xanh mãi nhưng không chứng minh gì. Chỉ mock ranh giới ngoài (mạng, thời gian, bên thứ ba).
4. **Assert lỏng**: `toBeTruthy()` thay vì giá trị chính xác.
5. **Sửa test cho xanh**: đó là xóa bằng chứng chứ không phải sửa bug.

## 4. Vì sao tách 3 agent
Một agent vừa viết code vừa viết test sẽ viết test **khớp với code của chính nó**, kể cả khi code
sai. Tách vai làm cho:
- **Tester** chỉ thấy spec, nên test phản ánh yêu cầu chứ không phản ánh lời giải.
- **Implementer** không được sửa test, nên chỉ có một cách để xanh: làm đúng hành vi.
- **Reviewer** chỉ đọc, chạy lại test và thử "đột biến" code (mutation) xem test có bắt được không.

Playbook cưỡng chế điều này bằng `role-gate.sh`: sau mỗi vai, gate so diff với commit mốc. Implementer
mà đụng vào file test là gate đỏ ngay, không cần tin lời ai.

## 5. Một vòng đầy đủ trông thế nào
```
01-spec.md (AC1..AC3, slice S1..S3)
S1: tester -> gate tester ✓ -> RED evidence -> commit test(red)
    implementer -> gate implementer --base RED ✓ -> GREEN evidence -> commit feat(green)
S2: ...
reviewer (read-only, model khác) -> gate reviewer ✓ -> 05-review.md (APPROVE/CHANGES)
close-out: chạy lại test/lint/typecheck -> 06-final-report.md (bảng AC -> test -> bằng chứng)
```

## 6. Tự kiểm tra test của bạn có "thật" không (mutation spot-check)
Cố tình làm sai code: đổi `>` thành `>=`, bỏ một nhánh `if`, lệch một đơn vị trong vòng lặp.
Chạy test. **Nếu test vẫn xanh thì test đó yếu.** Các công cụ tự động: StrykerJS (JS/TS),
mutmut (Python), PIT (Java), cargo-mutants (Rust).

## 7. Khi nào không TDD (và phải nói rõ)
- Spike để thử API: làm nhanh, học xong thì **xóa**, rồi TDD bản thật.
- Chỉnh giao diện thuần thị giác: kiểm tra bằng ảnh chụp hoặc xem trực tiếp.
- File cấu hình hay code sinh tự động: test hành vi mà chúng tạo ra.

## 8. Lộ trình luyện tập đề xuất
1. Tuần 1: kata nhỏ (FizzBuzz, String Calculator, Bowling) bằng tay, chỉ để quen nhịp RED, GREEN, REFACTOR.
2. Tuần 2: sửa bug thật theo quy trình: test tái hiện bug, rồi sửa.
3. Tuần 3: dùng `playbook-tdd` cho một tính năng nhỏ. Tự đọc `01-spec.md` và bảng AC trong báo cáo cuối.
   Đây là chỗ con người kiểm soát chất lượng hiệu quả nhất.
4. Từ tuần 4: thêm mutation spot-check vào review và chạy `evals/scenarios.md` định kỳ.

Tài liệu cho agent (tiếng Anh, ngắn hơn): `skills/playbook-tdd/references/tdd-guide.md`.
