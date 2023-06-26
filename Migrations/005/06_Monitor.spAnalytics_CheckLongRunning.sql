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
		AND [name] = 'spAnalytics_CheckLongRunning'
)
BEGIN
	EXEC('CREATE PROCEDURE [Monitor].[spAnalytics_CheckLongRunning] AS BEGIN SET NOCOUNT ON; END');
END
GO


ALTER PROCEDURE [Monitor].[spAnalytics_CheckLongRunning]
WITH EXECUTE AS OWNER

AS

SET NOCOUNT ON;

/*
EXEC [Monitor].[spAnalytics_CheckLongRunning]
*/

DECLARE
	@Subject				varchar(200)	= 'Analytics Queue Running Long',
	@Body					varchar(max)	= '',
	@HourLookback			int				= 4,
	@QueueSize				int;



SELECT
	@QueueSize = COUNT(*)
FROM
	Analytics.DRGQueue	WITH(NOLOCK)
WHERE
	FinishedAnalysisDt IS NULL
	AND AddDt <= DATEADD(hour, -@HourLookback, CURRENT_TIMESTAMP);



IF @QueueSize > 0 BEGIN
	SET @Body = '<style>th{text-align:left;}</style>' +
	'There are currently ' + CONVERT(varchar(10), @QueueSize) + ' unfinished Encounters in Analytics.DRGQueue that were added at least ' + CONVERT(varchar(10), @HourLookback) + ' hours ago.<br />' + CHAR(13) + CHAR(10) +
	'This message will be repeated every hour until there are none.';
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
