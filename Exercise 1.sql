
IF NOT EXISTS (SELECT d.name 
					FROM sys.databases d 
					WHERE	(d.database_id > 4)
					AND		(d.[name] = N'DB_STAT')
)
BEGIN
	CREATE DATABASE DB_STAT
END
GO

USE DB_STAT
GO

--Create a table to store the history of performed actions 
IF NOT EXISTS 
(	SELECT 1
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = N'DB_STAT')
		AND		(OBJECTPROPERTY(o.[ID],N'IsUserTable')=1)
)
BEGIN
	CREATE TABLE dbo.DB_STAT
	(	stat_id		int				NOT NULL IDENTITY
			CONSTRAINT PK_DB_STAT PRIMARY KEY
	,	[db_nam]	nvarchar(20)	NOT NULL
	,	[comment]	nvarchar(20)	NOT NULL
	,	[when]		datetime		NOT NULL DEFAULT GETDATE()
	,	[usr_nam]	nvarchar(100)	NOT NULL DEFAULT USER_NAME()
	,	[host]		nvarchar(100)	NOT NULL DEFAULT HOST_NAME()
	)
END
GO

IF NOT EXISTS 
(	SELECT 1 
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = N'DB_RCOUNT')
		AND		(OBJECTPROPERTY(o.[ID], N'IsUserTable')=1)
)
BEGIN
	CREATE TABLE dbo.DB_RCOUNT
	(	stat_id		int				NOT NULL CONSTRAINT FK_DB_STAT__RCOUNT FOREIGN KEY
											REFERENCES dbo.DB_STAT(stat_id)
	,	[table]		nvarchar(100)	NOT NULL
	,	[RCOUNT]	int				NOT NULL DEFAULT 0
	,	[RDT]		datetime		NOT NULL DEFAULT GETDATE()
	)
END
GO


USE DB_STAT
GO

--Create a table to store the data needed to restore foreign keys
IF NOT EXISTS 
(	SELECT 1
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = N'DB_FK')
		AND		(OBJECTPROPERTY(o.[ID],N'IsUserTable')=1)
)
BEGIN
	CREATE TABLE dbo.DB_FK
	(	stat_id					int					NOT NULL CONSTRAINT FK_DB_FK__RCOUNT FOREIGN KEY 
													REFERENCES dbo.DB_STAT(stat_id) --Foreign key to connect to the DB_STAT table
	,	constraint_name			nvarchar(50)		NOT NULL
	,	referencing_table_name	nvarchar(20)		NOT NULL	--The name of the table that refers to the master table
	,	referencing_column_name nvarchar(20)		NOT NULL	--The name of the column that references the column in the master table
	,	master_table_name		nvarchar(20)		NOT NULL	--The name of the referenced table
	,	master_column_name		nvarchar(20)		NOT NULL	--The name of the referenced column
)
END
GO


--Create a procedure for writing foreign keys
IF NOT EXISTS 
(	SELECT 1 
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = 'save_foreign_keys')
		AND		(OBJECTPROPERTY(o.[ID],'IsProcedure')=1)
)
BEGIN
	DECLARE @stmt nvarchar(100)
	SET @stmt = 'CREATE PROCEDURE dbo.save_foreign_keys AS '
	EXEC sp_sqlexec @stmt
END
GO

ALTER PROCEDURE [dbo].save_foreign_keys (@db nvarchar(100), @commt nvarchar(20) = '<unkn>')
AS
	DECLARE @sql	nvarchar(2000)				-- SQL command to insert the result into the tables
	,		@id		int							-- Id given after inserting the record into the DB_STAT table
	,		@cID	nvarchar(20)				-- Converted @id to text

	SET @db = LTRIM(RTRIM(@db))					-- Remove leading and trailing spaces from the database name

	CREATE TABLE #Temp ([fkNumber] int)

	--Check if the given database has any foreign keys
	SET @sql = N'USE [' + @db + N']; '
	+ N'INSERT INTO #Temp SELECT COUNT (*) 
	FROM sys.foreign_keys AS f 
	JOIN sys.foreign_key_columns AS fc 
	ON f.[object_id] = fc.constraint_object_id'

	EXEC sp_sqlexec @sql

	IF (SELECT t.fkNumber FROM #Temp t) = 0			-- If the database has no foreign keys, exit the procedure
		BEGIN
			RETURN
		END
	ELSE											-- Otherwise save the foreign keys
		BEGIN
		-- Insert a record into the DB_STAT table and remember the ID that was given to the new row
		INSERT INTO DB_STAT.dbo.DB_STAT (comment, db_nam) 
		VALUES (@commt, @db)
		SET		@id = SCOPE_IDENTITY()
		SET		@cID = RTRIM(LTRIM(STR(@id,20,0)))

		SET @sql = N'USE [' + @db + N']; '
		+ 'INSERT INTO [DB_STAT].dbo.DB_FK '		-- Insert appropriate values ​​into the DB_FK table
		+ N' SELECT '
			+ @cID
			+ N' ,f.name constraint_name			
			, OBJECT_NAME(f.parent_object_id) referencing_table_name
			, COL_NAME(fc.parent_object_id, fc.parent_column_id) referencing_column_name
			, OBJECT_NAME (f.referenced_object_id) master_table_name
			, COL_NAME(fc.referenced_object_id, fc.referenced_column_id) master_column_name'
		+ N' FROM sys.foreign_keys AS f
		JOIN sys.foreign_key_columns AS fc
		ON f.[object_id] = fc.constraint_object_id
		ORDER BY f.name'

		EXEC sp_sqlexec @sql
		END
GO

USE DB_STAT
GO

-- Create a procedure for saving foreign keys from ALL databases
IF NOT EXISTS 
(	SELECT 1 
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = 'save_foreign_keys_from_all_databases')
		AND		(OBJECTPROPERTY(o.[ID],'IsProcedure')=1)
)
BEGIN
	DECLARE @stmt nvarchar(100)
	SET @stmt = 'CREATE PROCEDURE dbo.save_foreign_keys_from_all_databases AS '
	EXEC sp_sqlexec @stmt
END
GO

ALTER PROCEDURE [dbo].save_foreign_keys_from_all_databases (@dbToOmmit nvarchar(100), @commt nvarchar(20) = '<unkn>')
AS
	SET @dbToOmmit = LTRIM(RTRIM(@dbToOmmit))	-- Remove leading and trailing spaces from the database name

	DECLARE CC INSENSITIVE CURSOR FOR 
			SELECT d.name 
			FROM sys.databases d 
			WHERE d.database_id > 4
			AND NOT d.name = @dbToOmmit
	DECLARE @db		nvarchar(100)				-- The name of the database from which foreign keys are currently saved

	OPEN CC
	FETCH NEXT FROM CC INTO @db					
	WHILE (@@FETCH_STATUS = 0)
	BEGIN
		EXEC DB_STAT.dbo.save_foreign_keys @commt = @commt, @db = @db
		
		FETCH NEXT FROM CC INTO @db
	END
	CLOSE CC
	DEALLOCATE CC
GO

EXEC DB_STAT.dbo.save_foreign_keys_from_all_databases @commt = 'Multiple database', @dbToOmmit = N'DB_STAT' -- Execute the procedure

SELECT * FROM dbo.DB_FK							
SELECT * FROM dbo.DB_STAT

-- Results
/*
(7 rows affected)
stat_id     constraint_name                                    referencing_table_name referencing_column_name master_table_name    master_column_name
----------- -------------------------------------------------- ---------------------- ----------------------- -------------------- --------------------
1           FK_InvoicePositions_Products                       InvoicePositions       ProductId               Products             Id
1           FK_Invoices_Clients                                Invoices               ClientNumber            Clients              Id
1           FK_InvoicePositions_Invoices                       InvoicePositions       InvoiceId               Invoices             Id
2           FK_WARTOSCI_CECHY__CECHY                           WARTOSCI_CECH          id_CECHY                CECHY                id_CECHY
2           FK_FIRMY_CECHY__WARTOSCI_CECH                      FIRMY_CECHY            id_wartosci             WARTOSCI_CECH        id_wartosci
2           fk_miasta__woj                                     miasta                 kod_woj                 woj                  kod_woj
2           fk_firmy__miasta                                   firmy                  id_miasta               miasta               id_miasta
2           fk_osoby__miasta                                   osoby                  id_miasta               miasta               id_miasta
2           fk_etaty__osoby                                    etaty                  id_osoby                osoby                id_osoby
2           fk_etaty__firmy                                    etaty                  id_firmy                firmy                nazwa_skr

(10 rows affected)

stat_id     db_nam               comment              when                    usr_nam                                                                                              host
----------- -------------------- -------------------- ----------------------- ---------------------------------------------------------------------------------------------------- ----------------------------------------------------------------------------------------------------
1           Enterprise           Multiple database    2021-10-13 15:20:54.547 dbo                                                                                                  DESKTOP-QPIMAKI
2           pwx_db               Multiple database    2021-10-13 15:20:54.687 dbo                                                                                                  DESKTOP-QPIMAKI

(2 rows affected)
*/

--3

-- Create an auxiliary procedure to display foreign keys in the database
IF NOT EXISTS 
(	SELECT 1 
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = 'show_foreign_keys')
		AND		(OBJECTPROPERTY(o.[ID],'IsProcedure')=1)
)
BEGIN
	DECLARE @stmt nvarchar(100)
	SET @stmt = 'CREATE PROCEDURE dbo.show_foreign_keys AS '
	EXEC sp_sqlexec @stmt
END
GO

ALTER PROCEDURE [dbo].show_foreign_keys (@db nvarchar(100))
AS
	DECLARE	@sql	nvarchar(2000)		
	SET @sql = N'USE [' + @db + N']; ' 
	+ N'SELECT
			f.name constraint_name
		,OBJECT_NAME(f.parent_object_id) referencing_table_name
		,COL_NAME(fc.parent_object_id, fc.parent_column_id) referencing_column_name
		,OBJECT_NAME (f.referenced_object_id) referenced_table_name
		,COL_NAME(fc.referenced_object_id, fc.referenced_column_id) referenced_column_name
			FROM sys.foreign_keys AS f
			JOIN sys.foreign_key_columns AS fc
			ON f.[object_id] = fc.constraint_object_id
			ORDER BY f.name'

	EXEC sp_sqlexec @sql
GO

-- Create an auxiliary procedure to display foreign keys in ALL databases

IF NOT EXISTS 
(	SELECT 1 
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = 'show_foreign_keys_from_all_databases')
		AND		(OBJECTPROPERTY(o.[ID],'IsProcedure')=1)
)
BEGIN
	DECLARE @stmt nvarchar(100)
	SET @stmt = 'CREATE PROCEDURE dbo.show_foreign_keys_from_all_databases AS '
	EXEC sp_sqlexec @stmt
END
GO

ALTER PROCEDURE [dbo].show_foreign_keys_from_all_databases (@dbToOmmit nvarchar(100))
AS
	SET @dbToOmmit = LTRIM(RTRIM(@dbToOmmit))

	DECLARE CC_show INSENSITIVE CURSOR FOR 
			SELECT d.name 
			FROM sys.databases d 
			WHERE d.database_id > 4
			AND NOT d.name = @dbToOmmit
	DECLARE @db		nvarchar(100)

	OPEN CC_show
	FETCH NEXT FROM CC_show INTO @db
	WHILE (@@FETCH_STATUS = 0)
	BEGIN
		EXEC DB_STAT.dbo.show_foreign_keys @db = @db
		
		FETCH NEXT FROM CC_show INTO @db
	END
	CLOSE CC_show
	DEALLOCATE CC_show
GO

-- Create a procedure to remove foreign keys from the database

IF NOT EXISTS 
(	SELECT 1 
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = 'delete_foreign_keys')
		AND		(OBJECTPROPERTY(o.[ID],'IsProcedure')=1)
)
BEGIN
	DECLARE @stmt nvarchar(100)
	SET @stmt = 'CREATE PROCEDURE dbo.delete_foreign_keys AS '
	EXEC sp_sqlexec @stmt
END
GO

ALTER PROCEDURE [dbo].delete_foreign_keys (@db nvarchar(100), @commt nvarchar(20) = '<unkn>')
AS
	EXEC DB_STAT.dbo.save_foreign_keys @commt = @commt, @db = @db

	-- Create a temporary table to hold the constraint name and the table name with this constraint
	CREATE TABLE #TC1 ([constraint_name] nvarchar(100), [table] nvarchar(100))

	-- We are looking for the last stat_id for the last key dump
	DECLARE @max_stat_id int

	SET @max_stat_id = 
		(SELECT MAX(o.stat_id)
		FROM DB_STAT o
		WHERE o.[db_nam] = @db
		AND EXISTS ( SELECT 1 FROM db_fk f WHERE f.stat_id = o.stat_id))

	-- Put the rows with max stat_id value into this table, that is where the latest backup was
	INSERT INTO #TC1 
	SELECT fk.constraint_name, fk.referencing_table_name FROM dbo.DB_FK fk 
	INNER JOIN 
		(SELECT constraint_name, stat_id as 'max_stat_id'
		FROM dbo.DB_FK
		WHERE	stat_id = @max_stat_id) newest_fk
	ON fk.constraint_name = newest_fk.constraint_name
	AND fk.stat_id = newest_fk.max_stat_id

	DECLARE CC INSENSITIVE CURSOR FOR 
			SELECT o.[table], o.[constraint_name]
				FROM #TC1 o
				ORDER BY 1

	DECLARE		@tab	nvarchar(256)		-- The name of the next table
	,			@sql	nvarchar(2000)		-- SQL command to delete foreign keys
	,			@constraint	nvarchar(50)	-- Storing the currently removed constraint

	OPEN CC
	FETCH NEXT FROM CC INTO @tab, @constraint	
	WHILE (@@FETCH_STATUS = 0)
	BEGIN
		SET @sql = N'USE [' + @db + N']; '+ N'ALTER TABLE ' + @tab + N' DROP CONSTRAINT '+ @constraint
		EXEC sp_sqlexec @sql
		
		FETCH NEXT FROM CC INTO @tab, @constraint
	END
	CLOSE CC
	DEALLOCATE CC
GO

-- Create a procedure to remove foreign keys from ALL databases

IF NOT EXISTS 
(	SELECT 1 
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = 'delete_foreign_keys_from_all_databases')
		AND		(OBJECTPROPERTY(o.[ID],'IsProcedure')=1)
)
BEGIN
	DECLARE @stmt nvarchar(100)
	SET @stmt = 'CREATE PROCEDURE dbo.delete_foreign_keys_from_all_databases AS '
	EXEC sp_sqlexec @stmt
END
GO

ALTER PROCEDURE [dbo].delete_foreign_keys_from_all_databases (@dbToOmmit nvarchar(100), @commt nvarchar(20) = '<unkn>')
AS
	SET @dbToOmmit = LTRIM(RTRIM(@dbToOmmit))

	DECLARE CC_delete INSENSITIVE CURSOR FOR 
			SELECT d.name 
			FROM sys.databases d 
			WHERE d.database_id > 4
			AND NOT d.name = @dbToOmmit
	DECLARE @db		nvarchar(100)						

	OPEN CC_delete
	FETCH NEXT FROM CC_delete INTO @db					
	WHILE (@@FETCH_STATUS = 0)
	BEGIN
		EXEC DB_STAT.dbo.delete_foreign_keys @commt = @commt, @db = @db
		
		FETCH NEXT FROM CC_delete INTO @db
	END
	CLOSE CC_delete
	DEALLOCATE CC_delete
GO

EXEC dbo.show_foreign_keys_from_all_databases @dbToOmmit = N'DB_STAT'	-- Check the state of foreign keys before executing the procedure
EXEC DB_STAT.dbo.delete_foreign_keys_from_all_databases @commt = 'Test wielu baz', @dbToOmmit = N'DB_STAT'	-- Execute the procedure
EXEC dbo.show_foreign_keys_from_all_databases @dbToOmmit = N'DB_STAT'	-- Check the state of foreign keys after completing the procedure

-- Results

/* Before:
constraint_name                                                                                                                  referencing_table_name                                                                                                           referencing_column_name                                                                                                          referenced_table_name                                                                                                            referenced_column_name
-------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- --------------------------------------------------------------------------------------------------------------------------------
FK_InvoicePositions_Invoices                                                                                                     InvoicePositions                                                                                                                 InvoiceId                                                                                                                        Invoices                                                                                                                         Id
FK_InvoicePositions_Products                                                                                                     InvoicePositions                                                                                                                 ProductId                                                                                                                        Products                                                                                                                         Id
FK_Invoices_Clients                                                                                                              Invoices                                                                                                                         ClientNumber                                                                                                                     Clients                                                                                                                          Id

(3 rows affected)

constraint_name                                                                                                                  referencing_table_name                                                                                                           referencing_column_name                                                                                                          referenced_table_name                                                                                                            referenced_column_name
-------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- --------------------------------------------------------------------------------------------------------------------------------

(0 rows affected)

constraint_name                                                                                                                  referencing_table_name                                                                                                           referencing_column_name                                                                                                          referenced_table_name                                                                                                            referenced_column_name
-------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- --------------------------------------------------------------------------------------------------------------------------------
fk_etaty__firmy                                                                                                                  etaty                                                                                                                            id_firmy                                                                                                                         firmy                                                                                                                            nazwa_skr
fk_etaty__osoby                                                                                                                  etaty                                                                                                                            id_osoby                                                                                                                         osoby                                                                                                                            id_osoby
fk_firmy__miasta                                                                                                                 firmy                                                                                                                            id_miasta                                                                                                                        miasta                                                                                                                           id_miasta
FK_FIRMY_CECHY__WARTOSCI_CECH                                                                                                    FIRMY_CECHY                                                                                                                      id_wartosci                                                                                                                      WARTOSCI_CECH                                                                                                                    id_wartosci
fk_miasta__woj                                                                                                                   miasta                                                                                                                           kod_woj                                                                                                                          woj                                                                                                                              kod_woj
fk_osoby__miasta                                                                                                                 osoby                                                                                                                            id_miasta                                                                                                                        miasta                                                                                                                           id_miasta
FK_WARTOSCI_CECHY__CECHY                                                                                                         WARTOSCI_CECH                                                                                                                    id_CECHY                                                                                                                         CECHY                                                                                                                            id_CECHY

(7 rows affected)
*/

/*After:
-------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- --------------------------------------------------------------------------------------------------------------------------------

(0 rows affected)

constraint_name                                                                                                                  referencing_table_name                                                                                                           referencing_column_name                                                                                                          referenced_table_name                                                                                                            referenced_column_name
-------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- --------------------------------------------------------------------------------------------------------------------------------

(0 rows affected)

constraint_name                                                                                                                  referencing_table_name                                                                                                           referencing_column_name                                                                                                          referenced_table_name                                                                                                            referenced_column_name
-------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- --------------------------------------------------------------------------------------------------------------------------------

(0 rows affected)
*/

-- Create a procedure to restore foreign keys in the database

USE DB_STAT
DROP PROCEDURE dbo.recreate_foreign_keys
GO

IF NOT EXISTS 
(	SELECT 1 
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = 'recreate_foreign_keys')
		AND		(OBJECTPROPERTY(o.[ID],'IsProcedure')=1)
)
BEGIN
	DECLARE @stmt nvarchar(100)
	SET @stmt = 'CREATE PROCEDURE dbo.recreate_foreign_keys AS '
	EXEC sp_sqlexec @stmt
END
GO

ALTER PROCEDURE [dbo].recreate_foreign_keys (@db nvarchar(100), @commt nvarchar(20) = '<unkn>')
AS
	-- Create a temporary table to store the constraint name, table name, and columns associated with that constraint
	CREATE TABLE #TC 
	(	[constraint_name]				nvarchar(50)
	,	[referencing_table_name]		nvarchar(20)
	,	[referencing_column_name]		nvarchar(20)
	,	[master_table_name]				nvarchar(20)
	,	[master_column_name]			nvarchar(20)
	)

	DECLARE @max_stat_id int
	SET @max_stat_id = 
		(SELECT MAX(o.stat_id)
		FROM DB_STAT o
		WHERE o.[db_nam] = @db
		AND EXISTS ( SELECT 1 FROM db_fk f WHERE f.stat_id = o.stat_id))

	-- Insert the rows with the highest stat_id value into this table, that is where the latest backup was
	INSERT INTO #TC 
	SELECT fk.constraint_name
		, fk.referencing_table_name
		, fk.referencing_column_name
		, fk.master_table_name
		, fk.master_column_name FROM dbo.DB_FK fk 
	INNER JOIN 
		(SELECT constraint_name, stat_id AS 'max_stat_id'
		FROM dbo.DB_FK
		WHERE stat_id = @max_stat_id) newest_fk
	ON fk.constraint_name = newest_fk.constraint_name
	AND fk.stat_id = newest_fk.max_stat_id

	DECLARE CC INSENSITIVE CURSOR FOR 
			SELECT o.[constraint_name]
				, o.[referencing_table_name]
				, o.[referencing_column_name]
				, o.[master_table_name]
				, o.[master_column_name]
				FROM #TC o
				ORDER BY 1

	DECLARE		@constraint		nvarchar(50)		-- Name of the currently restored constraint
	,			@refTable		nvarchar(20)		-- Name of the table that refers to the master table
	,			@refColumn		nvarchar(20)		-- Name of the column that refers to the column in the master table
	,			@masTable		nvarchar(20)		-- Name of the referenced table
	,			@masColumn		nvarchar(20)		-- Name of the referenced column
	,			@sql			nvarchar(2000)		-- Variable to hold SQL command

	OPEN CC
	FETCH NEXT FROM CC
	INTO @constraint
		, @refTable
		, @refColumn
		, @masTable
		, @masColumn

	WHILE (@@FETCH_STATUS = 0)
	BEGIN
		SET @sql = N'USE [' + @db + N']; '
				 + N'ALTER TABLE ' + @refTable + N' ADD CONSTRAINT '+ @constraint 
				 + N' FOREIGN KEY '+ N' (' + @refColumn + N') REFERENCES ' + @masTable + N' (' + @masColumn + N')'
		EXEC sp_sqlexec @sql
		
		FETCH NEXT FROM CC 
		INTO @constraint
			, @refTable
			, @refColumn
			, @masTable
			, @masColumn
	END
	CLOSE CC
	DEALLOCATE CC
GO

-- We create a procedure to restore foreign keys in ALL databases

IF NOT EXISTS 
(	SELECT 1 
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = 'recreate_foreign_keys_from_all_databases')
		AND		(OBJECTPROPERTY(o.[ID],'IsProcedure')=1)
)
BEGIN
	DECLARE @stmt nvarchar(100)
	SET @stmt = 'CREATE PROCEDURE dbo.recreate_foreign_keys_from_all_databases AS '
	EXEC sp_sqlexec @stmt
END
GO

ALTER PROCEDURE [dbo].recreate_foreign_keys_from_all_databases (@dbToOmmit nvarchar(100), @commt nvarchar(20) = '<unkn>')
AS
	SET @dbToOmmit = LTRIM(RTRIM(@dbToOmmit))

	DECLARE CC_RECREATE INSENSITIVE CURSOR FOR 
			SELECT d.name 
			FROM sys.databases d 
			WHERE d.database_id > 4
			AND NOT d.name = @dbToOmmit
	DECLARE @db		nvarchar(100)						-- The name of the database from which we are currently restoring foreign keys

	OPEN CC_RECREATE
	FETCH NEXT FROM CC_RECREATE INTO @db
	WHILE (@@FETCH_STATUS = 0)
	BEGIN
		EXEC DB_STAT.dbo.recreate_foreign_keys @commt = @commt, @db = @db
		
		FETCH NEXT FROM CC_RECREATE INTO @db
	END
	CLOSE CC_RECREATE
	DEALLOCATE CC_RECREATE
GO

EXEC dbo.show_foreign_keys_from_all_databases @dbToOmmit = N'DB_STAT'		-- Check the state of foreign keys before executing the procedure
EXEC DB_STAT.dbo.recreate_foreign_keys_from_all_databases @commt = 'test', @dbToOmmit = N'DB_STAT'	-- Execute the procedure
EXEC dbo.show_foreign_keys_from_all_databases @dbToOmmit = N'DB_STAT'		-- Check the state of foreign keys after executing the procedure

--Wyniki

/*Przed uruchomieniem procedury:
-------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- --------------------------------------------------------------------------------------------------------------------------------

(0 rows affected)

constraint_name                                                                                                                  referencing_table_name                                                                                                           referencing_column_name                                                                                                          referenced_table_name                                                                                                            referenced_column_name
-------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- --------------------------------------------------------------------------------------------------------------------------------

(0 rows affected)

constraint_name                                                                                                                  referencing_table_name                                                                                                           referencing_column_name                                                                                                          referenced_table_name                                                                                                            referenced_column_name
-------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- --------------------------------------------------------------------------------------------------------------------------------

(0 rows affected)
*/

/* Po uruchomieniu procedury:
constraint_name                                                                                                                  referencing_table_name                                                                                                           referencing_column_name                                                                                                          referenced_table_name                                                                                                            referenced_column_name
-------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- --------------------------------------------------------------------------------------------------------------------------------
FK_InvoicePositions_Invoices                                                                                                     InvoicePositions                                                                                                                 InvoiceId                                                                                                                        Invoices                                                                                                                         Id
FK_InvoicePositions_Products                                                                                                     InvoicePositions                                                                                                                 ProductId                                                                                                                        Products                                                                                                                         Id
FK_Invoices_Clients                                                                                                              Invoices                                                                                                                         ClientNumber                                                                                                                     Clients                                                                                                                          Id

(3 rows affected)

constraint_name                                                                                                                  referencing_table_name                                                                                                           referencing_column_name                                                                                                          referenced_table_name                                                                                                            referenced_column_name
-------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- --------------------------------------------------------------------------------------------------------------------------------

(0 rows affected)

constraint_name                                                                                                                  referencing_table_name                                                                                                           referencing_column_name                                                                                                          referenced_table_name                                                                                                            referenced_column_name
-------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------------------------------------------------------------------------------------------------------- --------------------------------------------------------------------------------------------------------------------------------
fk_etaty__firmy                                                                                                                  etaty                                                                                                                            id_firmy                                                                                                                         firmy                                                                                                                            nazwa_skr
fk_etaty__osoby                                                                                                                  etaty                                                                                                                            id_osoby                                                                                                                         osoby                                                                                                                            id_osoby
fk_firmy__miasta                                                                                                                 firmy                                                                                                                            id_miasta                                                                                                                        miasta                                                                                                                           id_miasta
FK_FIRMY_CECHY__WARTOSCI_CECH                                                                                                    FIRMY_CECHY                                                                                                                      id_wartosci                                                                                                                      WARTOSCI_CECH                                                                                                                    id_wartosci
fk_miasta__woj                                                                                                                   miasta                                                                                                                           kod_woj                                                                                                                          woj                                                                                                                              kod_woj
fk_osoby__miasta                                                                                                                 osoby                                                                                                                            id_miasta                                                                                                                        miasta                                                                                                                           id_miasta
FK_WARTOSCI_CECHY__CECHY                                                                                                         WARTOSCI_CECH                                                                                                                    id_CECHY                                                                                                                         CECHY                                                                                                                            id_CECHY

(7 rows affected)
*/