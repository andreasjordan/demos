CREATE DATABASE test01
CREATE DATABASE test02
-- Just in case it's an Express Edition:
ALTER DATABASE test01 SET AUTO_CLOSE OFF
ALTER DATABASE test02 SET AUTO_CLOSE OFF
GO

DECLARE @columnDefinition VARCHAR(1000) = '
id    INT,
num1  INT,
num2  INT,
txt1  CHAR(100),
txt2  CHAR(100)'
EXEC ('CREATE TABLE test01.dbo.heap01 (' + @columnDefinition + ')')
EXEC ('CREATE TABLE test01.dbo.heap02 (' + @columnDefinition + ')')
EXEC ('CREATE TABLE test01.dbo.table01 (' + @columnDefinition + ', CONSTRAINT table01_PK PRIMARY KEY (id))')
EXEC ('CREATE TABLE test01.dbo.table02 (' + @columnDefinition + ', CONSTRAINT table02_PK PRIMARY KEY (id))')
EXEC ('CREATE TABLE test02.dbo.heap01 (' + @columnDefinition + ')')
EXEC ('CREATE TABLE test02.dbo.heap02 (' + @columnDefinition + ')')
EXEC ('CREATE TABLE test02.dbo.table01 (' + @columnDefinition + ', CONSTRAINT table01_PK PRIMARY KEY (id))')
EXEC ('CREATE TABLE test02.dbo.table02 (' + @columnDefinition + ', CONSTRAINT table02_PK PRIMARY KEY (id))')
GO

SET NOCOUNT ON;
DECLARE @id INT = 1;
WHILE @id <= 50000
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
CREATE INDEX num2 ON test01.dbo.heap02 (num2) WITH FILLFACTOR = 70;
CREATE INDEX num1 ON test01.dbo.table01 (num1);
CREATE INDEX num2 ON test01.dbo.table01 (num2);
CREATE INDEX num1 ON test01.dbo.table02 (num1);
CREATE INDEX num2 ON test01.dbo.table02 (num2) WITH FILLFACTOR = 70;
CREATE INDEX num1 ON test02.dbo.heap01 (num1);
CREATE INDEX num2 ON test02.dbo.heap01 (num2);
CREATE INDEX num1 ON test02.dbo.heap02 (num1);
CREATE INDEX num2 ON test02.dbo.heap02 (num2) WITH FILLFACTOR = 70;
CREATE INDEX num1 ON test02.dbo.table01 (num1);
CREATE INDEX num2 ON test02.dbo.table01 (num2);
CREATE INDEX num1 ON test02.dbo.table02 (num1);
CREATE INDEX num2 ON test02.dbo.table02 (num2) WITH FILLFACTOR = 70;

DELETE test01.dbo.heap01 WHERE Id%5 = 0;
DELETE test01.dbo.heap02 WHERE Id%5 = 0;
DELETE test01.dbo.table01 WHERE Id%5 = 0;
DELETE test01.dbo.table02 WHERE Id%5 = 0;

UPDATE test01.dbo.heap01 SET num2 = -num1;
UPDATE test01.dbo.heap02 SET num2 = -num1;
UPDATE test01.dbo.table01 SET num2 = -num1;
UPDATE test01.dbo.table02 SET num2 = -num1;
GO

/* To remove the databases:

USE master;
DROP DATABASE test01;
DROP DATABASE test02;
GO

*/
