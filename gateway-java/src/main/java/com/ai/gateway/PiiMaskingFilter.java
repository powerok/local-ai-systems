package com.ai.gateway;

import org.springframework.cloud.gateway.filter.GatewayFilter;
import org.springframework.cloud.gateway.filter.factory.AbstractGatewayFilterFactory;
import org.springframework.core.io.buffer.DataBuffer;
import org.springframework.core.io.buffer.DataBufferUtils;
import org.springframework.http.HttpHeaders;
import org.springframework.http.server.reactive.ServerHttpRequest;
import org.springframework.http.server.reactive.ServerHttpRequestDecorator;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * 요청 본문의 PII(개인식별정보)를 마스킹하는 Gateway 필터
 *
 * 마스킹 대상:
 *   - 주민등록번호 : 900101-1234567 → [JUMIN]
 *   - 휴대폰 번호  : 010-1234-5678  → [PHONE]
 *   - 카드 번호    : 1234-5678-9012-3456 → [CARD]
 *   - 이메일       : user@example.com → [EMAIL]
 *
 * application.yml 에서 필터명 PiiMaskingFilter 로 참조한다.
 */
@Component
public class PiiMaskingFilter extends AbstractGatewayFilterFactory<PiiMaskingFilter.Config> {

    /** 마스킹 패턴 : 순서 보장을 위해 LinkedHashMap 사용 */
    private static final Map<Pattern, String> PII_PATTERNS = new LinkedHashMap<>();

    static {
        PII_PATTERNS.put(Pattern.compile("\\d{6}-[1-4]\\d{6}"),          "[JUMIN]");
        PII_PATTERNS.put(Pattern.compile("01[016789]-\\d{3,4}-\\d{4}"),  "[PHONE]");
        PII_PATTERNS.put(Pattern.compile("\\d{4}-\\d{4}-\\d{4}-\\d{4}"), "[CARD]");
        PII_PATTERNS.put(Pattern.compile("[\\w.+\\-]+@[\\w.\\-]+\\.[a-zA-Z]{2,}"), "[EMAIL]");
    }

    public PiiMaskingFilter() {
        super(Config.class);
    }

    /** application.yml 에서 설정할 수 있는 Config 클래스 (현재 설정값 없음) */
    public static class Config {
    }

    @Override
    public GatewayFilter apply(Config config) {
        return (exchange, chain) -> {
            ServerHttpRequest request = exchange.getRequest();

            // 요청 본문 전체를 읽어 PII 마스킹 후 재구성
            Mono<DataBuffer> bodyMono = DataBufferUtils.join(request.getBody());

            return bodyMono.flatMap(dataBuffer -> {
                // 1. 원본 본문 읽기
                byte[] bytes = new byte[dataBuffer.readableByteCount()];
                dataBuffer.read(bytes);
                DataBufferUtils.release(dataBuffer);
                String body = new String(bytes, StandardCharsets.UTF_8);

                // 2. PII 마스킹
                String maskedBody = mask(body);

                // 3. 마스킹된 본문으로 요청 재구성
                byte[] maskedBytes = maskedBody.getBytes(StandardCharsets.UTF_8);
                DataBuffer maskedBuffer = exchange.getResponse()
                        .bufferFactory()
                        .wrap(maskedBytes);

                ServerHttpRequest decoratedRequest = new ServerHttpRequestDecorator(request) {
                    @Override
                    public Flux<DataBuffer> getBody() {
                        return Flux.just(maskedBuffer);
                    }

                    @Override
                    public HttpHeaders getHeaders() {
                        HttpHeaders headers = new HttpHeaders();
                        headers.putAll(super.getHeaders());
                        headers.setContentLength(maskedBytes.length);
                        return headers;
                    }
                };

                return chain.filter(exchange.mutate().request(decoratedRequest).build());
            });
        };
    }

    /**
     * 텍스트에서 PII 패턴을 찾아 플레이스홀더로 치환한다.
     *
     * @param text 원본 텍스트
     * @return PII가 마스킹된 텍스트
     */
    private String mask(String text) {
        for (Map.Entry<Pattern, String> entry : PII_PATTERNS.entrySet()) {
            text = entry.getKey().matcher(text).replaceAll(entry.getValue());
        }
        return text;
    }
}
