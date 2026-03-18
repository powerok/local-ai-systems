package com.ai.gateway

import org.springframework.cloud.gateway.filter.GatewayFilter
import org.springframework.cloud.gateway.filter.factory.AbstractGatewayFilterFactory
import org.springframework.core.io.buffer.DataBufferUtils
import org.springframework.http.server.reactive.ServerHttpRequestDecorator
import org.springframework.stereotype.Component
import reactor.core.publisher.Flux
import java.nio.charset.StandardCharsets

/**
 * 요청 본문에서 PII(개인식별정보)를 마스킹하는 Gateway 필터
 * 주민번호, 전화번호, 카드번호, 이메일을 플레이스홀더로 치환한다.
 */
@Component
class PiiMaskingFilter : AbstractGatewayFilterFactory<PiiMaskingFilter.Config>(Config::class.java) {

    class Config

    private val patterns = listOf(
        Regex("""\d{6}-[1-4]\d{6}""")          to "[JUMIN]",
        Regex("""01[016789]-\d{3,4}-\d{4}""")  to "[PHONE]",
        Regex("""\d{4}-\d{4}-\d{4}-\d{4}""")  to "[CARD]",
        Regex("""[\w.+-]+@[\w.-]+\.[a-zA-Z]{2,}""") to "[EMAIL]",
    )

    override fun apply(config: Config): GatewayFilter = GatewayFilter { exchange, chain ->
        val request = exchange.request

        DataBufferUtils.join(request.body).flatMap { dataBuffer ->
            // 요청 본문 읽기
            val bytes = ByteArray(dataBuffer.readableByteCount())
            dataBuffer.read(bytes)
            DataBufferUtils.release(dataBuffer)

            // PII 마스킹
            var body = String(bytes, StandardCharsets.UTF_8)
            patterns.forEach { (regex, replacement) ->
                body = regex.replace(body, replacement)
            }

            // 마스킹된 본문으로 요청 재구성
            val maskedBytes   = body.toByteArray(StandardCharsets.UTF_8)
            val bufferFactory = exchange.response.bufferFactory()
            val maskedBuffer  = bufferFactory.wrap(maskedBytes)

            val decoratedRequest = object : ServerHttpRequestDecorator(request) {
                override fun getBody() = Flux.just(maskedBuffer)
                override fun getHeaders() = mutate()
                    .header("Content-Length", maskedBytes.size.toString())
                    .build()
                    .headers
            }

            chain.filter(exchange.mutate().request(decoratedRequest).build())
        }
    }
}
