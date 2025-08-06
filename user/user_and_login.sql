-- Connect as Windows admin first, then run:
SELECT CASE SERVERPROPERTY('IsIntegratedSecurityOnly')
    WHEN 1 THEN 'Windows Authentication Only - CHANGE THIS!'
    WHEN 0 THEN 'Mixed Mode Authentication - OK'
END AS AuthenticationMode;

USE master;

-- Drop login if it exists (and any associated users)
IF EXISTS (SELECT * FROM sys.server_principals WHERE name = 'dba_reader')
    DROP LOGIN dba_reader;

-- Drop user from AdventureWorks2019 if it exists
USE [AdventureWorks2019];
IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'dba_reader')
    DROP USER dba_reader;

-- Go back to master and create login
USE master;
CREATE LOGIN dba_reader 
WITH PASSWORD = 'TempPass123!',
     DEFAULT_DATABASE = [master],  -- Start with master, not AdventureWorks2019
     CHECK_EXPIRATION = OFF,
     CHECK_POLICY = OFF;

-- Verify login was created
SELECT 
    name, 
    is_disabled,
    default_database_name,
    type_desc
FROM sys.server_principals 
WHERE name = 'dba_reader';

USE [AdventureWorks2019];

-- Check if user exists in this database
SELECT name, type_desc 
FROM sys.database_principals 
WHERE name = 'dba_reader';

-- Create the database user for the login
CREATE USER dba_reader FOR LOGIN dba_reader;

-- Verify user was created
SELECT name, type_desc 
FROM sys.database_principals 
WHERE name = 'dba_reader';


USE [AdventureWorks2019];

-- Grant db_owner role (full database permissions)
ALTER ROLE [db_owner] ADD MEMBER [dba_reader];

-- Verify the role assignment
SELECT 
    dp.name AS PrincipalName,
    dp.type_desc AS PrincipalType,
    r.name AS RoleName
FROM sys.database_role_members rm
JOIN sys.database_principals dp ON rm.member_principal_id = dp.principal_id
JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
WHERE dp.name = 'dba_reader';