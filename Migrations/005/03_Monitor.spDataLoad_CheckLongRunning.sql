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
		AND [name] = 'spDataLoad_CheckLongRunning'
)
BEGIN
	EXEC('CREATE PROCEDURE [Monitor].[spDataLoad_CheckLongRunning] AS BEGIN SET NOCOUNT ON; END');
END
GO


ALTER PROCEDURE [Monitor].[spDataLoad_CheckLongRunning]
WITH EXECUTE AS OWNER

AS

SET NOCOUNT ON;

/*
select top 10 * from DataLoad.ManualLoads with(nolock) order by DLManualLoadId desc
*/

DECLARE
	@Subject		varchar(200)	= 'Data Loads Running Long',
	@MinutesFrom	int				= 61,
	@MinutesThru	int				= 70,
	@Body			varchar(max)	= '',
	@ManualLoads	varchar(max)	= '',
	@Logs			varchar(max)	= '';



SELECT
	@ManualLoads = @ManualLoads +
	'<tr>' +
	'<td>' + CONVERT(varchar(20), ml.DLManualLoadId) + '</td>' +
	'<td>' + ml.OriginalFileName + '</td>' +
	'<td>' + COALESCE(c.DBCatalog, '') + '</td>' +
	'</tr>' + CHAR(13) + CHAR(10)
FROM
	DataLoad.ManualLoads	AS ml	WITH(NOLOCK)
		LEFT OUTER JOIN
	DataLoad.Clients		AS c	WITH(NOLOCK)
		ON	ml.DLClientId	= c.DLClientId
WHERE
	ml.ReadyToProcessDt IS NULL
	AND DATEDIFF(minute, ml.PickedUpDt, CURRENT_TIMESTAMP) BETWEEN @MinutesFrom AND @MinutesThru;



SELECT
	@Logs = @Logs +
	'<tr>' +
	'<td>' + CONVERT(varchar(20), l.DLLogId) + '</td>' +
	'<td>' + COALESCE(c.DBCatalog, '') + '</td>' +
	'<td>' + CONVERT(varchar(10), l.ADSProfileId) + '</td>' +
	'<td>' + l.MRN + '</td>' +
	'<td>' + l.EncounterId + '</td>' +
	'</tr>' + CHAR(13) + CHAR(10)
FROM
	DataLoad.Logs			AS l	WITH(NOLOCK)
		INNER JOIN
	DataLoad.Clients		AS c	WITH(NOLOCK)
		ON	l.DLClientId	= c.DLClientId
WHERE
	l.StartTime IS NOT NULL
	AND l.FinishTime IS NULL
	AND DATEDIFF(minute, l.StartTime, CURRENT_TIMESTAMP) BETWEEN @MinutesFrom AND @MinutesThru
ORDER BY
	l.DLLogId;



IF @ManualLoads != '' BEGIN
	SET @Body = @Body + 'Data Loads Manual Loads<br />' + CHAR(13) + CHAR(10) +
	'<table border="1">' +
	'<tr><th>DLManualLoadId</th><th>OriginalFileName</th><th>DBCatalog</th></tr>' +
	@ManualLoads +
	'</table><br />' + CHAR(13) + CHAR(10);
END



IF @Logs != '' BEGIN
	SET @Body = @Body + 'Data Loads Logs<br />' + CHAR(13) + CHAR(10) +
	'<table border="1">' +
	'<tr><th>DLLogId</th><th>DBCatalog</th><th>ADSProfileId</th><th>MRN</th><th>EncounterId</th></tr>' +
	@Logs +
	'</table><br />' + CHAR(13) + CHAR(10);
END



IF @Body != '' BEGIN
	SET @Body = '<style>th{text-align:left;}</style>' +
	'The following Data Loads have been running for over an hour and are not complete.<br />' + CHAR(13) + CHAR(10) +
	'This is the only Long Running notification you will receive about these Loads.<br />' + CHAR(13) + CHAR(10) +
	'<br />' +
	@Body;



	EXEC dbo.sp_send_dbmail
		@profile_name	= 'default',
		@recipients		= 'jason.rose@accuityhealthcare.com;zachary.west@accuityhealthcare.com',
		@subject		= @Subject,
		@body_format	= 'HTML',
		@body			= @Body;
END



SET NOCOUNT OFF;
GO
