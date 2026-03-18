# RAG Server (Java) Dockerfile
# Multi-stage build: Maven 빌드 → JRE 실행

# ── 1단계: Maven 빌드 ─────────────────────────────────────────
FROM maven:3.9.6-eclipse-temurin-21 AS build
WORKDIR /app

# 의존성 캐싱
COPY pom.xml .
RUN mvn dependency:go-offline -q

# 소스 복사 및 패키징
COPY src ./src
RUN mvn package -DskipTests -q

# ── 2단계: 실행 이미지 ────────────────────────────────────────
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

COPY --from=build /app/target/rag-server-*.jar app.jar

ENTRYPOINT ["java", \
            "-Xmx3g", \
            "-Xms512m", \
            "-XX:+UseContainerSupport", \
            "-XX:MaxRAMPercentage=75.0", \
            "-jar", "app.jar"]
