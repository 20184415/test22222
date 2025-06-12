-- ===========================================
-- 기사 조회 성능 비교: 인덱스 vs 반정규화 테이블
-- 올인원 스크립트
-- ===========================================

-- STEP 1: 반정규화 테이블 생성
DROP TABLE IF EXISTS articles_read_optimized;

CREATE TABLE articles_read_optimized (
    news_article_id UUID PRIMARY KEY,
    source_in VARCHAR(100),
    title VARCHAR(500),
    published_date TIMESTAMP,
    summary TEXT,
    view_counts BIGINT DEFAULT 0,
    comment_counts BIGINT DEFAULT 0,
    is_deleted BOOLEAN DEFAULT FALSE,
    
    -- 반정규화된 필드들
    interest_names TEXT,
    keywords TEXT,
    full_search_text TEXT,
    engagement_score BIGINT
);

-- 정규화 테이블 인덱스 (조인 최적화 포함)
CREATE INDEX IF NOT EXISTS idx_na_published_date ON news_articles(published_date DESC) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_na_comment_counts ON news_articles(comment_counts DESC) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_na_view_counts ON news_articles(view_counts DESC) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_na_source_in ON news_articles(source_in) WHERE is_deleted = false;
-- 출처별 복합 인덱스 (출처 + 정렬 조건)
CREATE INDEX IF NOT EXISTS idx_na_source_published ON news_articles(source_in, published_date DESC) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_na_source_comments ON news_articles(source_in, comment_counts DESC) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_na_source_views ON news_articles(source_in, view_counts DESC) WHERE is_deleted = false;

-- 조인 테이블 인덱스 (관심사 기반 검색 최적화)
CREATE INDEX IF NOT EXISTS idx_ina_news_id ON interests_news_articles(news_article_id);
CREATE INDEX IF NOT EXISTS idx_ina_interest_id ON interests_news_articles(interest_id);
CREATE INDEX IF NOT EXISTS idx_interests_name ON interests(name);
CREATE INDEX IF NOT EXISTS idx_ik_interest_id ON interests_keywords(interest_id);
CREATE INDEX IF NOT EXISTS idx_ik_keyword_id ON interests_keywords(keyword_id);
CREATE INDEX IF NOT EXISTS idx_keywords_name ON keywords(name);

-- 반정규화 테이블 인덱스
CREATE INDEX idx_aro_published_date ON articles_read_optimized(published_date DESC) WHERE is_deleted = false;
CREATE INDEX idx_aro_comment_counts ON articles_read_optimized(comment_counts DESC) WHERE is_deleted = false;
CREATE INDEX idx_aro_view_counts ON articles_read_optimized(view_counts DESC) WHERE is_deleted = false;
CREATE INDEX idx_aro_engagement_score ON articles_read_optimized(engagement_score DESC) WHERE is_deleted = false;
CREATE INDEX idx_aro_source_in ON articles_read_optimized(source_in) WHERE is_deleted = false;
-- 출처별 복합 인덱스 (출처 + 정렬 조건)
CREATE INDEX idx_aro_source_published ON articles_read_optimized(source_in, published_date DESC) WHERE is_deleted = false;
CREATE INDEX idx_aro_source_comments ON articles_read_optimized(source_in, comment_counts DESC) WHERE is_deleted = false;
CREATE INDEX idx_aro_source_views ON articles_read_optimized(source_in, view_counts DESC) WHERE is_deleted = false;

INSERT INTO articles_read_optimized (
    news_article_id, source_in, title, published_date, 
    summary, view_counts, comment_counts, is_deleted,
    interest_names, keywords, full_search_text, engagement_score
)
SELECT 
    na.news_article_id,
    na.source_in,
    na.title,
    na.published_date,
    na.summary,
    na.view_counts,
    na.comment_counts,
    na.is_deleted,
    
    COALESCE(interest_data.interest_names, '') as interest_names,
    COALESCE(keyword_data.keywords, '') as keywords,
    CONCAT(na.title, ' ', na.summary) as full_search_text,
    (COALESCE(na.view_counts, 0) + COALESCE(na.comment_counts, 0) * 5) as engagement_score
    
FROM news_articles na
LEFT JOIN (
    SELECT 
        ina.news_article_id,
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
) keyword_data ON na.news_article_id = keyword_data.news_article_id;

-- STEP 4: 통계 업데이트
ANALYZE articles_read_optimized;
ANALYZE news_articles;

-- ===========================================
-- 성능 비교 테스트 (조회수순 역순 포함)
-- ===========================================

-- 테스트 1: 최신순 정렬
EXPLAIN (ANALYZE, BUFFERS)
SELECT news_article_id, title, published_date, view_counts
FROM news_articles
WHERE is_deleted = false
ORDER BY published_date DESC
LIMIT 20;

EXPLAIN (ANALYZE, BUFFERS)
SELECT news_article_id, title, published_date, view_counts
FROM articles_read_optimized
WHERE is_deleted = false
ORDER BY published_date DESC
LIMIT 20;

-- 테스트 2: 조회수순 역순 (높은 조회수부터)
EXPLAIN (ANALYZE, BUFFERS)
SELECT news_article_id, title, view_counts, published_date
FROM news_articles
WHERE is_deleted = false
ORDER BY view_counts DESC
LIMIT 20;

EXPLAIN (ANALYZE, BUFFERS)
SELECT news_article_id, title, view_counts, published_date
FROM articles_read_optimized
WHERE is_deleted = false
ORDER BY view_counts DESC
LIMIT 20;

-- 테스트 3: 댓글수순 역순
EXPLAIN (ANALYZE, BUFFERS)
SELECT news_article_id, title, comment_counts, published_date
FROM news_articles
WHERE is_deleted = false
ORDER BY comment_counts DESC
LIMIT 20;

EXPLAIN (ANALYZE, BUFFERS)
SELECT news_article_id, title, comment_counts, published_date
FROM articles_read_optimized
WHERE is_deleted = false
ORDER BY comment_counts DESC
LIMIT 20;


\echo '=== 테스트 1: 최신 기사 목록 조회 ==='

-- 정규화 테이블
EXPLAIN (ANALYZE, BUFFERS)
SELECT news_article_id, title, published_date, comment_counts
FROM news_articles
WHERE is_deleted = false
ORDER BY published_date DESC
LIMIT 20;
DISCARD ALL;
-- 반정규화 테이블
EXPLAIN (ANALYZE, BUFFERS)
SELECT news_article_id, title, published_date, comment_counts
FROM articles_read_optimized
WHERE is_deleted = false
ORDER BY published_date DESC
LIMIT 20;

--댓글 수 정렬

-- 정규화 테이블
EXPLAIN (ANALYZE, BUFFERS)
SELECT news_article_id, title, comment_counts, published_date
FROM news_articles
WHERE is_deleted = false
ORDER BY comment_counts DESC, published_date DESC
LIMIT 20;

-- 반정규화 테이블
EXPLAIN (ANALYZE, BUFFERS)
SELECT news_article_id, title, comment_counts, published_date
FROM articles_read_optimized
WHERE is_deleted = false
ORDER BY comment_counts DESC, published_date DESC
LIMIT 20;

\echo '=== 테스트 3: 관심사 기반 검색 ==='

-- 정규화 테이블 (조인)
EXPLAIN (ANALYZE, BUFFERS)
SELECT DISTINCT na.news_article_id, na.title, na.comment_counts
FROM news_articles na
JOIN interests_news_articles ina ON na.news_article_id = ina.news_article_id
JOIN interests i ON ina.interest_id = i.interest_id
WHERE na.is_deleted = false AND i.name IN ('기술', '스포츠')
ORDER BY na.comment_counts DESC
LIMIT 20;

-- 반정규화 테이블 (문자열 검색)
EXPLAIN (ANALYZE, BUFFERS)
SELECT news_article_id, title, comment_counts, interest_names
FROM articles_read_optimized
WHERE is_deleted = false 
AND (interest_names LIKE '%기술%' OR interest_names LIKE '%스포츠%')
ORDER BY comment_counts DESC
LIMIT 20;

\echo '=== 테스트 4: 참여도 점수 순 정렬 ==='

-- 정규화 테이블 (실시간 계산)
EXPLAIN (ANALYZE, BUFFERS)
SELECT news_article_id, title, (view_counts + comment_counts * 5) as score
FROM news_articles
WHERE is_deleted = false
ORDER BY (view_counts + comment_counts * 5) DESC
LIMIT 20;

-- 반정규화 테이블 (미리 계산됨)
EXPLAIN (ANALYZE, BUFFERS)
SELECT news_article_id, title, engagement_score
FROM articles_read_optimized
WHERE is_deleted = false
ORDER BY engagement_score DESC
LIMIT 20;

\echo '=== 테스트 5: 출처별 필터링 ==='

-- 정규화 테이블 (특정 출처)
EXPLAIN (ANALYZE, BUFFERS)
SELECT news_article_id, title, source_in, published_date
FROM news_articles
WHERE is_deleted = false AND source_in = 'CNN'
ORDER BY published_date DESC
LIMIT 20;

-- 반정규화 테이블 (특정 출처)
EXPLAIN (ANALYZE, BUFFERS)
SELECT news_article_id, title, source_in, published_date
FROM articles_read_optimized
WHERE is_deleted = false AND source_in = 'CNN'
ORDER BY published_date DESC
LIMIT 20;

\echo '=== 테스트 6: 여러 출처 조건 ==='

-- 정규화 테이블 (여러 출처 IN 절)
EXPLAIN (ANALYZE, BUFFERS)
SELECT news_article_id, title, source_in, comment_counts
FROM news_articles
WHERE is_deleted = false AND source_in IN ('CNN', 'BBC', 'Reuters')
ORDER BY comment_counts DESC
LIMIT 20;

-- 반정규화 테이블 (여러 출처 IN 절)
EXPLAIN (ANALYZE, BUFFERS)
SELECT news_article_id, title, source_in, comment_counts
FROM articles_read_optimized
WHERE is_deleted = false AND source_in IN ('CNN', 'BBC', 'Reuters')
ORDER BY comment_counts DESC
LIMIT 20;

\echo '=== 테스트 7: 출처별 + 조회수 정렬 조합 ==='

-- 정규화 테이블 (출처 필터링 + 조회수 정렬)
EXPLAIN (ANALYZE, BUFFERS)
SELECT news_article_id, title, source_in, view_counts
FROM news_articles
WHERE is_deleted = false AND source_in = 'BBC'
ORDER BY view_counts DESC, published_date DESC
LIMIT 20;

-- 반정규화 테이블 (출처 필터링 + 조회수 정렬)
EXPLAIN (ANALYZE, BUFFERS)
SELECT news_article_id, title, source_in, view_counts
FROM articles_read_optimized
WHERE is_deleted = false AND source_in = 'BBC'
ORDER BY view_counts DESC, published_date DESC
LIMIT 20;

-- ===========================================
-- 결과 분석
-- ===========================================

-- 테이블 크기 비교
SELECT 
    'news_articles' as table_name,
    pg_size_pretty(pg_total_relation_size('news_articles'::regclass)) as total_size
UNION ALL
SELECT 
    'articles_read_optimized' as table_name,
    pg_size_pretty(pg_total_relation_size('articles_read_optimized'::regclass)) as total_size; 