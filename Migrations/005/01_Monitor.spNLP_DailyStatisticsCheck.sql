IF NOT EXISTS (
	SELECT TOP 1
		1
	FROM
		sys.schemas
	WHERE
		[name] = 'Monitor'
)
BEGIN
	EXEC('CREATE SCHEMA Monitor');
END
GO

CREATE or ALTER   PROCEDURE [Monitor].[spNLP_DailyStatisticsCheck] 
AS

DECLARE @TableOfStatistics varchar(max);

SET NOCOUNT ON;

DECLARE
	@Subject				varchar(200)	= 'Daily NLP Statistics Check ' + CAST(GetDate() AS varchar(30)),
	@Body					varchar(max)	= '';


CREATE TABLE #NlpDailyStatistics
( TypeOfStatistic Varchar(250) null,
  ValueOfStatistic Varchar(250) null,
  ExecutionTime Varchar(250) null);

Insert into #NlpDailyStatistics
	  ( TypeOfStatistic  ,
		ValueOfStatistic  ,
		ExecutionTime  )
values ('<b>Type Of Statistic</b>',
		'<b>Value Of Statistic</b>',
		'<b>Execution Time</b>');

		

Insert into #NlpDailyStatistics
exec [Monitor].[spNLP_NumberOfNotesFinishedPerMinuteToday] ;

Insert into #NlpDailyStatistics
exec [Monitor].[spNLP_AverageTimeToFinishNotesToday] ;

Insert into #NlpDailyStatistics
exec [Monitor].[spNLP_NumberOfNotesQueuedForProcessingToday] ;

Insert into #NlpDailyStatistics
exec [Monitor].[spNLP_NumberOfNotesFinishedToday] 

Insert into #NlpDailyStatistics
exec [Monitor].[spNLP_NumberOfNotesFinishedByEndPointToday] 


SELECT
    @Body = CAST((
        SELECT
            '<tr>' + 
            TypeOfStatistic + 
            ValueOfStatistic + 
            ExecutionTime +
            '</tr>'
        FROM (
            SELECT
                '<td>' + TypeOfStatistic + '</td>' as TypeOfStatistic,
                '<td>' + ValueOfStatistic + '</td>' as ValueOfStatistic ,
                '<td>' + ExecutionTime + '</td>' as ExecutionTime
            FROM #NlpDailyStatistics
			) AS DataColumns
        FOR XML PATH(''), TYPE
    ).value('.', 'NVARCHAR(MAX)') AS NVARCHAR(MAX) );

drop table #NlpDailyStatistics;

SELECT @Body = '<table  border="1">' + @Body + '</table>';

EXEC dbo.sp_send_dbmail
		@profile_name	= 'default',
		@recipients		= 'maya.taylor@accuityhealthcare.com',
		@subject		= @Subject,
		@body_format	= 'HTML',
		@body			= @Body;

SET NOCOUNT OFF;
GO