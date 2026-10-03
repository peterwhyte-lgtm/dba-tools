/*
Script Name : Get-LinkedServerInventory
Category    : migration
Purpose     : Inventory linked servers for migration and connectivity dependency mapping.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-linked-servers/)
Requires    : none beyond CONNECT SQL (the default login mapping to public makes every linked server visible); ALTER ANY LINKED SERVER once that mapping has been removed
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SELECT
    s.name AS linked_server_name,
    s.product,
    s.provider,
    s.data_source,
    s.location,
    s.catalog,
    s.is_data_access_enabled,
    s.is_rpc_out_enabled,
    CASE WHEN s.is_linked = 1 THEN 'Linked' ELSE 'Local' END AS status
FROM sys.servers AS s
WHERE s.is_linked = 1
ORDER BY s.name;

