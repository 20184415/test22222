

CREATE TABLE articles_read_optimized (
    news_article_id UUID PRIMARY KEY,
    source_in VARCHAR(100),
    source_url VARCHAR(2048) NOT NULL,
    title VARCHAR(500) NOT NULL,
    published_date TIMESTAMP,
    summary TEXT NOT NULL,
    view_counts BIGINT DEFAULT 0,
    comment_counts BIGINT DEFAULT 0,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    
    interest_ids TEXT,
    interest_names TEXT,
    
    keywords TEXT, -- 키워드들을 콤마로 구분된 문자열로 저장
    
    full_text_search TEXT,
    
    total_engagement_score DECIMAL(10,2),
    
    -- 타임스탬프
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- 원본 테이블과의 동기화를 위한 해시값
    data_hash VARCHAR(64) -- 원본 데이터 변경 감지용
);

-- 성능 최적화를 위한 인덱스들
CREATE INDEX idx_articles_read_published_date ON articles_read_optimized(published_date DESC);
CREATE INDEX idx_articles_read_source_in ON articles_read_optimized(source_in);
CREATE INDEX idx_articles_read_view_counts ON articles_read_optimized(view_counts DESC);
CREATE INDEX idx_articles_read_comment_counts ON articles_read_optimized(comment_counts DESC);
CREATE INDEX idx_articles_read_engagement_score ON articles_read_optimized(total_engagement_score DESC);
CREATE INDEX idx_articles_read_is_deleted ON articles_read_optimized(is_deleted);

-- 복합 인덱스들 (자주 함께 사용되는 조건들)
CREATE INDEX idx_articles_read_date_source ON articles_read_optimized(published_date DESC, source_in);
CREATE INDEX idx_articles_read_date_engagement ON articles_read_optimized(published_date DESC, total_engagement_score DESC);
CREATE INDEX idx_articles_read_active_date ON articles_read_optimized(is_deleted, published_date DESC);

-- 전체 텍스트 검색 인덱스 (PostgreSQL의 경우)
CREATE INDEX idx_articles_read_full_text_gin ON articles_read_optimized USING gin(to_tsvector('korean', full_text_search));

-- 관심사 검색을 위한 인덱스
CREATE INDEX idx_articles_read_interests ON articles_read_optimized USING gin(string_to_array(interest_ids, ','));

-- 반정규화 테이블 데이터 동기화를 위한 함수
CREATE OR REPLACE FUNCTION sync_articles_read_optimized()
RETURNS TRIGGER AS $$
BEGIN
    -- 새로운 기사 추가 또는 업데이트 시 반정규화 테이블에 반영
    INSERT INTO articles_read_optimized (
        news_article_id, source_in, source_url, title, published_date, 
        summary, view_counts, comment_counts, is_deleted,
        interest_ids, interest_names, keywords, full_text_search,
        total_engagement_score, data_hash
    )
    SELECT 
        na.news_article_id,
        na.source_in,
        na.source_url,
        na.title,
        na.published_date,
        na.summary,
        na.view_counts,
        na.comment_counts,
        na.is_deleted,
        COALESCE(
            STRING_AGG(DISTINCT i.interest_id::text, ',' ORDER BY i.interest_id::text), ''
        ) as interest_ids,
        COALESCE(
            STRING_AGG(DISTINCT i.name, ',' ORDER BY i.name), ''
        ) as interest_names,
        COALESCE(
            STRING_AGG(DISTINCT k.name, ',' ORDER BY k.name), ''
        ) as keywords,
        CONCAT(na.title, ' ', na.summary, ' ', 
            COALESCE(STRING_AGG(DISTINCT k.name, ' '), '')
        ) as full_text_search,
        (na.view_counts + (na.comment_counts * 5)) as total_engagement_score,
        MD5(CONCAT(na.source_url, na.title, na.summary, na.view_counts, na.comment_counts, na.is_deleted)) as data_hash
    FROM news_articles na
    LEFT JOIN interests_news_articles ina ON na.news_article_id = ina.news_article_id
    LEFT JOIN interests i ON ina.interest_id = i.interest_id
    LEFT JOIN interests_keywords ik ON i.interest_id = ik.interest_id
    LEFT JOIN keywords k ON ik.keyword_id = k.keyword_id
    WHERE na.news_article_id = NEW.news_article_id
    GROUP BY na.news_article_id, na.source_in, na.source_url, na.title, 
             na.published_date, na.summary, na.view_counts, na.comment_counts, na.is_deleted
    ON CONFLICT (news_article_id) DO UPDATE SET
        source_in = EXCLUDED.source_in,
        source_url = EXCLUDED.source_url,
        title = EXCLUDED.title,
        published_date = EXCLUDED.published_date,
        summary = EXCLUDED.summary,
        view_counts = EXCLUDED.view_counts,
        comment_counts = EXCLUDED.comment_counts,
        is_deleted = EXCLUDED.is_deleted,
        interest_ids = EXCLUDED.interest_ids,
        interest_names = EXCLUDED.interest_names,
        keywords = EXCLUDED.keywords,
        full_text_search = EXCLUDED.full_text_search,
        total_engagement_score = EXCLUDED.total_engagement_score,
        data_hash = EXCLUDED.data_hash,
        updated_at = CURRENT_TIMESTAMP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 트리거 생성
CREATE TRIGGER trigger_sync_articles_read_optimized
    AFTER INSERT OR UPDATE ON news_articles
    FOR EACH ROW
    EXECUTE FUNCTION sync_articles_read_optimized();




INSERT INTO news_articles (
    news_article_id,
    source_in,
    source_url,
    title,
    published_date,
    summary,
    view_counts,
    comment_counts,
    is_deleted,
    created_at,
    updated_at
)
SELECT
    gen_random_uuid(),                                            -- UUID (Postgres pgcrypto 확장 필요)
    (ARRAY['NAVER','DAUM','YTN'])[floor(random()*3+1)],          -- 무작위 출처
    'https://example.com/article/' || i,                         -- 예시 URL
    '더미 기사 제목 #' || i,                                     -- 제목
    now() - (floor(random()*30) || ' days')::interval,            -- 최근 30일 내 랜덤 날짜
    '이것은 테스트용 더미 요약문입니다. 기사의 주요 내용을 요약합니다. (번호: ' || i || ')',
    floor(random()*10000),                                       -- 조회 수 0~9999
    floor(random()*1000),                                        -- 댓글 수 0~999
    FALSE,                                                       -- 삭제 여부
    now() - (floor(random()*30) || ' days')::interval,            -- 생성 일시
    now() - (floor(random()*30) || ' days')::interval             -- 수정 일시
FROM generate_series(1,10000) AS s(i);

