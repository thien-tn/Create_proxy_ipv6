# multi_proxy_ipv6
Tạo hàng loạt proxy ipv6 từ 1 ipv4. Chú ý: Các trang web không phân giải được ipv6 sẽ không truy cập được qua proxy ipv6

## Yêu cầu
- Centos 7
- Ipv6 \64

## Các bước cài đặt
[Video chi tiết]: https://youtu.be/YNL61nuh4nc, sử dụng Centos (thuê tại vultr) để cài đặt

- Bước 1. Chạy lệnh trên CentOS: sudo yum install curl

- Bước 2. Chạy lệnh trên CentOS: `bash <(curl -s "https://raw.githubusercontent.com/thien-tn/Create_proxy_ipv6/main/install.sh")`

- Bước 3: Tải file `proxy.zip`, cấu trúc proxy: `IP4:PORT:LOGIN:PASS`
