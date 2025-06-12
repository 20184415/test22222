package com.part2.monew.service;

import com.part2.monew.entity.NewsArticle;
import com.part2.monew.entity.NewsArticleRead;
import com.part2.monew.repository.NewsArticleRepository;
import com.part2.monew.repository.NewsReadRepository;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class ReadTableSyncService {

    private static final Logger logger = LoggerFactory.getLogger(ReadTableSyncService.class);
    
    private final NewsArticleRepository newsArticleRepository;
    private final NewsReadRepository newsReadRepository;

    // 데이터 동기화 초기단계
    @Transactional
    public void syncWriteToReadTable(int chunkSize) {
        int pageNumber = 0;
        Page<NewsArticle> articlePage;
        int totalProcessed = 0;
        int totalSynced = 0;

        logger.info("데이터 동기화 시작 - 청크 크기: {}", chunkSize);

        do {
            logger.info("현재 페이지 번호: {}", pageNumber);
            Sort sort = Sort.by(Sort.Order.desc("createdAt"));
            Pageable pageable = PageRequest.of(pageNumber, chunkSize, sort);
            
            // 조인으로 실제 조회수/댓글수를 포함한 데이터 조회
            List<Object[]> articlesWithCounts = newsArticleRepository.findAllArticlesWithCounts(pageable);

            if (articlesWithCounts.isEmpty()) {
                logger.info("더 이상 처리할 기사가 없습니다.");
                break;
            }
            
            // Object[] 결과를 NewsArticleRead로 변환
            List<NewsArticleRead> readArticles = articlesWithCounts.stream()
                .map(this::convertToNewsArticleRead)
                .collect(Collectors.toList());

            // 중복 체크: 이미 동기화된 것들 제외
            Set<UUID> existingIds = readArticles.stream()
                .map(NewsArticleRead::getNewsArticleId)
                .collect(Collectors.toSet());
            
            Set<UUID> alreadySynced = newsReadRepository.findAllById(existingIds)
                .stream()
                .map(NewsArticleRead::getNewsArticleId)
                .collect(Collectors.toSet());

            // 새로운 것만 필터링
            List<NewsArticleRead> newReadArticles = readArticles.stream()
                .filter(article -> !alreadySynced.contains(article.getNewsArticleId()))
                .collect(Collectors.toList());

            if (!newReadArticles.isEmpty()) {
                newsReadRepository.saveAll(newReadArticles);
                totalSynced += newReadArticles.size();
                logger.info("페이지 {} 처리 완료: {} / {} 기사 동기화", 
                    pageNumber, newReadArticles.size(), articlesWithCounts.size());
            } else {
                logger.info("페이지 {} - 모든 기사가 이미 동기화됨", pageNumber);
            }
            
            totalProcessed += articlesWithCounts.size();
            
            // 1순위: 페이지 증가 (다음 페이지로 이동)
            pageNumber++;

            // 페이지 체크를 위해 일반 페이지 조회도 함께 사용
            articlePage = newsArticleRepository.findAll(pageable);

        } while (articlePage.hasNext()); // 1순위: 루프 종료 조건
        
        logger.info("데이터 동기화 완료 - 총 처리: {}, 동기화: {}", totalProcessed, totalSynced);
    }

    // Object[] 결과를 NewsArticleRead로 변환하는 헬퍼 메서드
    private NewsArticleRead convertToNewsArticleRead(Object[] result) {
        NewsArticle article = (NewsArticle) result[0];
        Long actualViewCount = ((Number) result[1]).longValue();
        Long actualCommentCount = ((Number) result[2]).longValue();
        
        // 실제 조회수/댓글수로 engagement score 계산
        Long engagementScore = actualViewCount + (actualCommentCount * 5);
        
        String fullSearchText = article.getTitle() + " " + 
                               (article.getSummary() != null ? article.getSummary() : "");
        
        return NewsArticleRead.builder()
                .newsArticleId(article.getId())
                .sourceIn(article.getSourceIn())
                .title(article.getTitle())
                .publishedDate(article.getPublishedDate())
                .summary(article.getSummary())
                .viewCounts(actualViewCount)  // 조인으로 가져온 실제 값
                .commentCounts(actualCommentCount)  // 조인으로 가져온 실제 값
                .isDeleted(article.isDeleted())
                .fullSearchText(fullSearchText)
                .engagementScore(engagementScore)  // 실제 값으로 계산
                .createdAt(article.getCreatedAt())
                .updatedAt(new Timestamp(System.currentTimeMillis()))
                .build();
    }
}