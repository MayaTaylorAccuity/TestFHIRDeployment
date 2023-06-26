/* 
* SP_getHeir.sql -- A stored procedure to:
*					1. get all of the AUIs of the param CUI
*					2. Get all of the Hierarchiies that contain the AUIs of the CUIs
*					3. Insert into the main table, param to empty table before insert
*
* Parameters:
*				@search_cui = Main CUI to search for all of the AUI => Hierarchies
*
*				@Empty_table_ind = Binary Flag to indicate if the main table should be emptied 
*
*
* Date Created: 07/19/2022
*
* Created By: Stanley G 
*
*/

USE [APOLLO]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE OR ALTER PROCEDURE [UMLS].[sp_getHierarchy]
(
	@group_cui     varchar(24) = null,
	@search_cui				varchar(24)		= null,
	@Empty_table_ind			Bit		= 0
)

AS

SET NOCOUNT ON;

/*
*/

--create a temp table of AIUs of the param CUI
IF NOT EXISTS (
	SELECT
		*
	FROM
		INFORMATION_SCHEMA.TABLES
	WHERE
		TABLE_SCHEMA = 'UMLS'
		AND TABLE_NAME = 'MRHIER_VITALS_AUI'
)
BEGIN
	CREATE TABLE [UMLS].[MRHIER_VITALS_AUI]
	(
		[key]	int,
		AUI		nvarchar(9)
	);

END


TRUNCATE TABLE [UMLS].[MRHIER_VITALS_AUI];



INSERT INTO [UMLS].[MRHIER_VITALS_AUI]
SELECT
	ROW_NUMBER() OVER (
		ORDER BY
			AUI
	),
	AUI
FROM
	UMLS.MRCONSO	WITH(NOLOCK)
WHERE
	CUI = @search_cui
	AND SUPPRESS = 'N';



--create the table to insert the subset to if not exists
IF NOT EXISTS (
	SELECT
		*
	FROM
		INFORMATION_SCHEMA.TABLES
	WHERE
		TABLE_SCHEMA = 'UMLS'
		AND TABLE_NAME = 'MRHIER_VITALS'
)
BEGIN
	
	--create the table
	CREATE TABLE [UMLS].[MRHIER_VITALS]
	(
		[GROUP_CUI]		nchar(8)		NOT NULL,
		[SEARCH_CUI]		nchar(8)		NOT NULL,
		[CUI]		nchar(8)		NOT NULL,
		[AUI]		nvarchar(9)		NOT NULL,
		[CXN]		int				NOT NULL,
		[PAUI]		nvarchar(10)		NULL,
		[SAB]		nvarchar(40)	NOT NULL,
		[RELA]		nvarchar(100)		NULL,
		[PTR]		nvarchar(1000)		NULL,
		[PTR_JSON]	nvarchar(1100)		NULL CONSTRAINT [CHK__UMLS__MRHIER_VITALS__PTR_JSON] CHECK (ISJSON(PTR_JSON) = 1),
		[HCD]		nvarchar(100)		NULL,
		[CVF]		int					NULL
	);


	--create index on AUI
CREATE NONCLUSTERED INDEX IX_hier_vital
ON [UMLS].[MRHIER_VITALS]
(
	AUI
);

END

--truncate the table if @Empty_table_ind is = 1 

IF (@Empty_table_ind = 1)
BEGIN 

TRUNCATE TABLE [UMLS].[MRHIER_VITALS];

END


--populate the table with CUI parameter
DECLARE
	@cnt int = 1,
	@max int,
	@aui nvarchar(20);

SELECT
	@max = max([key])
FROM
	[UMLS].[MRHIER_VITALS_AUI];

WHILE @cnt < @max + 1 BEGIN
	--get the aui
	SELECT
		@aui = aui
	FROM
		[UMLS].[MRHIER_VITALS_AUI]
	WHERE
		[key] = @cnt;


	PRINT(@aui);


	--insert the data 
	INSERT INTO [UMLS].[MRHIER_VITALS]
	(
		[GROUP_CUI]	,
		[SEARCH_CUI],
		[CUI],
		[AUI],
		[CXN],
		[PAUI],
		[SAB],
		[RELA],
		[PTR],
		[PTR_JSON],
		[HCD],
		[CVF]
	)
	SELECT
	distinct
		@group_cui,
		@search_cui,
		[CUI],
		[AUI],
		[CXN],
		[PAUI],
		[SAB],
		[RELA],
		[PTR],
		--create the array like json to explode later
		'["' + REPLACE([PTR], '.', '","') + '","' + [AUI] + '"]' as PTR_JSON,
		[HCD],
		[CVF]
	FROM
		[UMLS].[MRHIER]	WITH(NOLOCK)
	WHERE
		--want all of the paths that contain an aui of a vital sign
		CONTAINS([PTR], @aui);


	SET @cnt = @cnt + 1;
END