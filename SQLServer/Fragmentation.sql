/*
Part 1:

Overall view of all pages related to user databases.

Can be be executed from any database context 
and shows information about every user database,
but object names cannot be retrieved.
*/


/*
Show one line per database.
*/
SELECT database_id
     , DB_NAME(database_id) AS database_name
     , COUNT(*) AS pages
     , COUNT(*)*8/1024 AS mb_total
     , SUM(free_space_in_bytes)/1024/1024 AS mb_free
  FROM sys.dm_os_buffer_descriptors
 WHERE database_id BETWEEN 5 and 32766
 GROUP BY database_id 
 ORDER BY database_id;


/*
Show one line per database, (relevant) page type and page level.
*/
SELECT database_id
     , DB_NAME(database_id) AS database_name
     , page_type
     , page_level
     , COUNT(*) AS pages
     , COUNT(*)*8/1024 AS mb_total
     , SUM(free_space_in_bytes)/1024/1024 AS mb_free
  FROM sys.dm_os_buffer_descriptors
 WHERE database_id BETWEEN 5 and 32766
 GROUP BY database_id
        , page_type
        , page_level
-- comment out to see all page types:
HAVING page_type NOT IN ('BOOT_PAGE', 'DIFF_MAP_PAGE', 'FILEHEADER_PAGE', 'GAM_PAGE', 'SGAM_PAGE', 'PFS_PAGE')
 ORDER BY database_id
        , page_type
        , page_level;


/*
Show one line per database and custom page type group.
*/
WITH data AS (
  SELECT database_id
       , DB_NAME(database_id) AS database_name
       , CASE
           WHEN page_type = 'DATA_PAGE'
           THEN 'DATA_PAGE'
           WHEN page_type = 'INDEX_PAGE'
            AND page_level = 0
           THEN 'INDEX_PAGE_leaf'
           WHEN page_type = 'INDEX_PAGE'
            AND page_level > 0
           THEN 'INDEX_PAGE_non_leaf'
           ELSE 'other_page'
         END AS page_type_and_level
       , CASE
           WHEN page_type = 'DATA_PAGE'
           THEN 1
           WHEN page_type = 'INDEX_PAGE'
            AND page_level = 0
           THEN 2
           WHEN page_type = 'INDEX_PAGE'
            AND page_level > 0
           THEN 3
           ELSE 4
         END AS order_id
       , free_space_in_bytes
    FROM sys.dm_os_buffer_descriptors
   WHERE database_id BETWEEN 5 and 32766
)
SELECT database_id
     , database_name
     , page_type_and_level
     , COUNT(*) AS pages
     , COUNT(*)*8/1024 AS mb_total
     , SUM(free_space_in_bytes)/1024/1024 AS mb_free
  FROM data
 GROUP BY database_id
        , database_name
        , page_type_and_level
        , order_id
 ORDER BY database_id
        , order_id;



/*
Part 2:

Detailed view of all pages related to one database.

Must be be executed from the target database context 
and shows information per object.
*/

USE test01
GO


/*
Show detailed information for "DATA_PAGE" and "INDEX_PAGE_leaf" per index on user objects.
*/
SELECT o.name AS table_name
     , i.index_id
     , i.name AS index_name
     , i.type_desc AS index_type
     , CASE
         WHEN bd.page_type = 'DATA_PAGE'
         THEN 'DATA_PAGE'
         ELSE 'INDEX_PAGE_leaf'
       END AS page_type_and_level
     , COUNT(*) AS pages
     , COUNT(*)*8/1024 AS mb_total
     , AVG(bd.free_space_in_bytes) AS avg_free_space_in_bytes
     , (8096-AVG(bd.free_space_in_bytes))*100/8096 AS avg_page_space_used_in_percent
     , MAX(i.fill_factor) AS index_fill_factor
  FROM sys.dm_os_buffer_descriptors AS bd
  JOIN sys.allocation_units AS au ON bd.allocation_unit_id = au.allocation_unit_id
  JOIN sys.partitions AS p ON au.container_id = p.hobt_id
  JOIN sys.objects AS o ON p.object_id = o.object_id
  JOIN sys.indexes AS i ON p.object_id = i.object_id AND p.index_id = i.index_id
 WHERE bd.database_id = DB_ID()
   AND bd.page_type IN ('DATA_PAGE', 'INDEX_PAGE')
   AND bd.page_level = 0
   AND au.type_desc = 'IN_ROW_DATA'
   AND o.is_ms_shipped = 0
 GROUP BY o.name
        , i.index_id
        , i.name
        , i.type_desc
        , bd.page_type
 ORDER BY 1,2;


/*
Show detailed information of all pages not shown in previous query.
*/
SELECT o.is_ms_shipped
     , o.name AS table_name
     , i.index_id
     , i.name AS index_name
     , i.type_desc AS index_type
     , bd.page_type AS page_type
     , bd.page_level
     , au.type_desc AS allocation_type
     , COUNT(*) AS pages
     , COUNT(*)*8/1024 AS mb_total
  FROM sys.dm_os_buffer_descriptors AS bd
  LEFT JOIN sys.allocation_units AS au ON bd.allocation_unit_id = au.allocation_unit_id
  LEFT JOIN sys.partitions AS p ON au.container_id = p.hobt_id
  LEFT JOIN sys.objects AS o ON p.object_id = o.object_id
  LEFT JOIN sys.indexes AS i ON p.object_id = i.object_id AND p.index_id = i.index_id
 WHERE bd.database_id = DB_ID()
   AND NOT (    ISNULL(bd.page_type, 'X') IN ('DATA_PAGE', 'INDEX_PAGE')
            AND ISNULL(bd.page_level, -1) = 0
            AND ISNULL(au.type_desc, 'X') = 'IN_ROW_DATA'
            AND ISNULL(o.is_ms_shipped, -1) = 0
           )
 GROUP BY o.is_ms_shipped
        , o.name
        , i.index_id
        , i.name
        , i.type_desc
        , bd.page_type
        , bd.page_level
        , au.type_desc
 ORDER BY 1,2,3,4,5,6,7,8;


/*
Very detailed view, query should be customized for individual needs.
*/
SELECT o.name AS table_name
     , i.name AS index_name
     , i.type_desc AS index_type
     , i.fill_factor
     , bd.page_type
     , au.type_desc AS allocation_type
     , bd.file_id
     , bd.page_id
     , bd.row_count
     , bd.free_space_in_bytes
     , bd.page_level
  FROM sys.dm_os_buffer_descriptors AS bd
  JOIN sys.allocation_units AS au ON bd.allocation_unit_id = au.allocation_unit_id
  JOIN sys.partitions AS p ON au.container_id = p.hobt_id
  JOIN sys.objects AS o ON p.object_id = o.object_id
  JOIN sys.indexes AS i ON p.object_id = i.object_id AND p.index_id = i.index_id
 WHERE bd.database_id = DB_ID()
--   AND bd.page_type IN ('DATA_PAGE', 'INDEX_PAGE')
--   AND bd.page_level = 0
--   AND au.type_desc = 'IN_ROW_DATA'
--   AND o.is_ms_shipped = 0
 ORDER BY 1,2,3,4,5,6,7;

