package com.part2.monew.entity;

import jakarta.persistence.*;
import lombok.*;
import java.sql.Timestamp;
import java.util.UUID;

@Entity
@Table(name = "articles_read_optimized", indexes = {
    @Index(name = "idx_engagement_score_desc", columnList = "engagement_score DESC"),
    @Index(name = "idx_view_counts_desc", columnList = "view_counts DESC"),
    @Index(name = "idx_comment_counts_desc", columnList = "comment_counts DESC"),
    @Index(name = "idx_published_date_desc", columnList = "published_date DESC"),
    @Index(name = "idx_source_in", columnList = "source_in"),
    @Index(name = "idx_full_search_text", columnList = "full_search_text")
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class NewsArticleRead {

    @Id
    @Column(name = "news_article_id")
    private UUID newsArticleId;

    @Column(name = "source_in", length = 100)
    private String sourceIn;

    @Column(name = "title", nullable = false, length = 1000)
    private String title;

    @Column(name = "published_date", nullable = false)
    private Timestamp publishedDate;

    @Column(name = "summary", columnDefinition = "TEXT")
    private String summary;

    @Column(name = "view_counts")
    @Builder.Default
    private Long viewCounts = 0L;

    @Column(name = "comment_counts")
    @Builder.Default
    private Long commentCounts = 0L;

    @Column(name = "is_deleted")
    @Builder.Default
    private Boolean isDeleted = false;

    @Column(name = "full_search_text", columnDefinition = "TEXT")
    private String fullSearchText;

    @Column(name = "engagement_score")
    @Builder.Default
    private Long engagementScore = 0L;

    @Column(name = "created_at", nullable = false)
    private Timestamp createdAt;

    @Column(name = "updated_at")
    private Timestamp updatedAt;

    public static NewsArticleRead fromNewsArticle(NewsArticle newsArticle) {
        String fullSearchText = newsArticle.getTitle() + " " + 
                                (newsArticle.getSummary() != null ? newsArticle.getSummary() : "");
        
        Long viewCounts = newsArticle.getViewCount() != null ? newsArticle.getViewCount() : 0L;
        Long commentCounts = newsArticle.getCommentCount() != null ? newsArticle.getCommentCount() : 0L;
        Long engagementScore = viewCounts + (commentCounts * 5);
        
        return NewsArticleRead.builder()
                .newsArticleId(newsArticle.getId())
                .sourceIn(newsArticle.getSourceIn())
                .title(newsArticle.getTitle())
                .publishedDate(newsArticle.getPublishedDate())
                .summary(newsArticle.getSummary())
                .viewCounts(viewCounts)
                .commentCounts(commentCounts)
                .isDeleted(newsArticle.isDeleted())
                .fullSearchText(fullSearchText)
                .engagementScore(engagementScore)
                .createdAt(newsArticle.getCreatedAt())
                .updatedAt(new Timestamp(System.currentTimeMillis()))
                .build();
    }
}
