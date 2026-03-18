# Spring Cloud Gateway (Java) Dockerfile
# Multi-stage build: Maven 빌드 → JRE 실행

# ── 1단계: Maven 빌드 ─────────────────────────────────────────
FROM maven:3.9.6-eclipse-temurin-21 AS build
WORKDIR /app

# 의존성 캐싱: pom.xml 먼저 복사 후 dependency 다운로드
COPY pom.xml .
RUN mvn dependency:go-offline -q

# 소스 복사 및 패키징 (테스트 생략)
COPY src ./src
RUN mvn package -DskipTests -q

# ── 2단계: 실행 이미지 ────────────────────────────────────────
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

COPY --from=build /app/target/gateway-*.jar app.jar

ENTRYPOINT ["java", \
            "-Xmx700m", \
            "-Xms256m", \
            "-XX:+UseContainerSupport", \
            "-XX:MaxRAMPercentage=75.0", \
            "-jar", "app.jar"]
