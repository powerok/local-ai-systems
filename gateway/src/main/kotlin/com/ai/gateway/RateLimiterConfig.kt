package com.ai.gateway

import org.springframework.cloud.gateway.filter.ratelimit.KeyResolver
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import reactor.core.publisher.Mono

@Configuration
class RateLimiterConfig {

    /**
     * JWT sub claim 뒤 16자를 Rate Limit 키로 사용한다.
     * Authorization 헤더가 없으면 "anonymous"를 사용한다.
     */
    @Bean
    fun userKeyResolver(): KeyResolver = KeyResolver { exchange ->
        val authHeader = exchange.request.headers.getFirst("Authorization")
        val key = authHeader
            ?.removePrefix("Bearer ")
            ?.takeLast(16)
            ?.ifBlank { "anonymous" }
            ?: "anonymous"
        Mono.just(key)
    }
}
