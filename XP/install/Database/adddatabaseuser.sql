
USE [master]
GO
ALTER DATABASE  [$(DatabasePrefix)_$(DatabaseSuffix)] SET CONTAINMENT = PARTIAL
GO

USE [$(DatabasePrefix)_$(DatabaseSuffix)]
create user [$(UserName)] WITH PASSWORD = '$(Password)', DEFAULT_SCHEMA=[dbo]

GO
EXEC sp_addrolemember 'db_datareader', [$(UserName)]
EXEC sp_addrolemember 'db_datawriter', [$(UserName)]
GO
GRANT EXECUTE to [$(UserName)]