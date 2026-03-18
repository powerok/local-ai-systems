package com.ai.rag.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * application.yml app.* 설정을 바인딩하는 프로퍼티 클래스
 */
@Getter
@Setter
@Component
@ConfigurationProperties(prefix = "app")
public class AppProperties {

    private Ollama ollama = new Ollama();
    private Milvus milvus = new Milvus();
    private Session session = new Session();
    private Agent agent = new Agent();

    @Getter @Setter
    public static class Ollama {
        private String url = "http://ollama:11434";
        private String model = "exaone";
        private int numPredict = 1024;
        private double temperature = 0.7;
        private int hydeNumPredict = 150;
        private double hydeTemperature = 0.3;
        private int agentNumPredict = 512;
        private double agentTemperature = 0.1;
        private int timeoutSeconds = 120;
    }

    @Getter @Setter
    public static class Milvus {
        private String host = "milvus";
        private int port = 19530;
        private String collection = "knowledge_base";
        private int topKDense = 15;
        private int topKHyde = 10;
        private int topNRerank = 5;
    }

    @Getter @Setter
    public static class Session {
        private int ttlSeconds = 7200;
        private int maxHistoryTurns = 8;
    }

    @Getter @Setter
    public static class Agent {
        private int maxSteps = 8;
    }
}
