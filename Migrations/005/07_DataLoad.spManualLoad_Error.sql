IF NOT EXISTS (
	SELECT TOP 1
		1
	FROM
		sys.schemas
	WHERE
		[name] = 'DataLoad'
)
BEGIN
	EXEC('CREATE SCHEMA DataLoad');
END
GO

IF NOT EXISTS (
	SELECT TOP 1
		1
	FROM
		sys.objects
	WHERE
		[type] = 'P'
		AND schema_name([schema_id]) = 'DataLoad'
		AND [name] = 'spManualLoad_Error'
)
BEGIN
	EXEC('CREATE PROCEDURE [DataLoad].[spManualLoad_Error] AS BEGIN SET NOCOUNT ON; END');
END
GO


ALTER PROCEDURE [DataLoad].[spManualLoad_Error]
(
	@DLManualLoadId		bigint,
	@ErrorMsg			varchar(1000)
)
WITH EXECUTE AS OWNER

AS

SET NOCOUNT ON;

/*
select top 10 * from DataLoad.ManualLoads with(nolock) order by DLManualLoadId desc
*/

DECLARE
	@Subject					varchar(200)	= 'Manual Load Error',
	@Body						varchar(max)	= '';



UPDATE DataLoad.ManualLoads SET
	ReadyToProcessDt	= CURRENT_TIMESTAMP,
	ErrorMsg			= @ErrorMsg
WHERE
	DLManualLoadId = @DLManualLoadId
	AND ReadyToProcessDt IS NULL;



IF @@ROWCOUNT != 0 BEGIN
	SELECT
		@Body =
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
		ml.DLManualLoadId = @DLManualLoadId;



	SET @Body = '<style>th{text-align:left;}</style>' +
	'Data Loads Manual Load Errored<br />' + CHAR(13) + CHAR(10) +
	'<table border="1">' +
	'<tr><th>DLManualLoadId</th><th>OriginalFileName</th><th>DBCatalog</th><th>ErrorMsg</th></tr>' +
	@Body +
	'</table><br />' + CHAR(13) + CHAR(10);



	EXEC dbo.sp_send_dbmail
		@profile_name	= 'default',
		@recipients		= 'jason.rose@accuityhealthcare.com;zachary.west@accuityhealthcare.com',
		@subject		= @Subject,
		@body_format	= 'HTML',
		@body			= @Body;
END



SET NOCOUNT OFF;
GO

GRANT EXECUTE ON DataLoad.spManualLoad_Error TO ADF_FHIR_SP_User;
GO
