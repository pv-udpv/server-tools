-- Top 10 largest tables
SELECT
    database,
    name,
    formatReadableSize(total_bytes) AS size,
    formatReadableQuantity(total_rows) AS rows
FROM system.tables
WHERE total_bytes > 0
ORDER BY total_bytes DESC
LIMIT 10;
