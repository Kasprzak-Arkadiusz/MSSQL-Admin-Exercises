USE DB_STAT
GO

IF NOT EXISTS 
(	SELECT 1 
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = 'create_indexes_on_foreign_keys')
		AND		(OBJECTPROPERTY(o.[ID],'IsProcedure')=1)
)
BEGIN
	DECLARE @stmt nvarchar(100)
	SET @stmt = 'CREATE PROCEDURE dbo.create_indexes_on_foreign_keys AS '
	EXEC sp_sqlexec @stmt
END
GO

ALTER PROCEDURE [dbo].create_indexes_on_foreign_keys (@db nvarchar(100))
AS
	DECLARE @sql	nvarchar(2000)					-- Variable to hold SQL command
	SET @db = LTRIM(RTRIM(@db))						-- Remove leading and trailing spaces from the database name

	CREATE TABLE #Count ([fkNumber] int)			-- Table for storing the number of foreign keys

	-- Check if the given database has any foreign keys
	SET @sql = N'USE [' + @db + N']; '
	+ N'INSERT INTO #Count SELECT COUNT (*) 
	FROM sys.foreign_keys AS f 
	JOIN sys.foreign_key_columns AS fc 
	ON f.[object_id] = fc.constraint_object_id'

	EXEC sp_sqlexec @sql

	IF (SELECT t.fkNumber FROM #Count t) = 0			-- If the database has no foreign keys, exit the procedure
		BEGIN
			RETURN
		END
	ELSE												-- Otherwise save the foreign keys
		BEGIN

-- Create a temporary table to store foreign key details
			CREATE TABLE #TempForeignKeys 
			(
				MasterTableName varchar(100),	-- The name of the master table
				DetailsTableName varchar(100),	-- The name of the table that refers to the master table
				DetailColumnsName varchar(100), -- The name of the column that references the master table
				ForeignKeyName varchar(100),	-- The name of the foreign key
				ObjectID int					-- Foreign key identifier
			)

-- Fill this table
			INSERT INTO #TempForeignKeys 
			SELECT 
				OBJECT_NAME(fk.referenced_object_id) as [masterName],
				o.[name] as [detailName],
				COL_NAME(fkc.parent_object_id, fkc.parent_column_id),
				fk.[name] as [fkName], 
				fk.[object_id] as [objectId] 
			FROM sys.foreign_keys fk
			INNER JOIN sys.objects o
			ON o.[object_id] = fk.[parent_object_id]
			INNER JOIN sys.foreign_key_columns fkc
			ON fk.[object_id] = fkc.constraint_object_id
			WHERE o.is_ms_shipped = 0			-- User-created indexes only

-- Create a temporary table to store foreign key indexes
			CREATE TABLE #TempIndexedFK (ObjectID int)

-- Fill this table
			INSERT INTO #TempIndexedFK  
			SELECT ObjectID
			FROM sys.foreign_key_columns fkc
			JOIN sys.index_columns i
			ON fkc.parent_object_id = i.[object_id]
			JOIN #TempForeignKeys fk
			ON  fkc.constraint_object_id = fk.ObjectID
			WHERE fkc.parent_column_id = i.column_id 

			DECLARE CC INSENSITIVE CURSOR FOR 
						SELECT t.MasterTableName, t.DetailsTableName, t.DetailColumnsName FROM #TempForeignKeys t
						WHERE ObjectID
						NOT IN (SELECT ObjectID FROM #TempIndexedFK)

				-- Details of the foreign key on which the index is being created
				DECLARE		@master		nvarchar(100)		-- The name of the master table
				,			@detail		nvarchar(100)		-- The name of the table that refers to the master table
				,			@detailCol	nvarchar(100)		-- The name of the column that references the master table

				OPEN CC
				FETCH NEXT FROM CC INTO @master, @detail, @detailCol
				WHILE (@@FETCH_STATUS = 0)
				BEGIN
					SET @sql = N'USE [' + @db + N']; '
					+ 'CREATE INDEX FKI_' + @master + '_' + @detail
					+ ' ON ' + @detail + N' (' + @detailCol + N')'

					EXEC sp_sqlexec @sql
		
					FETCH NEXT FROM CC INTO @master, @detail, @detailCol
				END
				CLOSE CC
				DEALLOCATE CC
		END
GO

EXEC [dbo].create_indexes_on_foreign_keys @db='InvoiceDB'

-- An auxiliary procedure to display all foreign keys without indexes
IF NOT EXISTS 
(	SELECT 1 
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = 'show_fk_with_indexes')
		AND		(OBJECTPROPERTY(o.[ID],'IsProcedure')=1)
)
BEGIN
	DECLARE @stmt nvarchar(100)
	SET @stmt = 'CREATE PROCEDURE dbo.show_fk_with_indexes AS '
	EXEC sp_sqlexec @stmt
END
GO

ALTER PROCEDURE [dbo].show_fk_with_indexes
AS

	CREATE TABLE #TempForeignKeys 
		(
			MasterTableName varchar(100),	-- The name of the master table
			DetailsTableName varchar(100),	-- The name of the table that refers to the master table
			DetailColumnsName varchar(100), -- The name of the column that references the master table
			ForeignKeyName varchar(100),	-- The name of the foreign key
			ObjectID int					-- Foreign key identifier
		)

-- Fill this table
	INSERT INTO #TempForeignKeys 
		SELECT 
			OBJECT_NAME(fk.referenced_object_id) as [masterName],
			o.[name] as [detailName],
			COL_NAME(fkc.parent_object_id, fkc.parent_column_id),
			fk.[name] as [fkName], 
			fk.[object_id] as [objectId] 
		FROM sys.foreign_keys fk
		INNER JOIN sys.objects o
		ON o.[object_id] = fk.[parent_object_id]
		INNER JOIN sys.foreign_key_columns fkc
		ON fk.[object_id] = fkc.constraint_object_id
		WHERE o.is_ms_shipped = 0			-- User-created indexes only

-- Create a temporary table to store the foreign key index IDs
	CREATE TABLE #TempIndexedFK (ObjectID int)

-- Fill this table
		INSERT INTO #TempIndexedFK  
		SELECT ObjectID
		FROM sys.foreign_key_columns fkc
		JOIN sys.index_columns i
		ON fkc.parent_object_id = i.[object_id]
		JOIN #TempForeignKeys fk
		ON  fkc.constraint_object_id = fk.ObjectID
		WHERE fkc.parent_column_id = i.column_id;
			
-- List all foreign keys without indexes
		SELECT * FROM #TempForeignKeys WHERE ObjectID IN (SELECT ObjectID FROM #TempIndexedFK)
GO

USE InvoiceDB
GO

-- Show foreign keys with indexes
EXEC [dbo].show_fk_with_indexes

/*
MasterTableName   DetailsTableName   DetailColumnsName    ForeignKeyName    ObjectID
---------------   ----------------   ------------------   ---------------   -----------
*/

-- Create indexes on foreign keys without indexes
EXEC [dbo].create_indexes_on_foreign_keys @db='InvoiceDB'

-- Show foreign keys with indexes
EXEC [dbo].show_fk_without_indexes

/*
MasterTableName    DetailsTableName     DetailColumnsName    ForeignKeyName               ObjectID
----------------- --------------------- -------------------- ---------------------------- -----------
klienci            faktury              klient_id            fk_faktury_klienci           82099333
klienci            szczegolyFaktury     nazwaKlienta         fk_klienci_szczegolyFaktury  594101157
faktury            pozycje              faktura_id           fk_pozycje_faktury           114099447
faktury            szczegolyFaktury     numerFaktury         fk_faktury_szczegolyFaktury  578101100
*/

-- We call the procedure again to check that the indexes will not be duplicated
EXEC [dbo].create_indexes_on_foreign_keys @db='InvoiceDB'

-- Show foreign keys with indexes
EXEC [dbo].show_fk_without_indexes

/*
MasterTableName    DetailsTableName     DetailColumnsName    ForeignKeyName               ObjectID
----------------- --------------------- -------------------- ---------------------------- -----------
klienci            faktury              klient_id            fk_faktury_klienci           82099333
klienci            szczegolyFaktury     nazwaKlienta         fk_klienci_szczegolyFaktury  594101157
faktury            pozycje              faktura_id           fk_pozycje_faktury           114099447
faktury            szczegolyFaktury     numerFaktury         fk_faktury_szczegolyFaktury  578101100
*/