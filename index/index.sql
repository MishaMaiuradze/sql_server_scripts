
SELECT
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.avg_fragmentation_in_percent,
    ips.page_count,
    CASE
        WHEN ips.avg_fragmentation_in_percent < 5 THEN 'No Action Needed'
        WHEN ips.avg_fragmentation_in_percent BETWEEN 5 AND 30 THEN 'Reorganize'
        WHEN ips.avg_fragmentation_in_percent > 30 THEN 'Rebuild'
    END AS Recommendation,
    -- Generate the actual SQL command
    CASE
        WHEN ips.avg_fragmentation_in_percent BETWEEN 5 AND 30 THEN
            'ALTER INDEX [' + i.name + '] ON [' + OBJECT_SCHEMA_NAME(ips.object_id) + '].[' + OBJECT_NAME(ips.object_id) + '] REORGANIZE;'
        WHEN ips.avg_fragmentation_in_percent > 30 THEN
            'ALTER INDEX [' + i.name + '] ON [' + OBJECT_SCHEMA_NAME(ips.object_id) + '].[' + OBJECT_NAME(ips.object_id) + '] REBUILD;'
        ELSE 'No action needed'
    END AS SQLCommand
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED') ips
JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.avg_fragmentation_in_percent >= 5  -- Only show indexes that need attention
 --AND ips.page_count > 100  -- Only consider indexes with significant pages
 AND i.index_id > 0  -- Exclude heaps
 AND i.is_disabled = 0  -- Exclude disabled indexes
ORDER BY ips.avg_fragmentation_in_percent DESC;



-- Comprehensive Index Information with Storage Details
-- Sorted by Storage Size Descending
SELECT
    -- Basic Index Information
    OBJECT_SCHEMA_NAME(i.object_id) AS SchemaName,
    OBJECT_NAME(i.object_id) AS TableName,
    i.name AS IndexName,
    i.type_desc AS IndexType,
    -- Storage Information (in MB)
    CAST(SUM(ps.used_page_count * 8.0 / 1024) AS DECIMAL(10,2)) AS IndexSizeMB,
    CAST(SUM(ps.reserved_page_count * 8.0 / 1024) AS DECIMAL(10,2)) AS ReservedSizeMB,
    SUM(ps.row_count) AS [RowCount],
    -- Index Properties
    i.is_unique AS IsUnique,
    i.is_primary_key AS IsPrimaryKey,
    i.is_unique_constraint AS IsUniqueConstraint,
    i.fill_factor AS [FillFactor],
    i.is_padded AS IsPadded,
    i.is_disabled AS IsDisabled,
    i.allow_row_locks AS AllowRowLocks,
    i.allow_page_locks AS AllowPageLocks,
    -- Fragmentation Information
    ips.avg_fragmentation_in_percent AS FragmentationPercent,
    ips.fragment_count AS FragmentCount,
    ips.avg_page_space_used_in_percent AS AvgPageSpaceUsed,
    ips.page_count AS PageCount,
    -- Index Key Columns
    STUFF((
        SELECT ', ' + COL_NAME(ic.object_id, ic.column_id) +
               CASE WHEN ic.is_descending_key = 1 THEN ' DESC' ELSE ' ASC' END
        FROM sys.index_columns ic
        WHERE ic.object_id = i.object_id
          AND ic.index_id = i.index_id
          AND ic.is_included_column = 0
        ORDER BY ic.key_ordinal
        FOR XML PATH('')
    ), 1, 2, '') AS KeyColumns,
    -- Included Columns
    STUFF((
        SELECT ', ' + COL_NAME(ic.object_id, ic.column_id)
        FROM sys.index_columns ic
        WHERE ic.object_id = i.object_id
          AND ic.index_id = i.index_id
          AND ic.is_included_column = 1
        ORDER BY ic.key_ordinal
        FOR XML PATH('')
    ), 1, 2, '') AS IncludedColumns,
    -- Usage Statistics (if available)
    us.user_seeks AS UserSeeks,
    us.user_scans AS UserScans,
    us.user_lookups AS UserLookups,
    us.user_updates AS UserUpdates,
    us.last_user_seek AS LastUserSeek,
    us.last_user_scan AS LastUserScan,
    us.last_user_lookup AS LastUserLookup,
    us.last_user_update AS LastUserUpdate,
    -- Maintenance Recommendations
    CASE
        WHEN ips.avg_fragmentation_in_percent IS NULL THEN 'N/A (Heap or small index)'
        WHEN ips.avg_fragmentation_in_percent < 5 THEN 'No Action Needed'
        WHEN ips.avg_fragmentation_in_percent BETWEEN 5 AND 30 THEN 'Consider Reorganize'
        WHEN ips.avg_fragmentation_in_percent > 30 THEN 'Consider Rebuild'
    END AS MaintenanceRecommendation,
    -- Usage Score (composite metric)
    ISNULL(us.user_seeks, 0) + ISNULL(us.user_scans, 0) + ISNULL(us.user_lookups, 0) AS TotalReads,
    -- Compression Information
    p.data_compression_desc AS CompressionType
FROM sys.indexes i
    INNER JOIN sys.objects o ON i.object_id = o.object_id
    LEFT JOIN sys.dm_db_partition_stats ps ON i.object_id = ps.object_id AND i.index_id = ps.index_id
    LEFT JOIN sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
        ON i.object_id = ips.object_id AND i.index_id = ips.index_id
    LEFT JOIN sys.dm_db_index_usage_stats us
        ON i.object_id = us.object_id AND i.index_id = us.index_id AND us.database_id = DB_ID()
    LEFT JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
WHERE o.type = 'U'  -- User tables only
  AND i.index_id >= 0  -- Include heaps and indexes
  AND o.is_ms_shipped = 0  -- Exclude system tables
GROUP BY
    i.object_id, i.index_id, i.name, i.type_desc, i.is_unique, i.is_primary_key,
    i.is_unique_constraint, i.fill_factor, i.is_padded, i.is_disabled,
    i.allow_row_locks, i.allow_page_locks, ips.avg_fragmentation_in_percent,
    ips.fragment_count, ips.avg_page_space_used_in_percent, ips.page_count,
    us.user_seeks, us.user_scans, us.user_lookups, us.user_updates,
    us.last_user_seek, us.last_user_scan, us.last_user_lookup, us.last_user_update,
    p.data_compression_desc
-- Sort by storage size descending
ORDER BY IndexSizeMB DESC;


