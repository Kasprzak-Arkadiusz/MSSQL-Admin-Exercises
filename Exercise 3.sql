USE DB_STAT
GO

-- Create a procedure to delete tables
IF EXISTS
( SELECT 1
	FROM sysobjects o
	WHERE	(o.[name] = 'pr_rmv_table')
	AND	(OBJECTPROPERTY(o.[ID],'IsProcedure')=1)
)
BEGIN
	DROP PROCEDURE pr_rmv_table
		
END
GO

USE InvoiceDB
GO

CREATE PROCEDURE [dbo].pr_rmv_table
(	@table_name nvarchar(100)
)
AS

-- The procedure checks if table named @table_name exists in database. If so, the procedure removes it
	DECLARE @stmt nvarchar(1000)

	IF EXISTS 
	( SELECT 1
		FROM sysobjects o
		WHERE	(o.[name] = @table_name)
		AND	(OBJECTPROPERTY(o.[ID],'IsUserTable')=1)
	)
	BEGIN
		SET @stmt = 'DROP TABLE ' + @table_name
		EXECUTE sp_executeSQL @stmt = @stmt
	END
GO

USE InvoiceDB
GO

-- Removing tables in the reverse order of their creation
EXEC pr_rmv_table @table_name='pozycje'
EXEC pr_rmv_table @table_name='faktury'
EXEC pr_rmv_table @table_name='klienci'

/*******************
* Definition of Tables
*********************/

CREATE TABLE dbo.klienci(
	klient_id		int				NOT NULL	Identity(1,1) primary key,
	NIP				nvarchar(20)	NOT NULL,
	nazwa			nvarchar(100)	NOT NULL,
	adres			nvarchar(100)	NOT NULL
)

CREATE TABLE dbo.faktury(
	faktura_id		int				NOT NULL	Identity(1,1) primary key,
	klient_id		int				NOT NULL
												constraint fk_faktury_klienci foreign key (klient_id)
												references klienci(klient_id),
	[data]			datetime		NOT NULL,
	numer			int				NOT NULL,
	anulowana		bit				NOT NULL
)

CREATE TABLE dbo.pozycje(
	faktura_id		int				NOT NULL
												constraint fk_pozycje_faktury foreign key 
												references faktury(faktura_id),
	opis			nvarchar(100)	NOT NULL,
	cena			money			NOT NULL
)

-- We put sample data into the customers (klienci) table
DELETE from klienci
INSERT INTO klienci values('1234', 'Spółka ZOO', 'Warszawa')
INSERT INTO klienci values('5678', 'Spółka ZOO', 'Warszawa')
SELECT * from klienci

USE DB_STAT
GO

-- Create table for logging
CREATE TABLE dbo.LOG_FA(
	numer_faktury	int				NOT NULL,
	nip_klienta		nvarchar(20)	NOT NULL,
	[data]			datetime		NOT NULL,
	anulowana		bit				NOT NULL
)

-- Create a trigger to write data to dbo.LOG_FA after inserting invoices into dbo.invoices (faktury)
USE InvoiceDB
GO

DROP TRIGGER INS_FA
GO

CREATE TRIGGER INS_FA
ON	dbo.faktury
AFTER INSERT
AS
BEGIN
	INSERT INTO DB_STAT.dbo.LOG_FA 
		SELECT i.faktura_id AS [numer faktury], k.NIP AS [NIP klienta], i.data, i.anulowana
		FROM inserted i
		JOIN klienci k
		ON i.klient_id = k.klient_id
END
GO

-- Test

INSERT INTO faktury values(1, GETDATE(), 1, 0)
INSERT INTO faktury values(2, GETDATE(), 1, 0)
SELECT * from faktury
SELECT * from DB_STAT.dbo.LOG_FA

-- Results
/*
faktura_id  klient_id   data                    numer       anulowana
----------- ----------- ----------------------- ----------- ---------
3           1           2022-02-10 13:39:22.963 1           0
4           2           2022-02-10 13:39:22.963 1           0

(4 rows affected)

numer_faktury nip_klienta          data                    anulowana
------------- -------------------- ----------------------- ---------
3             1234                 2022-02-10 13:39:22.963 0
4             5678                 2022-02-10 13:39:22.963 0

(2 rows affected)
*/

--  Create a trigger for dbo.clients. After modifying the client's tax identification number (NIP), 
--  the trigger modifies the value in the LOG_FA table

DROP TRIGGER UPD_NIP
GO

CREATE TRIGGER UPD_NIP
ON	dbo.klienci
FOR UPDATE
AS
BEGIN
	IF (UPDATE(NIP)	-- Check if the update affected the NIP field
	AND (SELECT 1 FROM inserted i join deleted d ON (i.klient_id = d.klient_id) -- Values ​​have been changed
		WHERE NOT (i.NIP = d.NIP)) IS NOT NULL)
	BEGIN
		CREATE TABLE #Table ([NIP_stare] nvarchar(20), [NIP_nowe] nvarchar(20))	-- Create a table of new and old NIP numbers
		INSERT INTO #Table SELECT d.NIP as [NIP_stare], i.NIP as [NIP_nowe]		-- Insert new and old NIP numbers into the table
			FROM deleted d
			JOIN inserted i
			ON i.klient_id = d.klient_id
			WHERE (i.klient_id = d.klient_id)

		DECLARE @staryNIP nvarchar(20), @nowyNIP nvarchar(20)
		SET @staryNIP = (SELECT t.NIP_stare FROM #Table t)
		SET @nowyNIP = (SELECT t.NIP_nowe FROM #Table t)

		UPDATE DB_STAT.dbo.LOG_FA	-- Update the NIP in dbo.LOG_FA
		SET nip_klienta = (
			SELECT @nowyNIP
			WHERE nip_klienta = @staryNIP) -- Connect based on old NIP values
		WHERE nip_klienta = @staryNIP

		DROP TABLE #Table
	END
END
GO

--Test
UPDATE klienci SET NIP = '2345'
WHERE klient_id = 1

UPDATE klienci SET NIP = '6789'
WHERE klient_id = 2

SELECT * FROM klienci
SELECT * FROM DB_STAT.dbo.LOG_FA

/* Results
klient_id   NIP                  nazwa                                                                                                adres
----------- -------------------- ---------------------------------------------------------------------------------------------------- ----------------------------------------------------------------------------------------------------
1           2345                 Spółka ZOO                                                                                           Warszawa
2           6789                 Spółka ZOO                                                                                           Warszawa

(2 rows affected)

numer_faktury nip_klienta          data                    anulowana
------------- -------------------- ----------------------- ---------
3             2345                 2022-02-10 13:39:22.963 0
4             6789                 2022-02-10 13:39:22.963 0

(2 rows affected)
*/

-- Create a trigger on dbo.invoice. After updating the "canceled" ("anulowana") field, save the changes to dbo.LOG_FA
-- "canceled" Field change  => search where the change occurred => change value

DROP TRIGGER UPD_FA
GO

CREATE TRIGGER UPD_FA 
ON  dbo.faktury
FOR UPDATE
AS
BEGIN
	IF( UPDATE(anulowana) -- The update was on this field
	AND EXISTS (SELECT * FROM inserted i join deleted d ON (i.faktura_id = d.faktura_id) -- Values ​​have been changed
		WHERE NOT (i.anulowana = d.anulowana)))
	BEGIN

		UPDATE DB_STAT.dbo.LOG_FA
		SET anulowana = i.anulowana
		FROM inserted i
		INNER JOIN DB_STAT.dbo.LOG_FA l ON i.faktura_id = l.numer_faktury

	END
END
GO

--test
UPDATE faktury SET anulowana = 1
WHERE faktura_id = 1

SELECT * FROM faktury
SELECT * FROM DB_STAT.dbo.LOG_FA 

/* Results
faktura_id  klient_id   data                    numer       anulowana
----------- ----------- ----------------------- ----------- ---------
1           1           2022-02-10 13:49:08.060 1           1
2           2           2022-02-10 13:49:08.063 1           0

(2 rows affected)

numer_faktury nip_klienta          data                    anulowana
------------- -------------------- ----------------------- ---------
1             1234                 2022-02-10 13:49:08.060 1
2             5678                 2022-02-10 13:49:08.063 0

(2 rows affected)
*/