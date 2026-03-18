package com.ai.rag.config;

import io.milvus.client.MilvusServiceClient;
import io.milvus.param.ConnectParam;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Slf4j
@Configuration
@RequiredArgsConstructor
public class MilvusConfig {

    private final AppProperties props;

    @Bean
    public MilvusServiceClient milvusServiceClient() {
        ConnectParam connectParam = ConnectParam.newBuilder()
                .withHost(props.getMilvus().getHost())
                .withPort(props.getMilvus().getPort())
                .build();

        MilvusServiceClient client = new MilvusServiceClient(connectParam);
        log.info("Milvus 연결 완료: {}:{}", props.getMilvus().getHost(), props.getMilvus().getPort());
        return client;
    }
}
