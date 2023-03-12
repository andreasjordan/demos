USE master
GO

DROP DATABASE TestDB
GO

CREATE DATABASE TestDB
GO

ALTER DATABASE TestDB SET RECOVERY SIMPLE;
GO

USE TestDB
GO

SET NOCOUNT ON;
GO

CREATE TABLE dbo.TestTableA
( Id        int IDENTITY
, JustSpace varchar(300) DEFAULT REPLICATE('Space', 30)  -- 5x 30 = 150 BYTE
, CONSTRAINT TestTableA_PK PRIMARY KEY (Id)
);
GO

CREATE TABLE dbo.TestTableB
( Id        int IDENTITY
, JustSpace varchar(300) DEFAULT REPLICATE('Space', 40)  -- 5x 40 = 200 BYTE
, CONSTRAINT TestTableB_PK PRIMARY KEY (Id)
);
GO

CREATE TABLE dbo.TestTableC
( Id        int IDENTITY
, JustSpace varchar(300) DEFAULT REPLICATE('Space', 60)  -- 5x 60 = 300 BYTE
, CONSTRAINT TestTableC_PK PRIMARY KEY (Id)
);
GO

INSERT INTO dbo.TestTableA DEFAULT VALUES;
INSERT INTO dbo.TestTableB DEFAULT VALUES;
INSERT INTO dbo.TestTableC DEFAULT VALUES;
GO 100000

UPDATE dbo.TestTableA
   SET JustSpace = JustSpace + 'we need much more Space!!we need much more Space!!'  -- 150 -> 200 BYTE
 WHERE Id <= 30000;

UPDATE dbo.TestTableB
   SET JustSpace = SUBSTRING(JustSpace, 1, 150)  -- 200 -> 150 BYTE
 WHERE Id > 30000;

UPDATE dbo.TestTableC
   SET JustSpace = SUBSTRING(JustSpace, 1, 200)  -- 300 -> 200 BYTE
 WHERE Id <= 30000;

UPDATE dbo.TestTableC
   SET JustSpace = SUBSTRING(JustSpace, 1, 150)  -- 300 -> 150 BYTE
 WHERE Id > 30000;

SELECT OBJECT_NAME(object_id) table_name, index_id, avg_fragmentation_in_percent, fragment_count, page_count, avg_page_space_used_in_percent, avg_record_size_in_bytes, record_count
  FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED')
 WHERE OBJECT_NAME(object_id) LIKE 'Test%'
   AND index_level = 0;

/*
TestTableA	1	46,32	1437	2709	82,98	180	100000
TestTableB	1	 0,33	 347	2703	83,16	180	100000
TestTableC	1	 0,35	 434	4000	56,19	180	100000

Test table A and B have both filled their pages to around 80 percent, but only A has a high value in avg_fragmentation_in_percent and would be processed by most de-fragmentation tools.
Test table C has their pages only filled around 50 percent, but as the value of avg_fragmentation_in_percent is so low, it would not be processed by most de-fragmentation tools.
*/








USE master
GO

DROP DATABASE TestDB
GO

CREATE DATABASE TestDB
GO

ALTER DATABASE TestDB SET RECOVERY SIMPLE;
GO

USE TestDB
GO

SET NOCOUNT ON;
GO

CREATE TABLE dbo.TestTableA
( Id        int IDENTITY
, Number    decimal(10,10) DEFAULT RAND()
, String    char(30) DEFAULT SUBSTRING(CONVERT(varchar, RAND()*10000000, 3), 3, 15) + SUBSTRING(CONVERT(varchar, RAND()*10000000, 3), 3, 15)
, JustSpace varchar(300) DEFAULT REPLICATE('Space', 30)  -- 5x 30 = 150 BYTE
, CONSTRAINT TestTableA_PK PRIMARY KEY (Id)
);
GO

INSERT INTO dbo.TestTableA DEFAULT VALUES;
GO 95000

CREATE INDEX TestIndex ON dbo.TestTableA (String) WITH FILLFACTOR = 90
GO

SELECT OBJECT_NAME(object_id) table_name, index_id, avg_fragmentation_in_percent, fragment_count, page_count, avg_page_space_used_in_percent, avg_record_size_in_bytes, record_count
  FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED')
 WHERE OBJECT_NAME(object_id) LIKE 'Test%'
   AND index_id = 2
   AND index_level = 0;
GO

INSERT INTO dbo.TestTableA DEFAULT VALUES;
GO 5000
DELETE dbo.TestTableA WHERE Id < (SELECT MIN(Id) FROM dbo.TestTableA) + 5000
GO
SELECT OBJECT_NAME(object_id) table_name, index_id, avg_fragmentation_in_percent, fragment_count, page_count, avg_page_space_used_in_percent, avg_record_size_in_bytes, record_count
  FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED')
 WHERE OBJECT_NAME(object_id) LIKE 'Test%' 
   AND index_id = 2
   AND index_level = 0;
GO

INSERT INTO dbo.TestTableA DEFAULT VALUES;
GO 5000
DELETE dbo.TestTableA WHERE Id < (SELECT MIN(Id) FROM dbo.TestTableA) + 5000
GO
SELECT OBJECT_NAME(object_id) table_name, index_id, avg_fragmentation_in_percent, fragment_count, page_count, avg_page_space_used_in_percent, avg_record_size_in_bytes, record_count
  FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED')
 WHERE OBJECT_NAME(object_id) LIKE 'Test%' 
   AND index_id = 2
   AND index_level = 0;
GO

INSERT INTO dbo.TestTableA DEFAULT VALUES;
GO 5000
DELETE dbo.TestTableA WHERE Id < (SELECT MIN(Id) FROM dbo.TestTableA) + 5000
GO
SELECT OBJECT_NAME(object_id) table_name, index_id, avg_fragmentation_in_percent, fragment_count, page_count, avg_page_space_used_in_percent, avg_record_size_in_bytes, record_count
  FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED')
 WHERE OBJECT_NAME(object_id) LIKE 'Test%' 
   AND index_id = 2
   AND index_level = 0;
GO

INSERT INTO dbo.TestTableA DEFAULT VALUES;
GO 5000
DELETE dbo.TestTableA WHERE Id < (SELECT MIN(Id) FROM dbo.TestTableA) + 5000
GO
SELECT OBJECT_NAME(object_id) table_name, index_id, avg_fragmentation_in_percent, fragment_count, page_count, avg_page_space_used_in_percent, avg_record_size_in_bytes, record_count
  FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED')
 WHERE OBJECT_NAME(object_id) LIKE 'Test%' 
   AND index_id = 2
   AND index_level = 0;
GO

INSERT INTO dbo.TestTableA DEFAULT VALUES;
GO 5000
DELETE dbo.TestTableA WHERE Id < (SELECT MIN(Id) FROM dbo.TestTableA) + 5000
GO

SELECT OBJECT_NAME(object_id) table_name, index_id, avg_fragmentation_in_percent, fragment_count, page_count, avg_page_space_used_in_percent, avg_record_size_in_bytes, record_count
  FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED')
 WHERE OBJECT_NAME(object_id) LIKE 'Test%' 
   AND index_id = 2
   AND index_level = 0;
GO

--ALTER INDEX TestIndex ON dbo.TestTableA REBUILD
--GO

DELETE dbo.TestTableA WHERE Id < (SELECT MIN(Id) FROM dbo.TestTableA) + 25000
GO

SELECT OBJECT_NAME(object_id) table_name, index_id, avg_fragmentation_in_percent, fragment_count, page_count, avg_page_space_used_in_percent, avg_record_size_in_bytes, record_count
  FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED')
 WHERE OBJECT_NAME(object_id) LIKE 'Test%'
   AND index_id = 2
   AND index_level = 0;
GO




--SELECT * FROM dbo.TestTableA;

--UPDATE dbo.TestTableA SET String = REVERSE(String) WHERE Number < 0.3

