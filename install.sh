#!/bin/sh

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

# Hàm cài đặt 3proxy
install_3proxy() {
    echo "installing 3proxy"
    URL="https://raw.githubusercontent.com/ngochoaitn/multi_proxy_ipv6/main/3proxy-3proxy-0.8.6.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-3proxy-0.8.6
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cp ./scripts/rc.d/proxy.sh /etc/init.d/3proxy
    chmod +x /etc/init.d/3proxy
    chkconfig 3proxy on
    cd $WORKDIR
}

# Hàm để tạo file cấu hình cho 3proxy
gen_3proxy() {
    cat <<EOF
daemon
maxconn 1000
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

# Bắt đầu thực hiện script
echo "Installing apps"
yum -y install gcc net-tools bsdtar zip >/dev/null

install_3proxy

echo "working folder = /home/proxy-installer"
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir $WORKDIR && cd $_

# Tải ipv6.ini từ GitHub
download_ipv6_ini

# Đọc danh sách IPv6 từ file ipv6.ini
read_ipv6_list

# Lấy địa chỉ IP4
IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal IP = ${IP4}. External sub for IPv6 = ${IP6}"

# Thiết lập số lượng proxy bằng số IPv6 trong ipv6.ini
COUNT=${#ipv6_list[@]}

FIRST_PORT=10000
LAST_PORT=$(($FIRST_PORT + $COUNT - 1))

# Tạo dữ liệu proxy
gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x ${WORKDIR}/boot_*.sh /etc/rc.local

# Tạo file cấu hình cho 3proxy
gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

# Thêm script khởi động vào rc.local
cat >>/etc/rc.local <<EOF
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 10048
service 3proxy start
EOF

# Khởi động proxy
bash /etc/rc.local

# Tạo proxy file cho người dùng
gen_proxy_file_for_user

# Upload proxy file
upload_proxy
