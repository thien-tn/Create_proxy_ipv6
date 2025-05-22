#!/usr/bin/env bash

# Hàm để tải file ipv6.ini từ GitHub
download_ipv6_ini() {
    echo "Downloading ipv6.ini from GitHub..."
    wget -O ipv6.ini https://raw.githubusercontent.com/thien-tn/Create_proxy_ipv6/main/ipv6.ini
    if [ ! -f "./ipv6.ini" ]; then
        echo "Failed to download ipv6.ini from GitHub. Exiting."
        exit 1
    fi
}

# Hàm để đọc danh sách IPv6 từ file ipv6.ini
read_ipv6_list() {
    if [ ! -f "./ipv6.ini" ]; then
        echo "ipv6.ini not found in $(pwd)! Exiting."
        exit 1
    fi
    mapfile -t ipv6_list < ipv6.ini
    echo "Found ${#ipv6_list[@]} IPv6 addresses in ipv6.ini"
}

# Hàm random chuỗi
random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

# Hàm để phát hiện hệ điều hành
detect_os() {
    if [ -f /etc/os-release ]; then
        # freedesktop.org and systemd
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        # linuxbase.org
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        # Một số bản phân phối sử dụng /etc/lsb-release
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        # Debian/Ubuntu/etc.
        OS=Debian
        VER=$(cat /etc/debian_version)
    else
        # Phương pháp sao lưu
        OS=$(uname -s)
        VER=$(uname -r)
    fi

    # Chuyển đổi sang chữ thường để dễ so sánh
    OS=$(echo "$OS" | tr '[:upper:]' '[:lower:]')
    echo "Detected OS: $OS, Version: $VER"
}

# Hàm cài đặt 3proxy với phiên bản mới
install_3proxy() {
    echo "Installing 3proxy version 0.9.4"
    VERSION="0.9.4"
    wget --no-check-certificate -O 3proxy-${VERSION}.tar.gz https://github.com/z3APA3A/3proxy/archive/${VERSION}.tar.gz
    tar xzf 3proxy-${VERSION}.tar.gz
    cd 3proxy-${VERSION}
    make -f Makefile.Linux
    mkdir -p /etc/3proxy/{bin,logs,stat}
    mv bin/3proxy /etc/3proxy/bin/
    
    # Thiết lập service dựa vào hệ điều hành
    if [[ "$OS" == *"ubuntu"* ]] || [[ "$OS" == *"debian"* ]]; then
        cp scripts/3proxy.service /lib/systemd/system/
        systemctl daemon-reload
        systemctl enable 3proxy
    else
        cp scripts/3proxy.service /etc/init.d/3proxy
        chkconfig 3proxy on
    fi
    
    cd $WORKDIR
}

# Hàm để tạo file cấu hình cho 3proxy
gen_3proxy() {
    cat <<EOF
daemon
maxconn 2000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong

users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})

$(awk -F "/" '{print "auth strong\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

# Hàm để tạo proxy file cho người dùng
gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

# Hàm để upload proxy file
upload_proxy() {
    local PASS=$(random)
    zip --password $PASS proxy.zip proxy.txt
    URL=$(curl -s --upload-file proxy.zip https://bashupload.com/proxy.zip)

    echo "Proxy is ready! Format IP:PORT:LOGIN:PASS"
    echo "Download zip archive from: ${URL}"
    echo "Password: ${PASS}"
}

# Hàm để tạo dữ liệu proxy từ danh sách IPv6
gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "usr$(random)/pass$(random)/$IP4/$port/${ipv6_list[$(expr $port - $FIRST_PORT)]}"
    done
}

# Hàm để tạo iptables rule
gen_iptables() {
    cat <<EOF
    $(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA}) 
EOF
}

# Hàm để thiết lập IPv6 trên interface
gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

# Kiểm tra quyền root
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

# Phát hiện hệ điều hành
detect_os

# Bắt đầu thực hiện script
echo "Installing required packages..."
if [[ "$OS" == *"ubuntu"* ]] || [[ "$OS" == *"debian"* ]]; then
    apt-get update
    apt-get -y install gcc net-tools bsdtar zip make git wget curl >/dev/null
else
    yum -y install gcc net-tools bsdtar zip make git wget curl >/dev/null
fi

install_3proxy

echo "working folder = /home/proxy-installer"
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $_

# Tải ipv6.ini từ GitHub
download_ipv6_ini

# Đọc danh sách IPv6 từ file ipv6.ini
read_ipv6_list

# Lấy địa chỉ IP4 và IP6
IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal IP = ${IP4}. External sub for IPv6 = ${IP6}"

# Thiết lập số lượng proxy bằng số IPv6 trong ipv6.ini
COUNT=${#ipv6_list[@]}

FIRST_PORT=10000
LAST_PORT=$(($FIRST_PORT + $COUNT - 1))

# Tạo dữ liệu proxy và script khởi động
gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x ${WORKDIR}/boot_*.sh /etc/rc.local

# Tạo file cấu hình cho 3proxy
gen_3proxy >/etc/3proxy/3proxy.cfg

# Tạo thư mục logs
mkdir -p /var/log/3proxy/

# Thêm script khởi động vào rc.local
if [[ "$OS" == *"ubuntu"* ]] || [[ "$OS" == *"debian"* ]]; then
    # Đảm bảo rc.local tồn tại và có quyền thực thi trên Ubuntu
    if [ ! -f /etc/rc.local ]; then
        echo '#!/bin/sh -e' > /etc/rc.local
        echo 'exit 0' >> /etc/rc.local
        chmod +x /etc/rc.local
        
        # Tạo service cho rc.local nếu chưa có
        if [ ! -f /lib/systemd/system/rc-local.service ]; then
            cat > /lib/systemd/system/rc-local.service <<EOF
[Unit]
Description=/etc/rc.local Compatibility
ConditionPathExists=/etc/rc.local

[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99

[Install]
WantedBy=multi-user.target
EOF
            systemctl enable rc-local
        fi
    fi
fi

cat >>/etc/rc.local <<EOF
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 65535
/etc/3proxy/bin/3proxy /etc/3proxy/3proxy.cfg
EOF

# Khởi động proxy
bash /etc/rc.local

# Tạo proxy file cho người dùng
gen_proxy_file_for_user

# Upload proxy file
upload_proxy
