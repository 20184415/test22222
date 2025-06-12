-- ===========================================
-- 성능 테스트용 더미 데이터 생성 스크립트
-- ===========================================

-- 1. 기존 테스트 데이터 정리 (필요시)
-- TRUNCATE TABLE articles_read_optimized CASCADE;
-- DELETE FROM interests_news_articles;
-- DELETE FROM interests_keywords;
-- DELETE FROM news_articles WHERE title LIKE 'Test Article%';
-- DELETE FROM interests WHERE name LIKE 'Test Interest%';
-- DELETE FROM keywords WHERE name LIKE 'Test Keyword%';

-- 2. 관심사 더미 데이터 생성 (50개)
INSERT INTO interests (interest_id, name, subscriber_counts) 
SELECT 
    gen_random_uuid(),
    'Test Interest ' || i || ' - ' || 
    (ARRAY['기술', '스포츠', '경제', '정치', '문화', '과학', '건강', '여행', '음식', '교육'])[((i-1) % 10) + 1],
    floor(random() * 10000 + 100)::integer
FROM generate_series(1, 50) i;

-- 3. 키워드 더미 데이터 생성 (200개)
INSERT INTO keywords (keyword_id, name)
SELECT 
    gen_random_uuid(),
    'Test Keyword ' || i || ' - ' ||
    (ARRAY[
        'AI', '머신러닝', '블록체인', '클라우드', '빅데이터', 
        '축구', '야구', '농구', '올림픽', '월드컵',
        '주식', '부동산', '금리', '환율', '투자',
        '선거', '정책', '국정감사', '외교', '통일',
        '영화', '음악', '전시회', '페스티벌', '드라마',
        '우주', '의학', '환경', '에너지', '로봇',
        '다이어트', '운동', '영양', '병원', '약품',
        '해외여행', '국내여행', '호텔', '항공', '맛집'
    ])[((i-1) % 30) + 1]
FROM generate_series(1, 200) i;

-- 4. 관심사-키워드 매핑 (각 관심사당 3-7개 키워드)
INSERT INTO interests_keywords (interest_keyword_id, interest_id, keyword_id)
SELECT 
    gen_random_uuid(),
    i.interest_id,
    k.keyword_id
FROM interests i
CROSS JOIN LATERAL (
    SELECT keyword_id 
    FROM keywords k 
    ORDER BY random() 
    LIMIT floor(random() * 5 + 3)::integer
) k
WHERE i.name LIKE 'Test Interest%';

-- 5. 뉴스 기사 더미 데이터 생성 (100,000건)
INSERT INTO news_articles (
    news_article_id, source_in, source_url, title, published_date, 
    summary, view_counts, comment_counts, is_deleted
)
SELECT 
    gen_random_uuid(),
    (ARRAY['TechNews', 'ITWorld', 'SportsDaily', 'EconomyToday', 'PoliticsNow', 
           'CultureLife', 'ScienceWeekly', 'HealthNews', 'TravelGuide', 'FoodieNews'])[((i-1) % 10) + 1],
    'https://example.com/article/' || i,
    'Test Article ' || i || ' - ' ||
    (ARRAY[
        '인공지능이 바꾸는 미래', '스포츠 경기 결과 분석', '경제 동향 전망',
        '정치 정책 변화', '문화 행사 소개', '과학 기술 발전',
        '건강 관리 팁', '여행 추천 코스', '맛집 탐방기', '교육 제도 개선',
        '블록체인 기술 동향', '머신러닝 활용 사례', '클라우드 서비스 비교',
        '빅데이터 분석 결과', 'IoT 기기 리뷰', '사이버 보안 이슈',
        '스타트업 투자 소식', '부동산 시장 분석', '주식 투자 전략',
        '환경 보호 활동'
    ])[((i-1) % 20) + 1],
    -- 최근 2년간의 랜덤한 날짜
    timestamp '2023-01-01' + (random() * (timestamp '2024-12-31' - timestamp '2023-01-01')),
    'Test Summary ' || i || ' - 이것은 테스트용 기사 요약입니다. ' ||
    'Lorem ipsum dolor sit amet, consectetur adipiscing elit. ' ||
    'Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. ' ||
    'Ut enim ad minim veniam, quis nostrud exercitation. ' ||
    repeat('추가 텍스트 내용 ', floor(random() * 10 + 1)::integer),
    floor(random() * 50000)::bigint, -- 조회수
    floor(random() * 1000)::bigint,  -- 댓글수
    (random() < 0.05) -- 5% 확률로 삭제된 기사
FROM generate_series(1, 100000) i;

-- 6. 관심사-기사 매핑 (각 기사당 1-3개 관심사)
INSERT INTO interests_news_articles (interest_news_article_id, interest_id, news_article_id)
SELECT DISTINCT
    gen_random_uuid(),
    i.interest_id,
    na.news_article_id
FROM news_articles na
CROSS JOIN LATERAL (
    SELECT interest_id 
    FROM interests i 
    WHERE i.name LIKE 'Test Interest%'
    ORDER BY random() 
    LIMIT floor(random() * 3 + 1)::integer
) i
WHERE na.title LIKE 'Test Article%'
AND random() < 0.8; -- 80% 기사에만 관심사 매핑

-- 7. 사용자 더미 데이터 (1000명)
INSERT INTO users (user_id, nickname, email, password, active)
SELECT 
    gen_random_uuid(),
    'TestUser' || i,
    'testuser' || i || '@example.com',
    'password123',
    (random() < 0.95) -- 95% 활성 사용자
FROM generate_series(1, 1000) i;

-- 8. 댓글 더미 데이터 (기사당 평균 10개)
INSERT INTO comments_managements (
    comment_management_id, user_id, news_article_id, content, like_count, active
)
SELECT 
    gen_random_uuid(),
    (SELECT user_id FROM users ORDER BY random() LIMIT 1),
    na.news_article_id,
    'Test Comment ' || floor(random() * 1000) || ' - ' ||
    (ARRAY[
        '좋은 기사네요!', '정보 감사합니다.', '더 자세한 내용이 궁금해요.',
        '다른 의견도 있을 것 같은데요.', '유익한 정보였습니다.',
        '이런 관점도 있군요.', '추가 질문이 있습니다.', '공감됩니다.',
        '참고할게요.', '도움이 되었어요.'
    ])[floor(random() * 10 + 1)],
    floor(random() * 100)::integer,
    (random() < 0.95)
FROM news_articles na
CROSS JOIN generate_series(1, floor(random() * 20 + 1)::integer)
WHERE na.title LIKE 'Test Article%'
AND random() < 0.3; -- 30% 기사에 댓글

-- 9. 기사의 댓글 수 업데이트 (실제 댓글 수 반영)
UPDATE news_articles SET comment_counts = (
    SELECT COUNT(*)
    FROM comments_managements cm
    WHERE cm.news_article_id = news_articles.news_article_id
    AND cm.active = true
)
WHERE title LIKE 'Test Article%';

-- 10. 통계 정보 업데이트
ANALYZE news_articles;
ANALYZE interests;
ANALYZE keywords;
ANALYZE interests_news_articles;
ANALYZE interests_keywords;
ANALYZE comments_managements;
ANALYZE users;

-- ===========================================
-- 데이터 생성 결과 확인
-- ===========================================

-- 생성된 데이터 통계
SELECT 
    'news_articles' as table_name,
    COUNT(*) as total_count,
    COUNT(*) FILTER (WHERE title LIKE 'Test Article%') as test_data_count,
    AVG(view_counts) as avg_views,
    AVG(comment_counts) as avg_comments
FROM news_articles
UNION ALL
SELECT 
    'interests' as table_name,
    COUNT(*) as total_count,
    COUNT(*) FILTER (WHERE name LIKE 'Test Interest%') as test_data_count,
    AVG(subscriber_counts) as avg_subscribers,
    NULL
FROM interests
UNION ALL
SELECT 
    'keywords' as table_name,
    COUNT(*) as total_count,
    COUNT(*) FILTER (WHERE name LIKE 'Test Keyword%') as test_data_count,
    NULL,
    NULL
FROM keywords
UNION ALL
SELECT 
    'interests_news_articles' as table_name,
    COUNT(*) as total_count,
    COUNT(*) as test_data_count,
    NULL,
    NULL
FROM interests_news_articles ina
JOIN news_articles na ON ina.news_article_id = na.news_article_id
WHERE na.title LIKE 'Test Article%'
UNION ALL
SELECT 
    'comments_managements' as table_name,
    COUNT(*) as total_count,
    COUNT(*) as test_data_count,
    AVG(like_count) as avg_likes,
    NULL
FROM comments_managements cm
JOIN news_articles na ON cm.news_article_id = na.news_article_id
WHERE na.title LIKE 'Test Article%';

-- 날짜별 기사 분포 확인
SELECT 
    DATE_TRUNC('month', published_date) as month,
    COUNT(*) as article_count
FROM news_articles 
WHERE title LIKE 'Test Article%'
GROUP BY DATE_TRUNC('month', published_date)
ORDER BY month;

-- 소스별 기사 분포 확인
SELECT 
    source_in,
    COUNT(*) as article_count,
    AVG(view_counts) as avg_views,
    AVG(comment_counts) as avg_comments
FROM news_articles 
WHERE title LIKE 'Test Article%'
GROUP BY source_in
ORDER BY article_count DESC; 