USE DB_STAT
GO

-- Create procedure for creating database backup
IF NOT EXISTS 
(	SELECT 1 
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = 'backup_db')
		AND		(OBJECTPROPERTY(o.[ID],'IsProcedure')=1)
)
BEGIN
	DECLARE @stmt nvarchar(100)
	SET @stmt = 'CREATE PROCEDURE dbo.backup_db AS '
	EXEC sp_sqlexec @stmt
END
GO

ALTER PROCEDURE [dbo].backup_db (@db nvarchar(100), @path nvarchar(200))
AS
	DECLARE @sql	nvarchar(2000)				-- Variable to hold SQL command
	,		@fname	nvarchar(1000)				-- Backup file name

	SET @db = LTRIM(RTRIM(@db))					-- Remove leading and trailing spaces from the database name
	SET @path = LTRIM(RTRIM(@path))				-- Remove leading and trailing spaces from the file path

	IF @path NOT LIKE N'%\'						-- If the path does not have a '\' at the end
		SET @path = @path + N'\'				-- add it

	-- Set the file name according to the formula: <database name>_<date in the format (YYYYYMMDDHHMM)>
	SET @fname = REPLACE(REPLACE(CONVERT(nchar(19), GETDATE(), 126), N':', N'_'),'-','_')
	SET @fname = @path + RTRIM(@db)  + @fname + N'.bak'

	SET @sql = 'backup database ' + @db + ' to DISK= N''' + @fname + ''''

	EXEC sp_sqlexec @sql
GO

USE DB_STAT
GO

IF NOT EXISTS 
(	SELECT 1 
		from sysobjects o (NOLOCK)
		WHERE	(o.[name] = 'backup_all_db')
		AND		(OBJECTPROPERTY(o.[ID],'IsProcedure')=1)
)
BEGIN
	DECLARE @stmt nvarchar(100)
	SET @stmt = 'CREATE PROCEDURE dbo.backup_all_db AS '
	EXEC sp_sqlexec @stmt
END
GO

-- Create procedure for creating backup of ALL databases

ALTER PROCEDURE [dbo].backup_all_db (@path nvarchar(200))
AS
	DECLARE @sql	nvarchar(2000)				-- Variable to hold SQL command
	,		@fname	nvarchar(1000)				-- Backup file name

	SET @path = LTRIM(RTRIM(@path))				-- Remove leading and trailing spaces from the file path

	IF @path NOT LIKE N'%\'						-- If the path does not have a '\' at the end
		SET @path = @path + N'\'				-- add it

	DECLARE CC INSENSITIVE CURSOR FOR 
			SELECT d.name 
			FROM sys.databases d 
			WHERE d.database_id > 4
			AND NOT d.name = N'DB_STAT'
	DECLARE @db		nvarchar(100)				-- Name of the currently backed up database

	OPEN CC
	FETCH NEXT FROM CC INTO @db	
	WHILE (@@FETCH_STATUS = 0)
	BEGIN
		EXEC DB_STAT.dbo.backup_db @db = @db, @path = @path
		FETCH NEXT FROM CC INTO @db
	END
	CLOSE CC
	DEALLOCATE CC
GO

EXEC DB_STAT.dbo.backup_all_db @path = N'C:\Users\PC\'
