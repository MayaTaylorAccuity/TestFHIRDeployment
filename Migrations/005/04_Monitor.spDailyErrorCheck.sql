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
		AND [name] = 'spDailyErrorCheck'
)
BEGIN
	EXEC('CREATE PROCEDURE [Monitor].[spDailyErrorCheck] AS BEGIN SET NOCOUNT ON; END');
END
GO


ALTER PROCEDURE [Monitor].[spDailyErrorCheck]
(
	@AsOfDate		date	= null,
	@SendEmail		bit		= 0
)

AS

SET NOCOUNT ON;

/*
EXEC Monitor.spDailyErrorCheck


DECLARE @AsOfDate date = CURRENT_TIMESTAMP
EXEC Monitor.spDailyErrorCheck @AsOfDate;


DECLARE @AsOfDate date = '2/15/2023'
EXEC Monitor.spDailyErrorCheck @AsOfDate, 1;

*/

SET @AsOfDate = COALESCE(@AsOfDate, DATEADD(DAY, -1, CURRENT_TIMESTAMP));



DECLARE
	@Subject					varchar(200)	= 'Daily Error Alert for ' + CONVERT(varchar(10), @AsOfDate, 101),
	@Body						varchar(max)	= '',
	@ServiceBrokerErrors		varchar(max)	= '',
	@AnalyticsDRGQueueErrors	varchar(max)	= '',
	@DataLoadManualLoadsErrors	varchar(max)	= '',
	@DataLoadLogsErrors			varchar(max)	= '';



SELECT
	@DataLoadManualLoadsErrors = @DataLoadManualLoadsErrors +
	'<tr>' +
	'<td>' + CONVERT(varchar(20), ml.DLManualLoadId) + '</td>' +
	'<td>' + ml.OriginalFileName + '</td>' +
	'<td>' + COALESCE(c.DBCatalog, '') + '</td>' +
	'<td>' + ml.ErrorMsg + '</td>' +
	'</tr>' + CHAR(13) + CHAR(10)
FROM
	DataLoad.ManualLoads	AS ml	WITH(NOLOCK)
		LEFT OUTER JOIN
	DataLoad.Clients		AS c	WITH(NOLOCK)
		ON	ml.DLClientId	= c.DLClientId
WHERE
	CONVERT(DATE, ml.ReadyToProcessDt) = @AsOfDate
	AND ml.ErrorMsg != '';



SELECT
	@DataLoadLogsErrors = @DataLoadLogsErrors +
	'<tr>' +
	'<td>' + COALESCE(c.DBCatalog, '') + '</td>' +
	'<td>' + CONVERT(varchar(10), ca_rl.ADSProfileId) + '</td>' +
	'<td>' + l.MRN + '</td>' +
	'<td>' + l.EncounterId + '</td>' +
	'<td>' + CONVERT(varchar(10), l.ErrorCnt) + '</td>' +
	'<td>' + CONVERT(varchar(10), ca_rl.FinishTime, 101) + ' ' + CONVERT(varchar(8), ca_rl.FinishTime, 108) + '</td>' +
	'<td>' + ca_rl.ErrorMsg + '</td>' +
	'</tr>' + CHAR(13) + CHAR(10)
FROM
	(
		SELECT
			MRN,
			EncounterId,
			COUNT(*) AS ErrorCnt
		FROM
			DataLoad.Logs	WITH(NOLOCK)
		WHERE
			CONVERT(DATE, FinishTime) = @AsOfDate
			AND ErrorMsg != ''
		GROUP BY
			MRN,
			EncounterId
	)	AS l
		CROSS APPLY
	(
		SELECT TOP 1
			rl.DLLogId,
			rl.DLClientId,
			rl.ADSProfileId,
			rl.FinishTime,
			rl.ErrorMsg
		FROM
			DataLoad.Logs	AS rl	WITH(NOLOCK)
		WHERE
			rl.MRN = l.MRN
			AND rl.EncounterId = l.EncounterId
		ORDER BY
			rl.DLLogId DESC
	)	AS ca_rl
		INNER JOIN
	DataLoad.Clients		AS c	WITH(NOLOCK)
		ON	ca_rl.DLClientId	= c.DLClientId
WHERE
	ca_rl.ErrorMsg != ''
ORDER BY
	ca_rl.ErrorMsg,
	l.MRN,
	l.EncounterId;



SELECT
	@AnalyticsDRGQueueErrors = @AnalyticsDRGQueueErrors +
	'<tr>' +
	'<td>' + CONVERT(varchar(20), q.DRGQueueId) + '</td>' +
	'<td>' + COALESCE(c.DBCatalog, '') + '</td>' +
	'<td>' + CONVERT(varchar(10), q.ADSProfileId) + '</td>' +
	'<td>' + q.MRN + '</td>' +
	'<td>' + q.EncounterId + '</td>' +
	'<td>' + CASE q.RunNotesThruNLP WHEN 0 THEN 'No' WHEN 1 THEN 'Yes - New' ELSE 'Yes - All' END + '</td>' +
	'<td>' + q.ErrorMsg + '</td>' +
	'</tr>' + CHAR(13) + CHAR(10)
FROM
	Analytics.DRGQueue		AS q	WITH(NOLOCK)
		LEFT OUTER JOIN
	DataLoad.Clients		AS c	WITH(NOLOCK)
		ON	q.DLClientId	= c.DLClientId
WHERE
	CONVERT(DATE, q.FinishedAnalysisDt) = @AsOfDate
	AND q.ErrorMsg != ''
	AND q.ErrorMsg NOT LIKE 'No MindMap found%'
	AND q.ErrorMsg NOT LIKE 'No Working DRG found%';



SELECT
	@ServiceBrokerErrors = @ServiceBrokerErrors +
	'<tr>' +
	'<td>' + CONVERT(varchar(20), LogId) + '</td>' +
	'<td>' + SPSchema + '</td>' +
	'<td>' + SPName + '</td>' +
	'<td>' + ErrorMsg + '</td>' +
	'</tr>' + CHAR(13) + CHAR(10)
FROM
	ServiceBroker.Logs WITH(NOLOCK)
WHERE
	CONVERT(DATE, FinishTime) = @AsOfDate
	AND ErrorMsg != ''
ORDER BY
	LogId;



IF @DataLoadManualLoadsErrors != '' BEGIN
	SET @Body = @Body + 'Data Loads Manual Loads Errors<br />' + CHAR(13) + CHAR(10) +
	'<table border="1">' +
	'<tr><th>DLManualLoadId</th><th>OriginalFileName</th><th>DBCatalog</th><th>ErrorMsg</th></tr>' +
	@DataLoadManualLoadsErrors +
	'</table><br />' + CHAR(13) + CHAR(10);
END



IF @DataLoadLogsErrors != '' BEGIN
	SET @Body = @Body + 'Data Loads Logs Errors<br />' + CHAR(13) + CHAR(10) +
	'<table border="1">' +
	'<tr><th>DBCatalog</th><th>ADSProfileId</th><th>MRN</th><th>EncounterId</th><th>Error Count</th><th>Last Error Date</th><th>Last ErrorMsg</th></tr>' +
	@DataLoadLogsErrors +
	'</table><br />' + CHAR(13) + CHAR(10);
END



IF @AnalyticsDRGQueueErrors != '' BEGIN
	SET @Body = @Body + 'Analytics Queue Errors<br />' + CHAR(13) + CHAR(10) +
	'<table border="1">' +
	'<tr><th>DRGQueueId</th><th>DBCatalog</th><th>ADSProfileId</th><th>MRN</th><th>EncounterId</th><th>RunNotesThruNLP</th><th>ErrorMsg</th></tr>' +
	@AnalyticsDRGQueueErrors +
	'</table><br />' + CHAR(13) + CHAR(10);
END



IF @ServiceBrokerErrors != '' BEGIN
	SET @Body = @Body + 'Service Broker Errors<br />' + CHAR(13) + CHAR(10) +
	'<table border="1">' +
	'<tr><th>LogId</th><th>Schema</th><th>Procedure</th><th>Error</th></tr>' +
	@ServiceBrokerErrors +
	'</table><br />' + CHAR(13) + CHAR(10);
END



IF @Body != '' AND @SendEmail = 1 BEGIN
	SET @Body = '<style>th{text-align:left;}</style>' + @Body;
	EXEC dbo.sp_send_dbmail
		@profile_name	= 'default',
		@recipients		= 'jason.rose@accuityhealthcare.com;zachary.west@accuityhealthcare.com',
		@subject		= @Subject,
		@body_format	= 'HTML',
		@body			= @Body;
END
GO
