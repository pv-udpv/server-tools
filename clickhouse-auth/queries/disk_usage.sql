-- Disk usage by database
SELECT
    database,
    formatReadableSize(sum(total_bytes)) AS total_size,
    count() AS table_count
FROM system.tables
GROUP BY database
ORDER BY sum(total_bytes) DESC;
