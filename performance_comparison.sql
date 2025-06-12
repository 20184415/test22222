

-- 1. 반정규화 읽기 테이블 생성
CREATE TABLE IF NOT EXISTS articles_read_optimized (
    news_article_id UUID PRIMARY KEY,
    source_in VARCHAR(100),
    source_url VARCHAR(2048) NOT NULL,
    title VARCHAR(500) NOT NULL,
    published_date TIMESTAMP,
    summary TEXT NOT NULL,
    view_counts BIGINT DEFAULT 0,
    comment_counts BIGINT DEFAULT 0,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    
    -- 반정규화된 필드들
    interest_ids TEXT, -- 콤마로 구분된 UUID 문자열
    interest_names TEXT, -- 콤마로 구분된 관심사 이름
    keywords TEXT, -- 콤마로 구분된 키워드
    full_text_search TEXT, -- 검색 최적화용 통합 텍스트
    total_engagement_score DECIMAL(10,2), -- 종합 점수
    
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. 반정규화 테이블 인덱스 생성
CREATE INDEX IF NOT EXISTS idx_aro_published_date ON articles_read_optimized(published_date DESC);
CREATE INDEX IF NOT EXISTS idx_aro_source_in ON articles_read_optimized(source_in);
CREATE INDEX IF NOT EXISTS idx_aro_view_counts ON articles_read_optimized(view_counts DESC);
CREATE INDEX IF NOT EXISTS idx_aro_comment_counts ON articles_read_optimized(comment_counts DESC);
CREATE INDEX IF NOT EXISTS idx_aro_engagement_score ON articles_read_optimized(total_engagement_score DESC);
CREATE INDEX IF NOT EXISTS idx_aro_is_deleted ON articles_read_optimized(is_deleted);

-- 복합 인덱스
CREATE INDEX IF NOT EXISTS idx_aro_active_date_source ON articles_read_optimized(is_deleted, published_date DESC, source_in);
CREATE INDEX IF NOT EXISTS idx_aro_active_engagement ON articles_read_optimized(is_deleted, total_engagement_score DESC);

-- 전체 텍스트 검색 인덱스
CREATE INDEX IF NOT EXISTS idx_aro_full_text_gin ON articles_read_optimized USING gin(to_tsvector('english', full_text_search));

-- 3. 기존 테이블에도 최적화 인덱스 추가 (공정한 비교를 위해)
CREATE INDEX IF NOT EXISTS idx_na_active_date_source ON news_articles(is_deleted, published_date DESC, source_in) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_na_active_views ON news_articles(is_deleted, view_counts DESC) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_na_active_comments ON news_articles(is_deleted, comment_counts DESC) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_na_title_gin ON news_articles USING gin(to_tsvector('english', title));
CREATE INDEX IF NOT EXISTS idx_na_summary_gin ON news_articles USING gin(to_tsvector('english', summary));

-- 4. 반정규화 테이블 데이터 채우기
INSERT INTO articles_read_optimized (
    news_article_id, source_in, source_url, title, published_date, 
    summary, view_counts, comment_counts, is_deleted,
    interest_ids, interest_names, keywords, full_text_search, total_engagement_score
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
    COALESCE(interest_data.interest_ids, '') as interest_ids,
    COALESCE(interest_data.interest_names, '') as interest_names,
    COALESCE(keyword_data.keywords, '') as keywords,
    CONCAT(na.title, ' ', na.summary, ' ', COALESCE(keyword_data.keywords, '')) as full_text_search,
    (COALESCE(na.view_counts, 0) + (COALESCE(na.comment_counts, 0) * 5)) as total_engagement_score
FROM news_articles na
LEFT JOIN (
    SELECT 
        ina.news_article_id,
        STRING_AGG(DISTINCT i.interest_id::text, ',' ORDER BY i.interest_id::text) as interest_ids,
        STRING_AGG(DISTINCT i.name, ',' ORDER BY i.name) as interest_names
    FROM interests_news_articles ina
    JOIN interests i ON ina.interest_id = i.interest_id
    GROUP BY ina.news_article_id
) interest_data ON na.news_article_id = interest_data.news_article_id
LEFT JOIN (
    SELECT 
        ina.news_article_id,
        STRING_AGG(DISTINCT k.name, ' ' ORDER BY k.name) as keywords
    FROM interests_news_articles ina
    JOIN interests i ON ina.interest_id = i.interest_id
    JOIN interests_keywords ik ON i.interest_id = ik.interest_id
    JOIN keywords k ON ik.keyword_id = k.keyword_id
    GROUP BY ina.news_article_id
) keyword_data ON na.news_article_id = keyword_data.news_article_id
ON CONFLICT (news_article_id) DO NOTHING;

-- ===========================================
-- 성능 테스트 쿼리들
-- ===========================================

-- 테스트 1: 키워드 검색 + 날짜 범위 + 정렬
-- 기존 방식 (정규화된 테이블 + 조인)
EXPLAIN ANALYZE
SELECT 
    na.news_article_id,
    na.title,
    na.published_date,
    na.view_counts,
    na.comment_counts,
    na.source_in
FROM news_articles na
WHERE na.is_deleted = false
    AND na.published_date >= '2024-01-01'::timestamp
    AND na.published_date <= '2024-12-31'::timestamp
    AND (na.title ILIKE '%기술%' OR na.summary ILIKE '%기술%')
    AND na.source_in IN ('TechNews', 'ITWorld')
ORDER BY na.published_date DESC
LIMIT 20;

-- 반정규화 테이블 방식
EXPLAIN ANALYZE
SELECT 
    news_article_id,
    title,
    published_date,
    view_counts,
    comment_counts,
    source_in
FROM articles_read_optimized
WHERE is_deleted = false
    AND published_date >= '2024-01-01'::timestamp
    AND published_date <= '2024-12-31'::timestamp
    AND full_text_search ILIKE '%기술%'
    AND source_in IN ('TechNews', 'ITWorld')
ORDER BY published_date DESC
LIMIT 20;

-- 테스트 2: 관심사 기반 검색 + 인기도 정렬
-- 기존 방식 (복잡한 조인)
EXPLAIN ANALYZE
SELECT DISTINCT
    na.news_article_id,
    na.title,
    na.published_date,
    na.view_counts,
    na.comment_counts,
    (na.view_counts + na.comment_counts * 5) as engagement_score
FROM news_articles na
JOIN interests_news_articles ina ON na.news_article_id = ina.news_article_id
JOIN interests i ON ina.interest_id = i.interest_id
WHERE na.is_deleted = false
    AND i.name IN ('기술', '스포츠', '경제')
    AND na.published_date >= '2024-01-01'::timestamp
ORDER BY (na.view_counts + na.comment_counts * 5) DESC
LIMIT 20;

-- 반정규화 테이블 방식
EXPLAIN ANALYZE
SELECT 
    news_article_id,
    title,
    published_date,
    view_counts,
    comment_counts,
    total_engagement_score
FROM articles_read_optimized
WHERE is_deleted = false
    AND (interest_names LIKE '%기술%' OR interest_names LIKE '%스포츠%' OR interest_names LIKE '%경제%')
    AND published_date >= '2024-01-01'::timestamp
ORDER BY total_engagement_score DESC
LIMIT 20;

-- 테스트 3: 복합 조건 검색 (키워드 + 관심사 + 소스 + 날짜 + 정렬)
-- 기존 방식
EXPLAIN ANALYZE
SELECT DISTINCT
    na.news_article_id,
    na.title,
    na.published_date,
    na.view_counts,
    na.comment_counts,
    na.source_in
FROM news_articles na
LEFT JOIN interests_news_articles ina ON na.news_article_id = ina.news_article_id
LEFT JOIN interests i ON ina.interest_id = i.interest_id
LEFT JOIN interests_keywords ik ON i.interest_id = ik.interest_id
LEFT JOIN keywords k ON ik.keyword_id = k.keyword_id
WHERE na.is_deleted = false
    AND na.published_date >= '2024-06-01'::timestamp
    AND na.published_date <= '2024-12-31'::timestamp
    AND (na.title ILIKE '%AI%' OR na.summary ILIKE '%AI%' OR k.name ILIKE '%AI%')
    AND na.source_in = 'TechNews'
    AND i.name = '기술'
ORDER BY na.view_counts DESC
LIMIT 20;

-- 반정규화 테이블 방식
EXPLAIN ANALYZE
SELECT 
    news_article_id,
    title,
    published_date,
    view_counts,
    comment_counts,
    source_in
FROM articles_read_optimized
WHERE is_deleted = false
    AND published_date >= '2024-06-01'::timestamp
    AND published_date <= '2024-12-31'::timestamp
    AND full_text_search ILIKE '%AI%'
    AND source_in = 'TechNews'
    AND interest_names LIKE '%기술%'
ORDER BY view_counts DESC
LIMIT 20;

-- 테스트 4: 전체 텍스트 검색 성능
-- 기존 방식 (GIN 인덱스 활용)
EXPLAIN ANALYZE
SELECT 
    na.news_article_id,
    na.title,
    na.published_date,
    ts_rank(to_tsvector('english', na.title || ' ' || na.summary), plainto_tsquery('english', '인공지능 머신러닝')) as rank
FROM news_articles na
WHERE na.is_deleted = false
    AND to_tsvector('english', na.title || ' ' || na.summary) @@ plainto_tsquery('english', '인공지능 머신러닝')
ORDER BY ts_rank(to_tsvector('english', na.title || ' ' || na.summary), plainto_tsquery('english', '인공지능 머신러닝')) DESC
LIMIT 20;

-- 반정규화 테이블 방식
EXPLAIN ANALYZE
SELECT 
    news_article_id,
    title,
    published_date,
    ts_rank(to_tsvector('english', full_text_search), plainto_tsquery('english', '인공지능 머신러닝')) as rank
FROM articles_read_optimized
WHERE is_deleted = false
    AND to_tsvector('english', full_text_search) @@ plainto_tsquery('english', '인공지능 머신러닝')
ORDER BY ts_rank(to_tsvector('english', full_text_search), plainto_tsquery('english', '인공지능 머신러닝')) DESC
LIMIT 20;

-- ===========================================
-- 성능 측정 결과 분석용 쿼리
-- ===========================================

-- 인덱스 사용량 확인
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes 
WHERE tablename IN ('news_articles', 'articles_read_optimized')
ORDER BY tablename, idx_scan DESC;

-- 테이블 크기 비교
SELECT 
    tablename,
    pg_size_pretty(pg_total_relation_size(tablename::regclass)) as total_size,
    pg_size_pretty(pg_relation_size(tablename::regclass)) as table_size,
    pg_size_pretty(pg_total_relation_size(tablename::regclass) - pg_relation_size(tablename::regclass)) as index_size
FROM (VALUES ('news_articles'), ('articles_read_optimized')) as t(tablename);

-- 통계 정보 업데이트 (정확한 성능 측정을 위해)
ANALYZE news_articles;
ANALYZE articles_read_optimized;
ANALYZE interests;
ANALYZE interests_news_articles;
ANALYZE interests_keywords;
ANALYZE keywords; 