package com.ai.gateway;

import org.springframework.cloud.gateway.filter.ratelimit.KeyResolver;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import reactor.core.publisher.Mono;

@Configuration
public class RateLimiterConfig {

    /**
     * Rate Limit 키 결정 전략
     * Authorization 헤더의 Bearer JWT 토큰 마지막 16자를 키로 사용한다.
     * 헤더가 없으면 "anonymous" 를 사용한다.
     *
     * application.yml 의 key-resolver: "#{@userKeyResolver}" 와 매핑된다.
     */
    @Bean
    public KeyResolver userKeyResolver() {
        return exchange -> {
            String authHeader = exchange.getRequest()
                    .getHeaders()
                    .getFirst("Authorization");

            String key;
            if (authHeader != null && authHeader.startsWith("Bearer ")) {
                String token = authHeader.substring(7);
                // JWT 토큰 뒤 16자를 버킷 키로 사용
                key = token.length() > 16
                        ? token.substring(token.length() - 16)
                        : token;
                if (key.isBlank()) key = "anonymous";
            } else {
                key = "anonymous";
            }
            return Mono.just(key);
        };
    }
}
