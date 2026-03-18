# API Gateway (Java + Maven)

> Spring Cloud Gateway — JWT 인증 · Rate Limiting · PII 필터  
> 언어: Java 21 | 빌드: Maven 3.9 | 프레임워크: Spring Boot 3.2

---

## 프로젝트 구조

```
gateway/
├── Dockerfile
├── pom.xml
└── src/main/
    ├── java/com/ai/gateway/
    │   ├── GatewayApplication.java     # 진입점
    │   ├── SecurityConfig.java         # JWT 인증 설정
    │   ├── RateLimiterConfig.java      # Rate Limit 키 전략
    │   └── PiiMaskingFilter.java       # PII 마스킹 필터
    └── resources/
        └── application.yml             # 라우팅 + Redis + OAuth2 설정
```

---

## 라우팅 규칙

| 외부 경로 | 내부 경로 | Rate Limit |
|----------|---------|------------|
| `POST /api/rag/**` | `POST /rag/**` → `rag-server:8080` | 10 req/s, burst 20 |
| `POST /api/agent/**` | `POST /agent/**` → `rag-server:8080` | 5 req/s, burst 10 |
| `GET /actuator/health` | (자체) | 인증 불필요 |

---

## 로컬 빌드 및 실행

```bash
# Maven으로 빌드
mvn clean package -DskipTests

# JAR 직접 실행
java -jar target/gateway-1.0.0.jar

# Docker로 실행
docker build -t ai-gateway .
docker run -p 8090:8090 \
  -e SPRING_REDIS_HOST=localhost \
  -e SPRING_REDIS_PASSWORD=changeme \
  ai-gateway
```

---

## 주요 컴포넌트 설명

### SecurityConfig
- `/actuator/health`, `/actuator/info` 만 인증 없이 허용
- 나머지 요청은 Bearer JWT 필수
- `spring.security.oauth2.resourceserver.jwt.jwk-set-uri` 로 JWK 검증

### RateLimiterConfig
- JWT 토큰 뒤 16자를 Redis Rate Limit 버킷 키로 사용
- Authorization 헤더 없을 시 `anonymous` 키 사용

### PiiMaskingFilter
- 요청 본문에서 주민번호·전화·카드·이메일 마스킹
- `[JUMIN]`, `[PHONE]`, `[CARD]`, `[EMAIL]` 플레이스홀더로 치환
- WebFlux 비동기 스트림 처리 (ServerHttpRequestDecorator)

---

## 개발 환경에서 JWT 없이 테스트

`SecurityConfig.java` 의 `authorizeExchange` 를 아래와 같이 수정:

```java
.authorizeExchange(exchanges -> exchanges
    .anyExchange().permitAll()  // 개발 전용 — 운영에서는 반드시 제거
)
```
