package com.ai.rag.etl;

import org.springframework.stereotype.Component;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * PII(개인식별정보) 마스킹 컴포넌트
 *
 * 마스킹 대상:
 *   JUMIN   - 주민등록번호  900101-1234567
 *   PHONE   - 휴대폰 번호   010-1234-5678
 *   CARD    - 카드 번호     1234-5678-9012-3456
 *   EMAIL   - 이메일        user@example.com
 *   ACCOUNT - 계좌 번호     110-12-345678
 */
@Component
public class PiiScrubber {

    private static final Map<String, Pattern> PII_PATTERNS = new LinkedHashMap<>();

    static {
        PII_PATTERNS.put("JUMIN",   Pattern.compile("\\d{6}-[1-4]\\d{6}"));
        PII_PATTERNS.put("PHONE",   Pattern.compile("01[016789]-\\d{3,4}-\\d{4}"));
        PII_PATTERNS.put("CARD",    Pattern.compile("\\d{4}-\\d{4}-\\d{4}-\\d{4}"));
        PII_PATTERNS.put("EMAIL",   Pattern.compile("[\\w.+\\-]+@[\\w.\\-]+\\.[a-zA-Z]{2,}"));
        PII_PATTERNS.put("ACCOUNT", Pattern.compile("\\d{3}-\\d{2}-\\d{6}"));
    }

    /**
     * 텍스트 내 PII를 [LABEL_N] 토큰으로 치환한다.
     *
     * @param text 원본 텍스트
     * @return ScrubResult (마스킹된 텍스트 + 토큰 역매핑)
     */
    public ScrubResult scrub(String text) {
        Map<String, String> tokenMap = new LinkedHashMap<>();

        for (Map.Entry<String, Pattern> entry : PII_PATTERNS.entrySet()) {
            String label = entry.getKey();
            Matcher matcher = entry.getValue().matcher(text);
            StringBuffer sb = new StringBuffer();
            int index = 1;
            while (matcher.find()) {
                String token = "[" + label + "_" + index + "]";
                tokenMap.put(token, matcher.group());
                matcher.appendReplacement(sb, Matcher.quoteReplacement(token));
                index++;
            }
            matcher.appendTail(sb);
            text = sb.toString();
        }
        return new ScrubResult(text, tokenMap);
    }

    /**
     * 마스킹된 토큰을 원본 PII 값으로 복원한다.
     */
    public String restore(String text, Map<String, String> tokenMap) {
        for (Map.Entry<String, String> entry : tokenMap.entrySet()) {
            text = text.replace(entry.getKey(), entry.getValue());
        }
        return text;
    }

    /** scrub() 반환 결과 */
    public record ScrubResult(String maskedText, Map<String, String> tokenMap) {}
}
