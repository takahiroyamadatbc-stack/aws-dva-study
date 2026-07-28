#!/bin/bash
# EC2起動時に一度だけ実行される。nginxをインストールし、
# X-Forwarded-Forヘッダーを別ログに記録する設定を追加する。
dnf install -y nginx

cat > /etc/nginx/conf.d/xff-log.conf <<'EOF'
log_format xff_log '$time_local remote_addr=$remote_addr x_forwarded_for=$http_x_forwarded_for request="$request"';
access_log /var/log/nginx/xff-access.log xff_log;
EOF

systemctl enable nginx
systemctl start nginx
