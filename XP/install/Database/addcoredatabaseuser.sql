
USE [master]
GO
ALTER DATABASE  [$(DatabasePrefix)_$(DatabaseSuffix)] SET CONTAINMENT = PARTIAL
GO

USE [$(DatabasePrefix)_$(DatabaseSuffix)]
create user [$(UserName)] WITH PASSWORD = '$(Password)', DEFAULT_SCHEMA=[dbo]

GO
ALTER ROLE [aspnet_Membership_BasicAccess] ADD MEMBER [$(userName)]
GO
ALTER ROLE [aspnet_Membership_FullAccess] ADD MEMBER [$(userName)]
GO
ALTER ROLE [aspnet_Membership_ReportingAccess] ADD MEMBER [$(userName)]
GO
ALTER ROLE [aspnet_Profile_BasicAccess] ADD MEMBER [$(userName)]
GO
ALTER ROLE [aspnet_Profile_FullAccess] ADD MEMBER [$(userName)]
GO
ALTER ROLE [aspnet_Profile_ReportingAccess] ADD MEMBER [$(userName)]
GO
ALTER ROLE [aspnet_Roles_BasicAccess] ADD MEMBER [$(userName)]
GO
ALTER ROLE [aspnet_Roles_FullAccess] ADD MEMBER [$(userName)]
GO
ALTER ROLE [aspnet_Roles_ReportingAccess] ADD MEMBER [$(userName)]
GO
ALTER ROLE [db_datareader] ADD MEMBER [$(userName)]
GO
ALTER ROLE [db_datawriter] ADD MEMBER [$(userName)]

GRANT EXECUTE TO [$(userName)];
