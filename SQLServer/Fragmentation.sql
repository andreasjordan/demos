CREATE DATABASE test01
CREATE DATABASE test02
-- Just in case it's an Express Edition:
ALTER DATABASE test01 SET AUTO_CLOSE OFF
ALTER DATABASE test02 SET AUTO_CLOSE OFF
GO


CREATE TABLE test01.dbo.heap01
( id    INT
, num1  INT 
, num2  INT
, txt1  CHAR(100)
, txt2  CHAR(200)
)
CREATE TABLE test01.dbo.heap02
( id    INT
, num1  INT 
, num2  INT
, txt1  CHAR(100)
, txt2  CHAR(200)
)
CREATE TABLE test01.dbo.table01
( id    INT PRIMARY KEY
, num1  INT 
, num2  INT
, txt1  CHAR(100)
, txt2  CHAR(200)
)
CREATE TABLE test01.dbo.table02
( id    INT PRIMARY KEY
, num1  INT 
, num2  INT
, txt1  CHAR(100)
, txt2  CHAR(200)
)
CREATE TABLE test02.dbo.heap01
( id    INT
, num1  INT 
, num2  INT
, txt1  CHAR(100)
, txt2  CHAR(200)
)
CREATE TABLE test02.dbo.heap02
( id    INT
, num1  INT 
, num2  INT
, txt1  CHAR(100)
, txt2  CHAR(200)
)
CREATE TABLE test02.dbo.table01
( id    INT PRIMARY KEY
, num1  INT 
, num2  INT
, txt1  CHAR(100)
, txt2  CHAR(200)
)
CREATE TABLE test02.dbo.table02
( id    INT PRIMARY KEY
, num1  INT 
, num2  INT
, txt1  CHAR(100)
, txt2  CHAR(200)
)
GO

SET NOCOUNT ON;
DECLARE @id INT = 1;
WHILE @id <= 300000
BEGIN
	INSERT INTO test01.dbo.heap01 VALUES (@id, @id, @id, @id, @id);
	INSERT INTO test01.dbo.heap02 VALUES (@id, @id, @id, @id, @id);
	INSERT INTO test01.dbo.table01 VALUES (@id, @id, @id, @id, @id);
	INSERT INTO test01.dbo.table02 VALUES (@id, @id, @id, @id, @id);
	INSERT INTO test02.dbo.heap01 VALUES (@id, @id, @id, @id, @id);
	INSERT INTO test02.dbo.heap02 VALUES (@id, @id, @id, @id, @id);
	INSERT INTO test02.dbo.table01 VALUES (@id, @id, @id, @id, @id);
	INSERT INTO test02.dbo.table02 VALUES (@id, @id, @id, @id, @id);
	SET @id = @id + 1;
END;
GO

CREATE INDEX num1 ON test01.dbo.heap01 (num1);
CREATE INDEX num2 ON test01.dbo.heap01 (num2);
CREATE INDEX num1 ON test01.dbo.heap02 (num1);
CREATE INDEX num2 ON test01.dbo.heap02 (num2);
CREATE INDEX num1 ON test01.dbo.table01 (num1);
CREATE INDEX num2 ON test01.dbo.table01 (num2);
CREATE INDEX num1 ON test01.dbo.table02 (num1);
CREATE INDEX num2 ON test01.dbo.table02 (num2);
CREATE INDEX num1 ON test02.dbo.heap01 (num1);
CREATE INDEX num2 ON test02.dbo.heap01 (num2);
CREATE INDEX num1 ON test02.dbo.heap02 (num1);
CREATE INDEX num2 ON test02.dbo.heap02 (num2);
CREATE INDEX num1 ON test02.dbo.table01 (num1);
CREATE INDEX num2 ON test02.dbo.table01 (num2);
CREATE INDEX num1 ON test02.dbo.table02 (num1);
CREATE INDEX num2 ON test02.dbo.table02 (num2);

DELETE test01.dbo.heap01 WHERE Id%5 = 0;
DELETE test01.dbo.heap02 WHERE Id%5 = 0;
DELETE test01.dbo.table01 WHERE Id%5 = 0;
DELETE test01.dbo.table02 WHERE Id%5 = 0;

UPDATE test01.dbo.heap01 SET num2 = -num1;
UPDATE test01.dbo.heap02 SET num2 = -num1;
UPDATE test01.dbo.table01 SET num2 = -num1;
UPDATE test01.dbo.table02 SET num2 = -num1;

-- Ca. 10 Minuten bis hierher

SELECT database_id
     , DB_NAME(database_id) AS database_name
     , COUNT(*) AS pages
	 , COUNT(*)*8/1024 AS mb_total
	 , SUM(free_space_in_bytes)/1024/1024 AS mb_free
  FROM sys.dm_os_buffer_descriptors
 WHERE database_id BETWEEN 5 and 32766
 GROUP BY database_id 
 ORDER BY database_id

/*
5	test01	56146	438	109
6	test02	53969	421	11
*/

SELECT database_id
     , DB_NAME(database_id) AS database_name
	 , page_level
	 , page_type
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
        , page_level

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
         END AS page_type
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
         END AS page_type_order_id
       , free_space_in_bytes
    FROM sys.dm_os_buffer_descriptors
   WHERE database_id BETWEEN 5 and 32766
)
SELECT database_id
     , database_name
     , page_type
     , COUNT(*) AS pages
	 , COUNT(*)*8/1024 AS mb_total
	 , SUM(free_space_in_bytes)/1024/1024 AS mb_free
  FROM data
 GROUP BY database_id
        , database_name
        , page_type
		, page_type_order_id
 ORDER BY database_id
        , page_type_order_id




USE test01
GO

-- Nicht sehr hilfreich, aber vielleicht mal für Detail-Analysen:
SELECT o.name AS table_name
	 , i.name AS index_name
	 , i.type_desc AS index_type
     , bd.page_type AS page_type
	 , au.type_desc AS allocation_type
	 , bd.file_id
	 , bd.page_id
     , bd.row_count
	 , bd.free_space_in_bytes
	 , i.fill_factor
	 , bd.page_level
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
 ORDER BY 1,2,3,4,5,6,7


-- Nur "DATA_PAGE" und "INDEX_PAGE_leaf"
SELECT o.name AS table_name
     , i.index_id
	 , i.name AS index_name
	 , i.type_desc AS index_type
	 , COUNT(*) AS pages
	 , COUNT(*)*8/1024 AS mb_total
     , SUM(bd.row_count) AS sum_row_count
	 , AVG(bd.free_space_in_bytes) AS avg_free_space_in_bytes
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
 ORDER BY 1,2


SELECT o.is_ms_shipped
	 , o.name AS table_name
     , i.index_id
	 , i.name AS index_name
	 , i.type_desc AS index_type
     , bd.page_type AS page_type
	 , bd.page_level
	 , au.type_desc AS allocation_type
	 , COUNT(*) AS pages
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
 ORDER BY 1,2,3,4,5,6,7,8



USE master;
DROP DATABASE test01;
DROP DATABASE test02;
