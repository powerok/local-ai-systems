# Spring Cloud Gateway Dockerfile
# Multi-stage build: Gradle 빌드 → JRE 실행

FROM gradle:8.5-jdk21 AS build
WORKDIR /app
# 의존성 캐싱을 위해 build 파일 먼저 복사
COPY build.gradle.kts settings.gradle.kts* ./
RUN gradle dependencies --no-daemon || true
# 소스 복사 및 빌드
COPY src ./src
RUN gradle bootJar --no-daemon -x test

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /app/build/libs/*.jar app.jar
ENTRYPOINT ["java", \
            "-Xmx700m", \
            "-Xms256m", \
            "-XX:+UseContainerSupport", \
            "-XX:MaxRAMPercentage=75.0", \
            "-jar", "app.jar"]
