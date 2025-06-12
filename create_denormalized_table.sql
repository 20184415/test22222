-- ===========================================
-- 반정규화 읽기 전용 테이블 생성 및 데이터 삽입
-- ===========================================

-- 1. 반정규화 읽기 전용 테이블 생성
DROP TABLE IF EXISTS articles_read_optimized;

CREATE TABLE articles_read_optimized (
    -- 기본 기사 정보
    news_article_id UUID PRIMARY KEY,
    source_in VARCHAR(100),
    source_url VARCHAR(2048),
    title VARCHAR(500),
    published_date TIMESTAMP,
    summary TEXT,
    view_counts BIGINT DEFAULT 0,
    comment_counts BIGINT DEFAULT 0,
    is_deleted BOOLEAN DEFAULT FALSE,
    
    -- 반정규화된 관심사 정보
    interest_ids TEXT, -- UUID들을 콤마로 구분
    interest_names TEXT, -- 관심사 이름들을 콤마로 구분
    
    -- 반정규화된 키워드 정보
    keywords TEXT, -- 키워드들을 콤마로 구분
    
    -- 검색 최적화용 통합 필드
    full_search_text TEXT, -- title + summary + keywords 통합
    
    -- 계산된 점수
    engagement_score BIGINT, -- view_counts + comment_counts * 5
    
    -- 메타 정보
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. 반정규화 테이블 인덱스 생성
CREATE INDEX idx_aro_published_date ON articles_read_optimized(published_date DESC);
CREATE INDEX idx_aro_source_in ON articles_read_optimized(source_in);
CREATE INDEX idx_aro_view_counts ON articles_read_optimized(view_counts DESC);
CREATE INDEX idx_aro_comment_counts ON articles_read_optimized(comment_counts DESC);
CREATE INDEX idx_aro_engagement_score ON articles_read_optimized(engagement_score DESC);
CREATE INDEX idx_aro_is_deleted ON articles_read_optimized(is_deleted);

-- 복합 인덱스
CREATE INDEX idx_aro_active_date_source ON articles_read_optimized(is_deleted, published_date DESC, source_in);
CREATE INDEX idx_aro_active_comments ON articles_read_optimized(is_deleted, comment_counts DESC);
CREATE INDEX idx_aro_active_engagement ON articles_read_optimized(is_deleted, engagement_score DESC);

-- 전체 텍스트 검색 인덱스
CREATE INDEX idx_aro_full_search_gin ON articles_read_optimized USING gin(to_tsvector('english', full_search_text));

-- 3. 기존 정규화 테이블 최적화 인덱스 (공정한 비교를 위해)
CREATE INDEX IF NOT EXISTS idx_na_active_date ON news_articles(is_deleted, published_date DESC) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_na_active_comments ON news_articles(is_deleted, comment_counts DESC) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_na_active_views ON news_articles(is_deleted, view_counts DESC) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_na_source_active ON news_articles(source_in, is_deleted) WHERE is_deleted = false;

-- 관련 테이블 인덱스
CREATE INDEX IF NOT EXISTS idx_ina_news_id ON interests_news_articles(news_article_id);
CREATE INDEX IF NOT EXISTS idx_ina_interest_id ON interests_news_articles(interest_id);
CREATE INDEX IF NOT EXISTS idx_ik_interest_id ON interests_keywords(interest_id);
CREATE INDEX IF NOT EXISTS idx_ik_keyword_id ON interests_keywords(keyword_id);

-- 4. 반정규화 테이블에 데이터 삽입
INSERT INTO articles_read_optimized (
    news_article_id, source_in, source_url, title, published_date, 
    summary, view_counts, comment_counts, is_deleted,
    interest_ids, interest_names, keywords, full_search_text, engagement_score
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
    
    -- 관심사 정보 집계
    COALESCE(interest_data.interest_ids, '') as interest_ids,
    COALESCE(interest_data.interest_names, '') as interest_names,
    
    -- 키워드 정보 집계
    COALESCE(keyword_data.keywords, '') as keywords,
    
    -- 전체 검색 텍스트
    CONCAT(
        na.title, ' ', 
        na.summary, ' ', 
        COALESCE(keyword_data.keywords, '')
    ) as full_search_text,
    
    -- 참여도 점수
    (COALESCE(na.view_counts, 0) + COALESCE(na.comment_counts, 0) * 5) as engagement_score
    
FROM news_articles na

-- 관심사 정보 조인
LEFT JOIN (
    SELECT 
        ina.news_article_id,
        STRING_AGG(DISTINCT i.interest_id::text, ',' ORDER BY i.interest_id::text) as interest_ids,
        STRING_AGG(DISTINCT i.name, ',' ORDER BY i.name) as interest_names
    FROM interests_news_articles ina
    JOIN interests i ON ina.interest_id = i.interest_id
    GROUP BY ina.news_article_id
) interest_data ON na.news_article_id = interest_data.news_article_id

-- 키워드 정보 조인  
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

-- 5. 통계 정보 업데이트
ANALYZE articles_read_optimized;
ANALYZE news_articles;
ANALYZE interests_news_articles;

-- 6. 데이터 확인
SELECT 
    'news_articles' as table_name,
    COUNT(*) as total_count,
    COUNT(*) FILTER (WHERE is_deleted = false) as active_count,
    AVG(view_counts) as avg_views,
    AVG(comment_counts) as avg_comments
FROM news_articles
UNION ALL
SELECT 
    'articles_read_optimized' as table_name,
    COUNT(*) as total_count,
    COUNT(*) FILTER (WHERE is_deleted = false) as active_count,
    AVG(view_counts) as avg_views,
    AVG(comment_counts) as avg_comments
FROM articles_read_optimized;

-- 7. 테이블 크기 비교
SELECT 
    'news_articles' as table_name,
    pg_size_pretty(pg_total_relation_size('news_articles'::regclass)) as total_size,
    pg_size_pretty(pg_relation_size('news_articles'::regclass)) as table_size,
    pg_size_pretty(pg_total_relation_size('news_articles'::regclass) - pg_relation_size('news_articles'::regclass)) as index_size
UNION ALL
SELECT 
    'articles_read_optimized' as table_name,
    pg_size_pretty(pg_total_relation_size('articles_read_optimized'::regclass)) as total_size,
    pg_size_pretty(pg_relation_size('articles_read_optimized'::regclass)) as table_size,
    pg_size_pretty(pg_total_relation_size('articles_read_optimized'::regclass) - pg_relation_size('articles_read_optimized'::regclass)) as index_size
UNION ALL
SELECT 
    'interests_news_articles' as table_name,
    pg_size_pretty(pg_total_relation_size('interests_news_articles'::regclass)) as total_size,
    pg_size_pretty(pg_relation_size('interests_news_articles'::regclass)) as table_size,
    pg_size_pretty(pg_total_relation_size('interests_news_articles'::regclass) - pg_relation_size('interests_news_articles'::regclass)) as index_size; 