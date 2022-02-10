USE TrainDB_backup
GO

-- Create sample tables
CREATE TABLE dbo.pomocnicza_tabela
( [id] int not null IDENTITY(1,1) PRIMARY KEY
, wiek int not null
)

CREATE TABLE dbo.test_us_kol
( [id] nchar(6) not null
, fk int not null 
	CONSTRAINT fk_testowa_pomocnicza FOREIGN KEY (fk)
	REFERENCES pomocnicza_tabela(id)
, czy_wazny bit NOT NULL default 0 
)
GO


INSERT INTO pomocnicza_tabela VALUES (18)
INSERT INTO pomocnicza_tabela VALUES (6)

SELECT * FROM pomocnicza_tabela

-- Insert values ​​to check if the default is being set
INSERT INTO test_us_kol ([id], fk) VALUES (N'ala', 1)
INSERT INTO test_us_kol ([id], fk, czy_wazny) VALUES (N'kot', 2, 1)

SELECT * FROM test_us_kol

/*
id     fk          czy_wazny
------ ----------- ---------
ala    1           0
kot    2           1

(2 rows affected)
*/

USE DB_STAT
GO

IF NOT EXISTS 
(	SELECT 1 
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = 'drop_column')
		AND		(OBJECTPROPERTY(o.[ID],'IsProcedure')=1)
)
BEGIN
	DECLARE @stmt nvarchar(100)
	SET @stmt = 'CREATE PROCEDURE dbo.drop_column AS '
	EXEC sp_sqlexec @stmt
END
GO

ALTER PROCEDURE [dbo].drop_column (@db nvarchar(100), @table nvarchar(50), @column nvarchar(50))
AS
	DECLARE @sql	nvarchar(2000)				-- Variable to hold SQL command
	
	SET @db = LTRIM(RTRIM(@db))					-- Remove leading and trailing spaces from the database name
	SET @table = LTRIM(RTRIM(@table))			-- Remove leading and trailing spaces from the table name
	SET @column = LTRIM(RTRIM(@column))			-- Remove leading and trailing spaces from the column name

	-- We check if the column exists (query from syscolumns combined with sysobjects by ID)
	SET @sql = N'USE ' + @db 
			+ N' SELECT * FROM sys.columns c
			JOIN sys.objects o
			ON o.object_id = c.object_id
			WHERE o.name = ''' + @table + N'''		
			AND c.name = ''' + @column + N''''

	EXEC sp_sqlexec @sql

	-- As there is, we check if there are certain limitations (e.g. DEFAULT was set)
	IF (@@ROWCOUNT > 0)
		BEGIN
			DECLARE @constraint_name nvarchar(100)

			-- Check whether the column is set to Default
			SET @sql = N'USE ' + @db 
			+ N' SELECT @constraint_name = (
			SELECT o.name FROM sysobjects o 
			INNER JOIN syscolumns c
			ON o.id = c.cdefault
			INNER JOIN sysobjects t
			ON c.id = t.id
			WHERE o.xtype = ''D''
			AND c.name = ''' + @column + N'''		
			AND t.name = ''' + @table + N''')'

			-- Save the query result to the constraint_name variable
			EXEC sp_executesql @sql, @Params = N'@constraint_name nvarchar(100) OUTPUT', @constraint_name = @constraint_name OUTPUT

			IF (@@ROWCOUNT > 0)
				BEGIN
					-- Delete the Default value in the column
					SET @sql = N'USE ' + @db + N' ALTER TABLE ' + @table + N' DROP CONSTRAINT ' + @constraint_name
					EXEC sp_sqlexec @sql	
				END

			-- We check if the column uses any foreign key
			DECLARE @foreign_key_constraint_name nvarchar(100)

			SET @sql = N'USE ' + @db 
			+ N' SELECT @foreign_key_constraint_name = (
			SELECT OBJECT_NAME(f.object_id) as ForeignKeyConstraintName
			FROM sys.foreign_keys AS f
				INNER JOIN sys.foreign_key_columns AS fk 
				ON f.OBJECT_ID = fk.constraint_object_id
			WHERE OBJECT_NAME(f.parent_object_id) = ''' + @table + N'''
			AND COL_NAME(fk.parent_object_id,fk.parent_column_id) = ''' + @column + N''')'

			-- We save the query result to the foreignKeyConstraintName variable
			EXEC sp_executesql @sql, @Params = N'@foreign_key_constraint_name nvarchar(100) OUTPUT',
			@foreign_key_constraint_name = @foreign_key_constraint_name OUTPUT

			SELECT foreign_key_constraint_name

			IF (@@ROWCOUNT > 0)
				BEGIN
					-- Remove the foreign key contraints
					SET @sql = N'USE ' + @db +  N' ALTER TABLE ' + @table + N' DROP CONSTRAINT ' + @foreign_key_constraint_name
					EXEC sp_sqlexec @sql	
				END

			-- Remove the column
			SET @sql = N'USE ' + @db 
			+ N' ALTER TABLE ' + @table 
			+ N' DROP COLUMN ' + @column
			
			EXEC sp_sqlexec @sql  
		END
	ELSE
		RETURN
GO

USE TrainDB_backup
GO

SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = N'test_us_kol'

/* The columns in the test_us_kol table before running the procedure
TABLE_NAME	COLUMN_NAME	DATA_TYPE
test_us_kol	id			nchar
test_us_kol	fk			int
test_us_kol	czy_wazny	bit
*/

--Deleting a column with a default value
EXEC DB_STAT.dbo.drop_column @db = N'TrainDB_backup', @table = N'test_us_kol', @column = N'czy_wazny'

SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = N'test_us_kol'

/* Columns in the test_us_kol table after removing the column czy_ważny
TABLE_NAME	COLUMN_NAME	DATA_TYPE
test_us_kol	id			nchar
test_us_kol	fk			int
*/

--Removing a foreign key column
EXEC DB_STAT.dbo.drop_column @db = N'TrainDB_backup', @table = N'test_us_kol', @column = N'fk'

SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = N'test_us_kol'

/* Columns in the test_us_kol table after removing the column fk
TABLE_NAME	COLUMN_NAME	DATA_TYPE
test_us_kol	id			nchar
*/