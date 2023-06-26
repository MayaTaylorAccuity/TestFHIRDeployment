/* 
* SP_getPaths.sql -- A stored procedure to:
*					1. create the paths table
*					2. create and populate the supporting columns 
*					
*
* Parameters:

*
*				@Empty_table_ind = Binary Flag to indicate if the main table should be emptied 
*
*
* Date Created: 07/19/2022
*
* Created By: Stanley G 
*
*/

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE OR ALTER PROCEDURE [UMLS].[sp_getPaths]
(
	@Empty_table_ind			Bit		= 0
)

AS

SET NOCOUNT ON;

/*
*/

--test to see if MRHIER_VITALS_PATHS table exists?
IF NOT EXISTS (
	SELECT
		*
	FROM
		INFORMATION_SCHEMA.TABLES
	WHERE
		TABLE_SCHEMA = 'UMLS'
		AND TABLE_NAME = 'MRHIER_VITALS_PATHS'
)
BEGIN

	CREATE TABLE [UMLS].[MRHIER_VITALS_PATHS]
(
	[GROUP_CUI]		nchar(8)		NOT NULL,
	[SEARCH_CUI]		nchar(8)		NOT NULL,
	[terminal_cui]		nchar(8)		NOT NULL,
	[terminal_aui]		nvarchar(9)		NOT NULL,
	[terminal_code]		nvarchar(100)		NULL,
	[terminal_str]		nvarchar(1500)		NULL,
	[path_context]		int				NOT NULL,
	[path_SAB]			nvarchar(40)	NOT NULL,
	[RELA]				nvarchar(100)		NULL,
	[path]				nvarchar(1100)		NULL,
	[path_depth]		int					NULL,
	[path_CUI]			nchar(8)			NULL,
	[path_aui]			nvarchar(20)		NULL,
	[path_code]			nvarchar(100)		NULL,
	[path_str]			nvarchar(1500)		NULL,
	[path_len]			int					NULL,
	[is_vital_sign]		int				 NULL,
	[vital_signs_index]			int,
	[vital_signs_group]			nvarchar(1500),
	[vital_signs_group_cui]		nchar(10),
	[vital_signs_subgroup]		nvarchar(1500),
	[vital_signs_subgroup_cui]	nchar(10)
);

--create indexes 
CREATE NONCLUSTERED INDEX IX_vitalP_termAUI
ON UMLS.MRHIER_VITALS_PATHS
(
	terminal_aui
);

CREATE NONCLUSTERED INDEX IXvital_pathAUI
ON UMLS.MRHIER_VITALS_PATHS
(
	path_aui
);

END





IF (@Empty_table_ind = 1)
BEGIN 

TRUNCATE TABLE [UMLS].[MRHIER_VITALS_PATHS];

END



--vitals paths 
INSERT INTO [UMLS].[MRHIER_VITALS_PATHS]
(
	[GROUP_CUI],
	[SEARCH_CUI],
	[terminal_cui],
	[terminal_aui],
	[path_context],
	[path_SAB],
	[RELA],
	[path],
	[path_depth],
	[path_aui],
	[path_len],
	[is_vital_sign]
)
SELECT
Distinct
	mrv.[GROUP_CUI],
	mrv.[SEARCH_CUI],
	mrv.[CUI]		AS terminal_cui,
	mrv.[AUI]		AS terminal_aui,
	mrv.[CXN]		AS path_context,
	mrv.[SAB]		AS path_SAB,
	mrv.[RELA],
	mrv.[PTR_JSON]	AS [path],
	pjson.[key]		AS path_depth,
	pjson.[value]	AS path_aui,
	MAX(pjson.[key]) OVER (
		PARTITION BY
			mrv.[PTR_JSON]
	)	AS path_len,
	null AS is_vital_sign
FROM
	UMLS.MRHIER_VITALS	AS mrv	WITH(NOLOCK)
		CROSS APPLY
	OPENJSON([PTR_JSON])	AS pjson;


--test to see if the aui terminal table exists
IF OBJECT_ID('tempdb..#aui_terminal') IS NOT NULL BEGIN
	DROP TABLE #aui_terminal;
END



CREATE TABLE #aui_terminal
(
	CUI		nchar(8),
	AUI		nvarchar(9),
	code	nvarchar(100),
	[str]	nvarchar(max)
);



--terminal AUIs
INSERT INTO #aui_terminal
SELECT DISTINCT
	conso.CUI,
	conso.AUI,
	conso.code,
	conso.[str]
FROM
	UMLS.MRCONSO				AS conso	WITH(NOLOCK)
		INNER JOIN
	UMLS.MRHIER_VITALS_PATHS	AS vit		WITH(NOLOCK)
		ON	conso.AUI				= vit.terminal_aui;



--test to see if the aui path table exists
IF OBJECT_ID('tempdb..#aui_path') IS NOT NULL BEGIN
	DROP TABLE #aui_path;
END



CREATE TABLE #aui_path
(
	CUI		nchar(8),
	AUI		nvarchar(9),
	code	nvarchar(100),
	[str]	nvarchar(max)
);



--path AUIs
INSERT INTO #aui_path
SELECT DISTINCT
	conso.CUI,
	conso.AUI,
	conso.code,
	conso.[str]
FROM
	UMLS.MRCONSO				AS conso	WITH(NOLOCK)
		INNER JOIN
	UMLS.MRHIER_VITALS_PATHS	AS vit		WITH(NOLOCK)
		ON	conso.AUI				= vit.path_aui;



--update terminal 
UPDATE mvp SET
	mvp.[terminal_code]	= child.code,
	mvp.[terminal_str]	= child.[str]
FROM
	UMLS.MRHIER_VITALS_PATHS	AS mvp
		INNER JOIN
	#aui_terminal					AS child
		ON	mvp.terminal_aui		= child.AUI;


--update path 
UPDATE mvp SET
	mvp.[path_CUI]	= parent.CUI,
	mvp.[path_code]	= parent.CODE,
	mvp.[path_str]	= parent.[STR]
FROM
	UMLS.MRHIER_VITALS_PATHS	AS mvp
		INNER JOIN
	#aui_path						AS parent
		ON	mvp.path_aui			= parent.AUI;







--update the depth of the vital signs node
UPDATE mvp SET
	mvp.[vital_signs_index] = mvp_index.vs_index
FROM
	UMLS.MRHIER_VITALS_PATHS	AS mvp
		INNER JOIN
	(
		SELECT
			[path_depth]	AS vs_index,
			[path]
		FROM
			UMLS.MRHIER_VITALS_PATHS	WITH(NOLOCK)
		WHERE
			[is_vital_sign] = 1
	)	AS mvp_index
		ON	mvp.[path]	= mvp_index.[path];



--create the groupings which is going to be vital sign index + 1 or the direct children of vital signs in heir
--not all of the hiers will have a grouping if the terminal node is the vital signs
UPDATE mvp SET
	mvp.[vital_signs_group]			= mvp_group.[path_str],
	mvp.[vital_signs_group_cui]		= mvp_group.[path_CUI],
	mvp.[vital_signs_subgroup]		= mvp_subgroup.[path_str],
	mvp.[vital_signs_subgroup_cui]	= mvp_subgroup.[path_CUI]
FROM
	UMLS.MRHIER_VITALS_PATHS	AS mvp
		INNER JOIN
	(
		SELECT
			[path_str],
			[path_CUI],
			[path]
		FROM
			UMLS.MRHIER_VITALS_PATHS	WITH(NOLOCK)
		WHERE
			path_depth = [vital_signs_index] + 1
	)	AS mvp_group
		ON	mvp.[path]	= mvp_group.[path]
	/*may not be a sub group depending on the depth of the path*/
		LEFT OUTER JOIN
	(
		SELECT
			[path_str],
			[path_CUI],
			[path]
		FROM
			UMLS.MRHIER_VITALS_PATHS	WITH(NOLOCK)
		WHERE
			path_depth = [vital_signs_index] + 2
	)	AS mvp_subgroup
		ON	mvp.[path]	= mvp_subgroup.[path];