package com.part2.monew.dto;

import java.sql.Timestamp;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.RequestParam;

public record RequestCursorDto(

    @RequestParam(value = "orderBy", defaultValue = "publishDate")
        String orderBy,

    @RequestParam(value = "direction", defaultValue = "DESC")
    String direction,

    @RequestParam(value = "cursor", required = false)
    String cursor,


    // 보조 커서 값 createAt
    @RequestParam(value = "after", required = false)
    @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME)
    Timestamp after,

    // viewCount 정렬 시 보조 커서 값
    @RequestParam(value = "cursorViewCount", required = false)
    Long cursorViewCount,

    @RequestParam(value = "limit", defaultValue = "50")
    int limit

) {}