/* 
* SP_getGroupings.sql -- A stored procedure to:
*						1. return the groupings based on the parameters
*						
*					
*
* Parameters:
*				@CUI = the driving CUI for the groupings, this is going to be the CUI1 in the relationship 
*				@REL = The relationship to capture
*				@SAB = The source Vocabulary to use for the grouping
*
*
* Returns :
*				Children CUIs of the param @CUI
* Date Created: 07/21/2022
*
* Created By: Stanley G 
*
*/

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE OR ALTER PROCEDURE [UMLS].[sp_getGroupings]
(
	@CUI varchar(20), 
	@REL varchar(5), 
	@SAB varchar(5)
)

AS

SET NOCOUNT ON;


   select
   ROW_NUMBER() over ( order by t1.CUI2) as r_num,
   t1.CUI2, 
   t3.str
   from 
   umls.MRREL t1 
   inner join 
   umls.MRCONSO t2 
   on 
   t1.AUI1 = t2.AUI
   inner join 
   umls.MRCONSO t3
   on 
   t1.AUI2 = t3.AUI
   where 
   t1.cui1 = @CUI
   and 
   --	Source asserted concept unique identifier
   t1.STYPE1 = 'SCUI'
   and 
   t1.SUPPRESS = 'N'
   and 
   --has child relationship in a Metathesaurus source vocabulary
   t1.rel = @REL
   and 
   --source vocab is LOINC
   t1.SAB = @SAB
   order by t1.rel,t1.SAB