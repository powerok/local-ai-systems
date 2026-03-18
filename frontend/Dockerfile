# ── Stage 1: Flutter Web 빌드 ──────────────────────────────
FROM ghcr.io/cirruslabs/flutter:3.19.0 AS builder

WORKDIR /app

# 의존성 설치
COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

# 소스 복사 및 빌드
COPY . .
RUN flutter build web \
    --release \
    --web-renderer canvaskit \
    --dart-define=FLUTTER_WEB_USE_SKIA=true

# ── Stage 2: Nginx 서빙 ─────────────────────────────────────
FROM nginx:1.25-alpine

# Flutter 빌드 결과물 복사
COPY --from=builder /app/build/web /usr/share/nginx/html

# Nginx 설정 복사
COPY nginx/nginx.conf /etc/nginx/conf.d/default.conf

# 기본 nginx.conf에서 default_type 설정
RUN echo 'user nginx; \
worker_processes auto; \
error_log /var/log/nginx/error.log warn; \
pid /var/run/nginx.pid; \
events { worker_connections 1024; } \
http { \
    include /etc/nginx/mime.types; \
    default_type application/octet-stream; \
    sendfile on; \
    keepalive_timeout 65; \
    include /etc/nginx/conf.d/*.conf; \
}' > /etc/nginx/nginx.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
