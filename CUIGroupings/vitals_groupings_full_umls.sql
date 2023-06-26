/* 
* vitals_groupings_full_umls.sql -- Script to group all of the Vital Signs into categories using UMLS metathesaurus
*
* Date Created: 06/06/2022
*
* Created By: Stanley G 
*
*/


--SP to create driver table of CUI groupings
IF OBJECT_ID('tempdb..#groups') IS NOT NULL BEGIN
	DROP TABLE #groups;
END

create table #groups (
idx int, 
cui varchar(10), 
cui_desc varchar(1000)
);

insert into #groups (idx, cui, cui_desc)
--vital signs , direct children from Loinc source vocab
exec [UMLS].[sp_getGroupings] 'C0518766', 'CHD', 'LNC';

select 
* 
from #groups;


--** OUTER LOOP ** Lex Norm from the groupings
DECLARE
	@cnt int = 1,
	@max int,
	@CUI_search nvarchar(20);

SELECT
	@max = max(idx)
FROM
	#groups;

	print(@max)

--table to hold the lex norms of the groupings 
--leaves out hemodynamics and o2, have to improve in future
IF EXISTS (
	SELECT
		*
	FROM
		INFORMATION_SCHEMA.TABLES
	WHERE
		TABLE_SCHEMA = 'UMLS'
		AND TABLE_NAME = 'CUI_LEX_NORMS'
)
BEGIN
DROP TABLE [UMLS].[CUI_LEX_NORMS]
END


create table [UMLS].[CUI_LEX_NORMS](
CUI varchar(15),
LUI varchar(15), 
SUI varchar(15), 
[str] varchar(1500),
CUI_LEX_NORM varchar(15), 
CUI_LEX_TUI varchar(10),
CUI_LEX_SEMANTIC_TYPE varchar(50)
);


--for each grouping , find lex norm CUIS, and put in the table
WHILE @cnt < @max + 1 
BEGIN

select 
@CUI_search = cui
from 
#groups
where 
idx = @cnt

print('searching for '+@CUI_search)

insert into [UMLS].[CUI_LEX_NORMS](
CUI,
LUI, 
SUI,
[str],
CUI_LEX_NORM, 
CUI_LEX_TUI,
CUI_LEX_SEMANTIC_TYPE)
 select 
 distinct 
   @CUI_search as CUI, 
   t1.LUI, 
   t1.SUI,
   t1.NSTR as [str], 
   t1.CUI as CUI_LEX_NORM, 
   sty.TUI, 
   sty.sty
   from 
   [UMLS].[MRXNS_ENG] t1
   inner join 
   [UMLS].[MRCONSO] con 
   on 
   t1.CUI = con.cui
   and 
   t1.LUI = con.LUI 
   and 
   t1.SUI = con.SUI
   inner join 
   umls.mrrel rel 
	on 
	rel.cui2 = @CUI_search
	and 
	rel.cui1 = t1.CUI 
	left outer join 
	[UMLS].[MRSTY] sty
	on 
	t1.CUI = sty.cui
	where 
	t1.lui in 
	(
	select 
	distinct lui
	from
	[UMLS].[MRXNS_ENG] t1 
	where 
	cui = @CUI_search
	)
	and 
	t1.cui != @CUI_search
	and 
	con.SUPPRESS = 'N'
	and 
	con.ISPREF = 'Y'
	and 
	con.STT = 'PF'

   SET @cnt = @cnt + 1;
END

--insert the groups as the lex norms for completness
insert into [UMLS].[CUI_LEX_NORMS](
CUI,
LUI, 
SUI,
[str],
CUI_LEX_NORM, 
CUI_LEX_TUI,
CUI_LEX_SEMANTIC_TYPE)
SELECT
distinct 
[CUI]
      ,null as [LUI]
      ,null as [SUI]
      ,null as [str]
      ,[CUI] as [CUI_LEX_NORM]
      ,null as[CUI_LEX_TUI]
      ,null as[CUI_LEX_SEMANTIC_TYPE]
  FROM [UMLS].[CUI_LEX_NORMS]


--set up inner loop to iterate though lex norms, for each getheir with group

IF OBJECT_ID('tempdb..#searchHeir') IS NOT NULL 
BEGIN
	DROP TABLE ..#searchHeir;
END

--table to hold the group and the mappings to search for in the hier, distinct
create table #searchHeir(
idx int,
group_cui varchar(10),
search_cui varchar(10)
)

insert into #searchHeir(
idx,
group_cui ,
search_cui )
select 
distinct 
ROW_NUMBER() over (order by cui) ,
t1.cui, 
t1.[CUI_LEX_NORM]
from 
(
select 
distinct 
--top 2
cui, 
[CUI_LEX_NORM]
from 
[UMLS].[CUI_LEX_NORMS] )t1 ;

declare
	@cnt_inner int = 1 ,
	@CUI_group nvarchar(20) = '',
	@CUI_search_inner nvarchar(20) = '', 
	@max_inner int, 
	@reset int = 0;

SELECT
	@max_inner = max(idx)
FROM
	#searchHeir;

	print(@max_inner)


select 
* 
from 
#searchHeir;
     

WHILE @cnt_inner < @max_inner + 1 
	BEGIN 
		IF(@cnt_inner = 1)
			BEGIN
				set @reset = @cnt_inner
			END
		ELSE 
			BEGIN
				set @reset = 0
			END
		
		SELECT
			@CUI_group = group_cui, 
			@CUI_search_inner = search_cui
		FROM
			#searchHeir
		WHERE
			idx = @cnt_inner;

		EXEC [UMLS].[sp_getHierarchy] @CUI_group, @CUI_search_inner, @reset;


		SET @cnt_inner = @cnt_inner + 1;
	END;

--   --then find terminal nodes in heirarchys, then add to the mapping
exec [UMLS].[sp_getPaths] @Empty_table_ind = 1;



--create the final table 

IF EXISTS (
	SELECT
		*
	FROM
		INFORMATION_SCHEMA.TABLES
	WHERE
		TABLE_SCHEMA = 'UMLS'
		AND TABLE_NAME = 'CUI_GROUPINGS'
)
BEGIN
	DROP TABLE [UMLS].CUI_GROUPINGS;
END


CREATE TABLE [UMLS].[CUI_GROUPINGS]
(
	[group_cui]		nchar(10)			NULL,
	[group_desc]			nvarchar(1500)	NULL,
	[group_semantic_type]				nvarchar(50)		NULL,
	[cui]						nchar(8)			NULL,
	[desc]						nvarchar(1500)		NULL,
	[semantic_type]				nvarchar(50)		NULL
);

INSERT INTO [UMLS].[CUI_GROUPINGS](
[group_cui],
[group_semantic_type],
[cui],
[semantic_type]				
)
select 
Distinct 
t1.group_cui, 
t2.sty, 
t1.terminal_cui, 
t3.sty
from 
(
select 
distinct 
group_cui, 
terminal_cui
from 
[UMLS].[MRHIER_VITALS_PATHS] 
union 
select 
distinct 
group_cui, 
search_cui as terminal_cui
from 
[UMLS].[MRHIER_VITALS_PATHS] 
)t1 
left outer join 
--get the semantic types of groups
UMLS.MRSTY t2 
on t1.group_cui = t2.CUI
left outer join 
--get the semantic types of mappings
UMLS.MRSTY t3
on t1.terminal_cui = t3.CUI;




----create temp table of descr group CUI, more general. Might want to mod to use loinc, don't know
IF OBJECT_ID('tempdb..#cui_names') IS NOT NULL BEGIN
	DROP TABLE #cui_names;
END



CREATE TABLE #cui_names
(
	CUI		nchar(8),
	[str]	nvarchar(max)
);


INSERT INTO #cui_names
SELECT DISTINCT
	t1.cui,
	t1.[str]
FROM
	(
		SELECT
			ROW_NUMBER() OVER (
				PARTITION BY
					con.cui
				ORDER BY
					mrank.[rank] DESC
			)	AS cui_name_rank,
			con.cui,
			con.[str]
		FROM
			UMLS.MRCONSO		AS con		WITH(NOLOCK)
				INNER JOIN
			(
				SELECT DISTINCT
					cui
				FROM
					[UMLS].[CUI_GROUPINGS]	WITH(NOLOCK)
			)	AS cuis
				ON	con.CUI	= cuis.cui
				LEFT OUTER JOIN
			UMLS.MRRANK			AS mrank	WITH(NOLOCK)
				ON	con.SAB			= mrank.SAB
				AND	con.TTY			= mrank.TTY
				AND	con.SUPPRESS	= mrank.SUPPRESS
		--WHERE
		--	con.SUPPRESS = 'N'
		--	and 
		--	con.ISPREF = 'Y'
		--	and 
		--	con.stt = 'PF'
			
	) t1
WHERE
	t1.cui_name_rank = 1;


--update the final table with the desc

update [UMLS].[CUI_GROUPINGS]
set group_desc = t2.str,
	[desc] = t3.str 
	from 
	[UMLS].[CUI_GROUPINGS] t1 
	left outer join 
	#cui_names t2 
	on 
	t1.group_cui = t2.cui
	left outer join 
	#cui_names t3
	on 
	t1.cui = t3.cui