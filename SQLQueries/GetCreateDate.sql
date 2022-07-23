Select name,create_date From sys.databases
--OR 
--sp_msforeachdb ' USE [?]; Select name,create_date From sys.databases 
--where database_id = DB_ID(''?'')'