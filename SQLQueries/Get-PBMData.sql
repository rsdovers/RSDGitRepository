WITH XMLNAMESPACES ('http://schemas.serviceml.org/smlif/2007/02' AS ns1
  , 'http://www.w3.org/2001/XMLSchema' AS xs
  , 'http://schemas.microsoft.com/sqlserver/DMF/2007/08' AS DMF
  , 'http://schemas.microsoft.com/sqlserver/sfc/serialization/2007/08' AS sfc
  , 'http://schemas.serviceml.org/sml/2007/02' AS sml)
 ,rs (xmlData) AS
 (
    SELECT TRY_CAST(BulkColumn AS XML) 
    FROM OPENROWSET(BULK N'/home/rsdovers/SQLAutomation/PBM/policy-result-2021-02-04.xml', SINGLE_BLOB) AS x
 )
 SELECT c.value('(DMF:EvaluationDetail/DMF:TargetQueryExpression/text())[1]', 'VARCHAR(1000)') AS [Target]
    , c.value('(DMF:EvaluationDetail/DMF:Parent/sfc:Reference/sml:Uri/text())[1]', 'VARCHAR(1000)') AS [Policy]
    , c.value('(DMF:EvaluationDetail/DMF:Result/text())[1]', 'VARCHAR(30)') AS [Result]
 FROM rs 
  CROSS APPLY xmlData.nodes('/PolicyEvaluationResults/ns1:model/xs:bufferSchema/ns1:definitions/ns1:document/ns1:data/xs:schema/DMF:bufferData/ns1:instances/ns1:document/ns1:data') AS t(c);