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

IF NOT EXISTS (
	SELECT TOP 1
		1
	FROM
		sys.objects
	WHERE
		[type] = 'P'
		AND schema_name([schema_id]) = 'Monitor'
		AND [name] = 'spAnalytics_CheckQueueSize'
)
BEGIN
	EXEC('CREATE PROCEDURE [Monitor].[spAnalytics_CheckQueueSize] AS BEGIN SET NOCOUNT ON; END');
END
GO


ALTER PROCEDURE [Monitor].[spAnalytics_CheckQueueSize]
WITH EXECUTE AS OWNER

AS

SET NOCOUNT ON;

/*
select top 10 * from DataLoad.ManualLoads with(nolock) order by DLManualLoadId desc
EXEC [Monitor].[spAnalytics_CheckQueueSize]
*/

DECLARE
	@Subject				varchar(200)	= 'Analytics Queue Overloaded',
	@Body					varchar(max)	= '',
	@QueueThreshold			int				= 500,
	@QueueSize				int,
	@QueueSizeLastHour		int,
	@QueueCompleteLastHour	int,
	@CurrentHour			datetime		= DATEADD(HOUR, DATEPART(HOUR, CURRENT_TIMESTAMP), CONVERT(datetime, CONVERT(date, CURRENT_TIMESTAMP)));



SELECT
	@QueueSize			= COUNT(*),
	@QueueSizeLastHour	= COUNT(CASE WHEN AddDt >= DATEADD(HOUR, -1, @CurrentHour) THEN DRGQueueId END)
FROM
	Analytics.DRGQueue	WITH(NOLOCK)
WHERE
	FinishedAnalysisDt IS NULL
	AND AddDt <= @CurrentHour;



SELECT
	@QueueCompleteLastHour	= COUNT(*)
FROM
	Analytics.DRGQueue	WITH(NOLOCK)
WHERE
	DATEADD(HOUR, DATEPART(HOUR, FinishedAnalysisDt), CONVERT(datetime, CONVERT(date, FinishedAnalysisDt))) = DATEADD(HOUR, -1, @CurrentHour);



/***************************************************************************************************************************************************
* If there are unfinished Encounters that were added prior to the last hour, and nothing completed in the last hour, assume nothing is processing. *
***************************************************************************************************************************************************/
IF @QueueSize > @QueueSizeLastHour AND @QueueSizeLastHour > 0 AND @QueueCompleteLastHour = 0 BEGIN
	SET @Subject = 'Analytics Queue Stalled';
	SET @Body = '<style>th{text-align:left;}</style>' +
	'There are currently ' + CONVERT(varchar(10), @QueueSize) + ' unfinished Encounters in Analytics.DRGQueue.<br />' + CHAR(13) + CHAR(10) +
	CONVERT(varchar(10), @QueueSizeLastHour) + ' ' + CASE WHEN @QueueSizeLastHour = 1 THEN 'was' ELSE 'were' END + ' added in the last hour.<br />' + CHAR(13) + CHAR(10) +
	'None have completed in the last hour.<br />' + CHAR(13) + CHAR(10) +
	'This message will be repeated every hour until the completed Encounters count rises above 0.';
END ELSE IF @QueueSize >= @QueueThreshold BEGIN
	SET @Subject = 'Analytics Queue Overloaded';
	SET @Body = '<style>th{text-align:left;}</style>' +
	'There are currently ' + CONVERT(varchar(10), @QueueSize) + ' unfinished Encounters in Analytics.DRGQueue.<br />' + CHAR(13) + CHAR(10) +
	CONVERT(varchar(10), @QueueSizeLastHour) + ' ' + CASE WHEN @QueueSizeLastHour = 1 THEN 'was' ELSE 'were' END + ' added in the last hour.<br />' + CHAR(13) + CHAR(10) +
	CONVERT(varchar(10), @QueueCompleteLastHour) + ' ' + CASE WHEN @QueueCompleteLastHour = 1 THEN 'has' ELSE 'have' END + ' completed in the last hour.<br />' + CHAR(13) + CHAR(10) +
	'This message will be repeated every hour until the unprocessed Encounters count drops below ' + CONVERT(varchar(10), @QueueThreshold) + '.';
END



IF @Body != '' BEGIN
	EXEC dbo.sp_send_dbmail
		@profile_name	= 'default',
		@recipients		= 'jason.rose@accuityhealthcare.com;zachary.west@accuityhealthcare.com',
		@subject		= @Subject,
		@body_format	= 'HTML',
		@body			= @Body;
END



SET NOCOUNT OFF;
GO
