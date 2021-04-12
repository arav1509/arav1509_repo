CREATE OR REPLACE PROCEDURE `rax-abo-72-dev`.cloud_uk.udsp_etl_cloud_account_contact_info_current()
/*
Created By Kano Canick 1/1/2011
Modified By: Larry Marshal 7/2/2015 included Sales and Keizan Attributes
Modified By: David Alvarez 7/6/2015 altered team logic to mirror Report_Tables.dbo.Historical_Keizan_Account_Facts.
Modified By: David Alvarez Changed load of #Keizan_XX to use local dbo.Cloud_Account_Team_Attributes WITH(nolock) from EBI-ODS-CORE.Keizan_ODS.dbo.Teams WITH(nolock) 
Modified By: David Alvarez 8/3/2015 Added logic to pull accounts when not available through HMDB ODS
Modified By: Kano Cannick 8/28/2015 alter proc to add in RC anf GCN
Modified By: Kano Cannick 9/24/2015 alter proc to add Account_Startup_Start_Date, Account_Startup_End_Date and update account_type
Modified By: Kano Cannick 4/8/2016  Added SF_Hierachy_Attribute_Key 
*/
begin
---------------------------------------------------------------------------------------------------------------	
DECLARE CURRENT_TMK int64;
SET CURRENT_TMK=`rax-abo-72-dev`.bq_functions.udf_yearmonth_nohyphen(current_date());
---------------------------------------------------------------------------------------------------------------	
CREATE OR REPLACE TEMP TABLE  start_up AS 
SELECT  --INTO	#Start_up
    CAST( replace(replace(ACCOUNT_NO,'020-',''),'021-','') as int64)					AS account_number,
    CASE 
	    WHEN 
			cast(current_datetime() as datetime) between cast(DATETIME_ADD(CAST('1970-01-01 00:00:00' AS datetime),interval CAST(max(PURCHASE_START_T) AS INT64) second) as datetime)
	    and cast(DATETIME_ADD(CAST('1970-01-01 00:00:00' AS datetime), interval CAST(max(PURCHASE_END_T) AS INT64) second) as datetime)
	    THEN 
		    1 
	    ELSE 
		    0 
    END AS Is_Startup,
    DATETIME_ADD(CAST('1970-01-01 00:00:00' AS datetime),interval CAST(max(PURCHASE_START_T) AS INT64)second) AS Startup_Start_Date,
	DATETIME_ADD(CAST('1970-01-01 00:00:00' AS datetime),interval CAST(max(PURCHASE_END_T) AS INT64)second) AS Startup_End_Date

FROM (
SELECT 
    a.ACCOUNT_NO,
    p.PURCHASE_START_T,
    p.PURCHASE_END_T
FROM 
   `rax-landing-qa`.brm_ods.deal_t d 
INNER JOIN 
    `rax-landing-qa`.brm_ods.purchased_product_t p 
ON d.POID_ID0 = p.DEAL_OBJ_ID0
INNER JOIN 
    `rax-landing-qa`.brm_ods.account_t a 
ON p.ACCOUNT_OBJ_ID0 = a.POID_ID0
WHERE 
    lower(d.DESCR) like '%startup%')
GROUP BY 
     CAST( replace(replace(ACCOUNT_NO,'020-',''),'021-','') as int64)
	;
	
---------------------------------------------------------------------------------------------------------------	
CREATE OR REPLACE TEMP TABLE rcn_temp AS 
SELECT * --INTO	#rcn
FROM (
SELECT 
    A.account_Number,
    customer_Number			 AS RCN,
    A.account_Source_System_name
FROM
	`rax-datamart-dev`.corporate_dmart.dim_account  A 
WHERE
	customer_Number IS NOT NULL
AND	A.current_Record = 1
AND upper(account_Source_System_name)='HOSTINGMATRIX_UK'
);
	
---------------------------------------------------------------------------------------------------------------	
CREATE OR REPLACE TEMP TABLE gcn AS 
SELECT * --into	#gcn
FROM (
SELECT  
    A.account_Number,
    GCN,
    account_Type
FROM
	`rax-datamart-dev`.corporate_dmart.gcn_match  A 
WHERE
	GCN IS NOT NULL
AND upper(account_Type)='HOSTINGMATRIX_UK'
);
	
---------------------------------------------------------------------------------------------------------------	
CREATE OR REPLACE TEMP TABLE rackconnect AS 
SELECT *  --into	#rackconnect
FROM(
SELECT  
    A.account_Number
FROM`rax-datamart-dev`.corporate_dmart.vw_sku_assignment  A 
where 
      cast(time_month_key as int64) = `rax-staging-dev`.bq_functions.udf_yearmonth_nohyphen(current_date()-1)--Convert(Varchar(8), Getdate()-1)
and ( lower(sku_name) like '%rackconnect%' or lower(sku_description) like '%rackconnect%')
and lower(device_online_status) = 'online'
group by     account_number)
	;

CREATE OR REPLACE TEMP TABLE USERS AS 
SELECT *  --into	#USERS
FROM (
SELECT 
	A.ID					AS User_ID,
	A.NAMEX				AS User,
	USERROLEID			AS User_Role_ID,
	ISACTIVE				AS User_IS_ACTIVE,
	C.NAMEX				AS User_Role,
	COMPANYNAME			AS Company_Name, 
	DIVISION				AS Division, 
	DEPARTMENT			AS Department, 
	TITLE				AS Title, 
	ISACTIVE				AS User_Active, 
	USERROLEID			AS Role_ID,
	MANAGERID				AS Manager_ID, 
	CREATEDDATE			AS Created_Date, 
	ISMANAGER				AS IsManager,
	USERNAME				AS Username,
	Region				AS Region,
	GROUPX				AS `Group`,
	SUB_GROUP				AS Sub_Group,
	DEFAULTCURRENCYISOCODE	AS Default_Currency_ISO_Code,
	EMPLOYEENUMBER		AS EMPLOYEE_NUMBER,
	EMPLOYEENUMBER			AS EMPLOYEENUMBER	
FROM
	`rax-landing-qa`.salesforce_ods.quser A  
LEFT OUTER JOIN
	`rax-landing-qa`.salesforce_ods.quserrole C 
ON A.USERROLEID= C.ID)
;

CREATE OR REPLACE TEMP TABLE QAccount AS
SELECT  --INTO QAccount
	A.ID								   AS SF_Account_ID,
	A.ACCOUNT_NUMBER					   AS SF_Core_Account_Number,
	ddi								   AS SF_DDI,
	LTRIM(RTRIM(A.NAMEX))				   AS SF_Account_Name,
	TYPEX							   AS SF_Account_Type, 
	SUB_TYPE							   AS SF_Account_Sub_Type,
	AM.User							   AS SF_Account_Manager,
	ACCOUNT_MANAGER					   AS SF_Account_Manager_ID,
	AM.User_Role						   AS SF_Account_Manager_Role,	
	AM.Group						   AS SF_Account_Manager_Group,
	AM.Sub_Group						   AS SF_Account_Manager_Sub_Group,	
	Acctowner.User					   AS SF_Account_Owner,
	A.OWNERID							   AS SF_Account_Owner_ID,
	Acctowner.EMPLOYEENUMBER				   AS SF_Account_Owner_Employee_Number,
	Acctowner.User_Role				   AS SF_Account_Owner_Role,
	Acctowner.Group					   AS SF_Account_Owner_Group,
	Acctowner.Sub_Group				   AS SF_Account_Owner_Sub_Group,
	'N/A'							   AS SF_GM, 	
	'N/A'							   AS SF_Director, 
	'N/A'							   AS SF_VP, 
	'N/A'							   AS SF_Manager, 
	'N/A'							   AS SF_Business_Unit,  
	'N/A'							   AS SF_Region,
	'N/A'							   AS SF_Segment,
	'N/A'							   AS SF_Sub_Segment,
	'N/A'							   AS SF_Team,
	'N/A'							   AS SF_Hierachy_Attribute_Key,
	'N/A'							   AS Hierarchy_Reporting_Group,
	LASTMODIFIEDDATE					   AS LASTMODIFIEDDATE
	
FROM
   (Select
	A.ID,
	A.NAMEX,
	A.TYPEX,
	ACC_Owner            AS OWNERID,
	A.ACCOUNT_NUMBER,
	A.SUB_TYPE,    
	A.ACCOUNT_MANAGER,    
	ddi,
	A.LASTMODIFIEDDATE 
	FROM
	`rax-landing-qa`.salesforce_ods.qaccounts  A                                                         
	WHERE  
	upper(A.DELETE_FLAG)='N'
	-- AND A.TYPEX IN (''Cloud Customer'',''Former Cloud Customer'')
	AND DDI IS NOT NULL ) A	
LEFT OUTER JOIN
	USERS Acctowner
ON A.OWNERID =Acctowner.User_ID
LEFT OUTER JOIN
	USERS Am
ON A.ACCOUNT_MANAGER=AM.User_ID
;
-----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE TEMP TABLE QAccount_DDI AS
SELECT--INTO    #QAccount_DDI
    SF_Account_ID,
    SF_Core_Account_Number,
    A.SF_DDI,
    SF_Account_Name,
    SF_Account_Type, 
    SF_Account_Sub_Type,
    SF_Account_Manager,
    SF_Account_Manager_ID,
    SF_Account_Manager_Role,	
    SF_Account_Manager_Group,
    SF_Account_Manager_Sub_Group,	
    SF_Account_Owner,
    SF_Account_Owner_ID,
    SF_Account_Owner_Employee_Number,
    SF_Account_Owner_Role,
    SF_Account_Owner_Group,
    SF_Account_Owner_Sub_Group,
    SF_GM, 	
    SF_Director, 
    SF_VP, 
    SF_Manager, 
    SF_Business_Unit,  
    SF_Region,
    SF_Segment,
    SF_Sub_Segment,
    SF_Team,
    SF_Hierachy_Attribute_Key,
    Hierarchy_Reporting_Group
FROM	 QAccount A
INNER JOIN
(
SELECT
    SF_DDI,
    MAX(LASTMODIFIEDDATE) AS MAX_LASTMODIFIEDDATE
FROM QAccount
GROUP BY
    SF_DDI
)B
 ON LASTMODIFIEDDATE=B.MAX_LASTMODIFIEDDATE
AND A.SF_DDI=B.SF_DDI
;

CREATE OR REPLACE TEMP TABLE Linked_Accounts AS
SELECT --into	#Linked_Accounts
    CAST(' ' as string)			    AS ACCOUNTID,
	Entity_number1					    AS Core_Account,
	CAST(entity_number2	as string)   AS DDI,
	Match_Time					    AS creation_date,
	Entity_number1					    AS Account_Num	
FROM (
SELECT 
	Entity_number1,
	entity_number2,
	Match_Time
FROM
	`rax-datamart-dev`.corporate_dmart.vw_entity_match  B  
WHERE  
	upper(Entity_source1)='SALESFORCE'
AND upper(Entity_source2) ='HOSTINGMATRIX'
AND upper(status) ='VERIFIED')
;


CREATE OR REPLACE TEMP TABLE Keizan_XX AS
SELECT --into	#Keizan_XX
    Keizan_Cloud_DDI,
    Keizan_Cloud_Segment,
    Keizan_Cloud_Region,
    Keizan_Cloud_Sub_Region,
    CASE WHEN `rax-staging-dev`.bq_functions.udf_is_numeric(Keizan_Core_Account)=0 then '0' else Keizan_Core_Account end as Keizan_Core_Account,
    Keizan_Cloud_BU,
    Keizan_Cloud_Team,
    Keizan_Cloud_Sub_Team,
    cast('1900-01-01' as datetime)			AS Keizan_Match_Date,
    Keizan_Cloud_AM,
    Keizan_Cloud_Onboarding_Specialist,
    Keizan_Cloud_Advisor,
    Keizan_Cloud_BDC,
    Keizan_Cloud_Tech_Lead, 
    Keizan_Cloud_Sales_Associate, 
    Keizan_Cloud_Launch_Manager,    
    Keizan_Cloud_TAM,
	Keizan_Cloud_Secondary_TAM
FROM(
SELECT 
    CAST(ddi as string)			AS Keizan_Cloud_DDI,
    MAX(`GROUP`)						AS Keizan_Cloud_Segment,
    MAX(REGION)						AS Keizan_Cloud_Region,
    MAX(subregion)						AS Keizan_Cloud_Sub_Region,
    CAST(CORE as string)			     AS Keizan_Core_Account,
    MAX(SEGMENT)						AS Keizan_Cloud_BU,
    MAX(TEAM)						AS Keizan_Cloud_Team,
    MAX(sub_team)						AS Keizan_Cloud_Sub_Team,
    MAX(AM)							AS Keizan_Cloud_AM,
    MAX(OnboardingSpecialist)			     AS Keizan_Cloud_Onboarding_Specialist,
    MAX(CloudAdvisor)				     AS Keizan_Cloud_Advisor,
    MAX(BusinessDevConsultant)		     AS Keizan_Cloud_BDC,
    MAX(TechLead)					     AS Keizan_Cloud_Tech_Lead, 
    MAX(SalesAssociate)				     AS Keizan_Cloud_Sales_Associate, 
    MAX(LaunchManager)				     AS Keizan_Cloud_Launch_Manager,    
    max(TAM)						     AS Keizan_Cloud_TAM,
    max(SecondaryTAM_FAWS)				AS Keizan_Cloud_Secondary_TAM
FROM
	`rax-landing-qa`.keizan_ods.teams_uk  B  
GROUP BY
	ddi,
	CORE)
;


UPDATE Keizan_XX k
SET
	k.Keizan_Match_Date=creation_date
FROM Keizan_XX A
INNER JOIN
	Linked_Accounts B
ON A.Keizan_Core_Account=cast(B.Core_Account as string)
where true;



create or replace table `rax-abo-72-dev`.cloud_uk.Keizan_Stage as
SELECT
    Keizan_Cloud_DDI,
    Keizan_Core_Account,
    Keizan_Cloud_BU,
    Keizan_Cloud_Region, 
    Keizan_Cloud_Sub_Region,
    Keizan_Cloud_Segment,
    Keizan_Cloud_Team,
    Keizan_Cloud_Sub_Team,
    Keizan_Match_Date,
    Keizan_Cloud_AM,
    Keizan_Cloud_Onboarding_Specialist,
    Keizan_Cloud_Advisor,
    Keizan_Cloud_BDC,
    Keizan_Cloud_Tech_Lead, 
    Keizan_Cloud_Sales_Associate, 
    Keizan_Cloud_Launch_Manager,    
    Keizan_Cloud_TAM,
    Keizan_Cloud_Secondary_TAM
FROM
(	
SELECT
	Keizan_Cloud_DDI		AS Min_DDI,
	MIN(Keizan_Match_Date)	AS Min_creation_date
 FROM Keizan_XX
GROUP BY
	Keizan_Cloud_DDI
)A
 INNER JOIN Keizan_XX B
ON A.Min_DDI=B.Keizan_Cloud_DDI
AND A.Min_creation_date=Keizan_Match_Date;

CREATE OR REPLACE TEMP TABLE team_all AS
SELECT * --INTO    #team_all
FROM
   (SELECT* FROM
    `rax-landing-qa`.ss_db_ods.team_all SSLteam 
WHERE 
    cast(deleted_at as date) = cast('1970-01-01' as date)
AND (subsegment IS NOT NULL 
and country IS NOT NULL 
and subsegment <> ' '
and country <> ' ')
)
;

CREATE OR REPLACE TEMP TABLE Keizan_ALL AS
SELECT   --INTO	#Keizan_ALL
    Keizan_Cloud_DDI,
    Keizan_Core_Account,
    Keizan_Match_Date,
    ifnull(SSLteam.country ,B.Country)					    AS Keizan_Country,
    ifnull(Keizan_Cloud_Region,B.Region)				    AS Keizan_Region,
    ifnull(Keizan_Cloud_Sub_Region,B.Sub_Region)			    AS Keizan_Sub_Region,
    ifnull(Keizan_Cloud_BU,B.Team_Business_Unit)			    AS Keizan_Business_Unit,
    ifnull(Keizan_Cloud_Segment,B.Team_Business_Segment)	    AS Keizan_Segment,
    ifnull(B.Team_Reporting_Segment, 'Other')			    AS Keizan_Reporting_Segment,
    ifnull(SSLteam.subsegment,B.Team_Business_Sub_Segment)    AS Keizan_Sub_Segment,
    Keizan_Cloud_Sub_Team							    AS Keizan_Cloud_Sub_Team,
    A.Keizan_Cloud_Team								    AS Keizan_Cloud_Team,
    A.Keizan_Cloud_AM								    AS Keizan_Cloud_AM,
    A.Keizan_Cloud_Onboarding_Specialist				    AS Keizan_Cloud_Onboarding_Specialist,
    A.Keizan_Cloud_Advisor							    AS Keizan_Cloud_Advisor,
    A.Keizan_Cloud_BDC								    AS Keizan_Cloud_BDC,
    A.Keizan_Cloud_Tech_Lead							    AS Keizan_Cloud_Tech_Lead, 
    A.Keizan_Cloud_Tech_Lead							    AS Keizan_Cloud_Sales_Associate, 
    A.Keizan_Cloud_Launch_Manager						    AS Keizan_Cloud_Launch_Manager,    
    A.Keizan_Cloud_TAM,
    A.Keizan_Cloud_Secondary_TAM	
FROM
	`rax-abo-72-dev`.cloud_uk.Keizan_Stage A
LEFT OUTER JOIN
	`rax-abo-72-dev`.report_tables.dim_support_team_hierarchy B 
ON A.Keizan_Cloud_Team=B.Team_Name
LEFT OUTER JOIN
    team_all	 SSLteam
On A.Keizan_Cloud_Team=SSLteam.name;

-----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE TEMP TABLE Max_invoiced AS
SELECT --INTO	#Max_invoiced
	Account								AS ACT_AccountID,
	CAST(MIN(invoice_Date) as date)	AS Min_Invoice_Date,
	CAST(MAX(invoice_Date) as date)	AS Max_Invoice_Date

FROM
	`rax-abo-72-dev`.cloud_uk.cloud_invoice_detail 
GROUP BY
	Account;
	
---------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE TEMP TABLE tempSLA AS
SELECT --into	#tempSLA
	substring(account_no, strpos(account_no,'-')+1,64)							AS ACCOUNT_ID,
	GL_SEGMENT																		AS GL_SEGMENT,
	CASE WHEN (upper(pd_VALUE) =  'TRUE' OR  upper(pd_VALUE) like '%MANAGED%') THEN 1 ELSE 0 END	AS MGD_FLAG,
	concat(NAME , '--' , pd_VALUE , ifnull(concat(' ', sla_VALUE), '')	)							AS SLA_NAME,
	DateTime_add(cast('1970-01-01 00:00:00' as datetime), interval cast(profile_Effective_T as int64) second) AS SLA_Effective_Date
FROM (
SELECT 
    a.account_no,
    GL_SEGMENT,
    PD.VALUE		    AS pd_VALUE,
    PD.NAME,		    
    sla.VALUE		    AS sla_VALUE,
    A.Effective_T	    AS Act_Effective_T,
    p.Effective_T	    AS profile_Effective_T		
From 
   `rax-landing-qa`.brm_ods.account_t A   
INNER JOIN
  `rax-landing-qa`.brm_ods.profile_t p 
on a.poid_id0 = p.Account_Obj_Id0
LEFT OUTER JOIN
   `rax-landing-qa`.brm_ods.profile_acct_extrating_data_t PD   
on PD.OBJ_ID0 = p.POID_ID0
LEFT OUTER JOIN 
    `rax-landing-qa`.brm_ods.profile_acct_extrating_data_t sla  
ON  p.POID_ID0 = sla.OBJ_ID0 
and upper(p.NAME) = 'MANAGED_FLAG'
AND upper(sla.NAME)='SERVICE_TYPE'
where 
    upper(PD.NAME)='MANAGED'
and upper(p.NAME) = 'MANAGED_FLAG'
AND upper(a.GL_SEGMENT) IN ('.CLOUD.UK'));

---------------------------------------------------------------------------------------------------------------
create or replace temp table dedicated as
SELECT --INTO	#dedicated
    number,
    id,
    parentAccountNumber,	
    parentAccountId,
    CAST (rcn as string) AS rcn
FROM (
SELECT    *
FROM
    `rax-landing-qa`.cms_ods.customer_account A 
WHERE
    type='MANAGED_HOSTING');

---------------------------------------------------------------------------------------------------------------

create or replace temp table Customer_Account as
SELECT--INTO   #Customer_Account
    number, 
    id, 
    CAST('N/A' as string)				   AS Account_Number,
    parentAccountNumber,
    parentAccountId, 
    name, 
    type, 
    status, 
    CAST(rcn as string)					  AS rcn,
    createdDate, 
    tier
FROM (
SELECT
    number, 
    A.id, 
    parentAccountNumber,
    parentAccountId, 
    name, 
    A.type, 
    A.status, 
    rcn,
    createdDate, 
    tier  
FROM
     `rax-landing-qa`.cms_ods.customer_account A 
WHERE
	 `rax-staging-dev`.bq_functions.udf_is_numeric(number)=1
AND upper(A.TYPE) IN ('CLOUD','SITES_ENDUSER') )
where
CAST(number as int64) >= 10000000
;
---------------------------------------------------------------------------------------------------    
UPDATE Customer_Account c
SET
  c.Account_Number=B.number
FROM Customer_Account A
INNER JOIN
  dedicated B
ON A.rcn=B.rcn
where true;



--------------------------------------------------------------------------------------------------- 
create or replace temp table ConcatenationDemo as
SELECT--INTO      #ConcatenationDemo
    Account,
    contactNumber,
    Number
FROM (
SELECT  
    A.number			   AS Account,
    phone.contactNumber,
    phone.Number
FROM 
      `rax-landing-qa`.cms_ods.customer_account A  
LEFT OUTER JOIN
    `rax-landing-qa`.cms_ods.contact_roles B  
ON A.number= B.customerAccountNumber
AND upper(B.CUSTOMERACCOUNTTYPE) IN ('CLOUD','SITES_ENDUSER') -- TO GET ONLY CLOUD FEEDS
AND upper(value)='PRIMARY'
AND A.type=customerAccountType
LEFT OUTER JOIN
   `rax-landing-qa`.cms_ods.contact_phonenumbers phone  
ON B.contactNumber= phone.contactNumber
WHERE
	`rax-staging-dev`.bq_functions.udf_is_numeric(A.number)=1
AND upper(A.TYPE) IN ('CLOUD','SITES_ENDUSER') -- TO GET ONLY CLOUD FEEDS
)
where
	CAST(Account as int64) >= 10000000
	;
---------------------------------------------------------------------------------------------------  
create or replace temp table Contact_PhoneNumbers as
SELECT --INTO    #Contact_PhoneNumbers
    Account,
    contactNumber, 
	STRING_AGG (Number,', ') as Phone
FROM  ConcatenationDemo AS x
GROUP BY 
    Account,contactNumber;

--------------------------------------------------------------------------------------------------- 
create or replace temp table Cloud_Account_Contact_Info as
SELECT --INTO	#Cloud_Account_Contact_Info
    ID									  AS Account_ID, 
    CAST('N/A' as string)				  AS Account_Number,
    contactNumber							  AS contactNumber,
    CAST(rcn as string)					  AS RCN,
    AccountName							  AS AccountName, 		
    status								  AS Account_Status,
    createdDate							  AS Account_Created_Date,
    extract(day from createdDate)						  AS DesiredBillingDate,
    FirstName,
    LastName, 
    username								  AS UserName,
    ifnull(CAST(REPLACE(SUBSTRING(SHD_EmailID,5,length(SHD_EmailID)),'-','') as int64),0)AS SHD_EmailID,
    ifnull(Address,'N/A')					  AS Email, 
    RTRIM(Street)							  AS Street,
    RTRIM(City)							  AS City, 
    RTRIM(ifnull(State,'Unknown'))				  AS State,
    RTRIM(zipcode)							  AS PostalCode, 
    RTRIM(Country)							  AS Country,
    code								  AS CountryCode,	
    current_date()								  AS Refresh_Date
FROM (
SELECT 
    A.Number								  AS ID, 
    B.contactNumber,
    A.Number								  AS Account_Number,
    A.rcn,
    A.Name								  AS AccountName, 		
    A.status,
    A.createdDate,
    PSN_Name.FirstName,
    PSN_Name.LastName, 
    PSN_Name.username,
    B.contactNumber						  AS SHD_EmailID,
    C.Address, 
    SHD_Address.Street,
    SHD_Address.City, 
    SHD_Address.State,
    SHD_Address.zipcode, 
    SHD_Country.Name						  AS Country,
    SHD_Country.code
FROM 
	`rax-landing-qa`.cms_ods.customer_account A  
LEFT OUTER JOIN
    `rax-landing-qa`.cms_ods.contact_roles B  
ON A.number= B.customerAccountNumber
AND upper(B.CUSTOMERACCOUNTTYPE) IN ('CLOUD','SITES_ENDUSER') -- TO GET ONLY CLOUD FEEDS
AND upper(value)='PRIMARY'
LEFT OUTER JOIN
    `rax-landing-qa`.cms_ods.customer_contact PSN_Name  
ON B.contactNumber= PSN_Name.contactNumber
LEFT OUTER JOIN
    `rax-landing-qa`.cms_ods.contact_emailaddress C  
ON B.contactNumber= C.contactNumber
AND C.primary is true
LEFT OUTER JOIN
    `rax-landing-qa`.cms_ods.contact_addresses SHD_Address  
ON B.contactNumber= SHD_Address.contactNumber
AND SHD_Address.primary is true
LEFT OUTER JOIN
    `rax-landing-qa`.cms_ods.countries SHD_Country  
ON SHD_Address.country= SHD_Country.code
WHERE
       A.type='Cloud'
AND `rax-staging-dev`.bq_functions.udf_is_numeric(A.number)=1
AND upper(A.TYPE) IN ('CLOUD','SITES_ENDUSER') -- TO GET ONLY CLOUD FEEDS
)
WHERE
	  CAST(ID as int64) >= 10000000
	  ;
----------------------------------------------------------------------------------------------------
create or replace temp table SSDB_Server_Level as 
SELECT --INTO	#SSDB_Server_Level
	DDI,
	service_level,
	service_type
FROM 
	(
SELECT  
	A.number		AS DDI,
	service_level,
	service_type
FROM 
	 `rax-landing-qa`.ss_db_ods.account_all A
WHERE
	upper(type)='CLOUD'
);

 
UPDATE Cloud_Account_Contact_Info c
SET
  c.Account_Number=B.number
FROM Cloud_Account_Contact_Info A
INNER JOIN dedicated B
ON A.rcn=B.rcn  
where true;

----------------------------------------------------------------------------------------------------
create or replace temp table Cloud_Account_Contact_Info_Current_All as 
SELECT --INTO	#Cloud_Account_Contact_Info_Current_All
    CAST(concat(CAST(A.Account_ID as string),'','Cloud_Hosting_UK') as string) AS Cloud_Account_Key,
    A.Account_ID							  AS Account_ID, 
    Account_Number,
    CAST(rcn as string)					  AS CMS_RCN,
    0				   					  AS SliceHost_CustomerID,
    AccountName, 		
    0									  AS Account_Tenure,	
    Account_Status,
    actstatus.ID                                                    AS Account_Status_ID,
    CASE	
    WHEN 
	    actstatus.Online<>1
    THEN
	    'Offline'
    ELSE
	    'Online'	
    END												   AS Account_Status_Online,
    actstatus.Online									   AS Account_Status_Online_ID,
    CAST('Cloud UK' as string)						   AS Account_Type,
    3												   AS Account_Type_ID,
	CAST('Cloud Customer'as string)					   AS Account_Customer_Type,
    'N/A'				   								   AS Account_SLAType,
    0												   AS Account_SLATypeID,
    'Infrastructure'									   AS Account_Service_Level,
    'legacy'											   AS Account_Service_Level_Type,
    0												   AS Account_Service_Level_ID,
    ifnull(MGD_FLAG,0)									   AS Is_Managed_Flag,
    ifnull(SLA_BRM_NAME,'unassigned')						   AS Account_SLA_Type_BRM_Desc,	    
    ifnull(SLAD.SLA_NAME,'unassigned')						   AS Account_SLA_Name_BRM,
    ifnull(SLAD.SLA_Type,'unassigned')						   AS Account_SLA_Type_BRM,     
    0												   AS Account_SLA_Name_BRM_Is_Managed,
    CAST(ifnull(SLA_Effective_Date,'1900-01-01') as datetime)		   AS Account_SLA_Type_BRM_Effective_Date,				    
    CAST(Account_Created_Date	as datetime)					   AS Account_Created_Date,
    CAST(ifnull(Max_Invoice_Date,Account_Created_Date)as datetime)  AS Account_End_Date,
    CAST(ifnull(Min_Invoice_Date,'1900-01-01')as datetime)		   AS Account_First_Billed_Date,
    CAST(ifnull(Max_Invoice_Date,'1900-01-01')as datetime)		   AS Account_Last_Billed_Date,
    extract(day from A.Account_Created_Date)							   AS DesiredBillingDate,
    0												   AS Consolidated_Billing,
    CAST('1900-01-01'	as datetime)							   AS Consolidated_Create_Date,
    0												   AS Managed_Flag,
    FirstName,
    LastName, 
    username										AS UserName,
    SHD_EmailID,
    Email, 
	ifnull(substr(Email,strpos(Email,'@')+1,length(Email)),'N/A') 
											AS Domain,		
    0									  AS Internal_Flag,
    0									  AS Domain_Internal_Flag,
    Phone, 
    Street,
    City, 
    State,
    PostalCode, 
    Country,
    CountryCode,	
    current_date()								  AS Refresh_Date

FROM  Cloud_Account_Contact_Info A  
LEFT OUTER JOIN
    Contact_PhoneNumbers p  
ON A.contactNumber= p.contactNumber
AND A.Account_ID=Account
LEFT OUTER JOIN
    `rax-abo-72-dev`.cloud_uk.act_val_accountstatus  actstatus
On A.Account_Status=actstatus.Name
LEFT OUTER JOIN
	Max_invoiced B
ON A.Account_ID = cast(B.ACT_AccountID as string)
LEFT OUTER JOIN
	tempSLA SLA
ON A.Account_ID =SLA.ACCOUNT_ID
LEFT OUTER JOIN
	`rax-abo-72-dev`.cloud_usage.dim_cloud_sla SLAD 
ON SLA.GL_SEGMENT=SLAD.GL_SEGMENT
AND SLA.SLA_NAME=SLAD.SLA_BRM_NAME;
----------------------------------------------------------------------------------------------------

UPDATE Cloud_Account_Contact_Info_Current_All A
SET
	A.Domain=ifnull(substr(Email,strpos(Email,'@')+1,length(Email)),'N/A') 
where true;
----------------------------------------------------------------------------------------------------
UPDATE Cloud_Account_Contact_Info_Current_All A
SET
	A.Account_Customer_Type='Former Cloud Customer'
WHERE
	lower(Account_Status)='closed';
-------------------------------------------------------------------------------------------------------------
UPDATE Cloud_Account_Contact_Info_Current_All 
 SET
	Account_Customer_Type=CASE
							WHEN
								Account_Last_Billed_Date >= cast(DATE_ADD(current_date(), interval -31 DAY) as date)
							AND Account_Last_Billed_Date <=  current_date()
							AND lower(Account_Status) not in('closed', 'close')
							THEN  
								'Cloud Customer'
							ELSE
								'Former Cloud Customer'
							END
where true;
-------------------------------------------------------------------------------------------------------------
UPDATE Cloud_Account_Contact_Info_Current_All
SET 
	Account_Tenure=
	ifnull(Date_diff( cast(Account_Created_Date as date),
			(CASE WHEN DATE_DIFF(cast(ifnull(cast(Account_Last_Billed_Date as date),cast(Account_End_Date as date)) as date),current_date(),day)>31 
			THEN current_date() 
			ELSE cast(Account_End_Date as date) END),day),0)
	--ifnull(ifnull(Account_Last_Billed_Date,CASE WHEN Account_End_Date='1900-01-01 00:00:00.000' THEn current_date() else Account_End_Date End),current_date())),0)
where true;
----------------------------------------------------------------------------------------------------
UPDATE  Cloud_Account_Contact_Info_Current_All 
SET	
	Domain_Internal_Flag=1			 
WHERE
  (lower(Domain) LIKE '%@rackspace%.co%' 
OR lower(Domain) LIKE '%@rackspace%'
OR lower(Domain) LIKE '%@racksapce%'
OR lower(Domain) LIKE '%@lists.rackspace%'
OR lower(Domain) LIKE '%@mailtrust%' 
OR lower(Domain) LIKE '%@mosso%' 
OR lower(Domain) LIKE '%@jungledisk%' 
OR lower(Domain) LIKE '%@slicehost%'
OR lower(Domain) LIKE '%@cloudkick%'
OR lower(Domain) like '%@ackspace%'
OR lower(Domain) like '%@test.com%'
OR lower(Domain) like '%@test.co.uk%'
OR lower(AccountName) like '%rackspace%'
OR lower(AccountName) like '%datapipe%'
)
;

UPDATE  Cloud_Account_Contact_Info_Current_All
SET	
	Internal_Flag=Domain_Internal_Flag		
where true;
----------------------------------------------------------------------------------------------------
UPDATE  Cloud_Account_Contact_Info_Current_All c
SET
    c.Account_Service_Level=ifnull(service_level,'infrastructure'), 
    c.Account_Service_Level_Type=ifnull(service_type, 'legacy') 
FROM
	Cloud_Account_Contact_Info_Current_All A
INNER JOIN 
	SSDB_Server_Level B
on a.Account_ID = B.DDI  
where true;
----------------------------------------------------------------------------------------------------   
UPDATE  Cloud_Account_Contact_Info_Current_All
SET
	Account_Service_Level_ID=1
WHERE
    lower(Account_Service_Level)='managed';
----------------------------------------------------------------------------------------------------
UPDATE  Cloud_Account_Contact_Info_Current_All 
SET
	Account_SLA_Name_BRM_Is_Managed=1
WHERE
    lower(Account_SLA_Name_BRM)='managed';
----------------------------------------------------------------------------------------------------   
UPDATE  Cloud_Account_Contact_Info_Current_All
SET
    Is_Managed_Flag=0,
    Account_SLA_Type_BRM_Desc='unassigned',
    Account_SLA_Name_BRM='unassigned',
    Account_SLA_Type_BRM='unassigned' 
WHERE
    Account_Type_ID=2;
----------------------------------------------------------------------------------------------------
create or replace temp table MAX_SHD_EmailID as 
SELECT --INTO    #MAX_SHD_EmailID
	Account_ID,
	MAX(SHD_EmailID) AS MAX_SHD_EmailID
FROM Cloud_Account_Contact_Info_Current_All A
GROUP BY
	Account_ID;

----------------------------------------------------------------------------------------------------
create or replace temp table Cloud_Account_Contact_Info_Current_Temp as
SELECT  --INTO    #Cloud_Account_Contact_Info_Current
    Cloud_Account_Key,
    A.Account_ID, 
    CAST(CMS_RCN as string)		AS CMS_RCN,
     CAST('N/A' AS string)		AS RCN,
    CAST('N/A' AS string)		AS GCN,
    Account_Number,
    SliceHost_CustomerID,
    AccountName, 		
    Account_Tenure,	
    Account_Status,
    Account_Status_ID,
    Account_Status_Online,
    Account_Status_Online_ID,
    Account_Type,
    Account_Type_ID,
	Account_Customer_Type,
    Account_SLAType,
    Account_SLATypeID,
    Account_Service_Level,
    Account_Service_Level_Type,
    Account_Service_Level_ID,
    Is_Managed_Flag,
    Account_SLA_Type_BRM_Desc,	    
    Account_SLA_Name_BRM,
    Account_SLA_Type_BRM,  
    Account_SLA_Name_BRM_Is_Managed,   
    Account_SLA_Type_BRM_Effective_Date,				    
    Account_Created_Date,
    Account_End_Date,
    Account_First_Billed_Date,
    Account_Last_Billed_Date,
    '1900-01-01'					 AS HMDB_Last_Billed_Date,
    DesiredBillingDate,
     '1900-01-01'				 AS ContractDate,
    Consolidated_Billing,
    Consolidated_Create_Date,
    Managed_Flag,
    FirstName,
    LastName, 
    UserName,
    SHD_EmailID,
    Email, 
    CAST(Domain as string)	 AS Domain,	
    Internal_Flag,
    Domain_Internal_Flag,
    Phone, 
    Street,
    City, 
    State,
    PostalCode, 
    Country,
    CountryCode,	
    Refresh_Date
FROM Cloud_Account_Contact_Info_Current_All A
INNER JOIN
    MAX_SHD_EmailID B
ON A.Account_ID=B.Account_ID
AND ifnull(A.SHD_EmailID,0)=ifnull(B.MAX_SHD_EmailID,0);


UPDATE Cloud_Account_Contact_Info_Current_Temp c
SET
   c.RCN=r.RCN
FROM
    Cloud_Account_Contact_Info_Current_Temp A
INNER JOIN
    rcn_temp	  AS r
ON A.Account_ID= r.account_Number
where true;
--------------------------------------------------------------------------------------------------- 
create or replace temp table Billing as
SELECT --INTO      #Billing
    Account,
    contactNumber,
    Number
FROM (
SELECT  
    A.number			   AS Account,
    phone.contactNumber,
    phone.Number
FROM 
      `rax-landing-qa`.cms_ods.customer_account A  
LEFT OUTER JOIN
    `rax-landing-qa`.cms_ods.contact_roles B  
ON A.number= B.customerAccountNumber
AND upper(B.CUSTOMERACCOUNTTYPE) IN ('CLOUD','SITES_ENDUSER') -- TO GET ONLY CLOUD FEEDS
AND upper(value)='BILLING'
LEFT OUTER JOIN
   `rax-landing-qa`.cms_ods.contact_phonenumbers phone  
ON B.contactNumber= phone.contactNumber
WHERE
	`rax-staging-dev`.bq_functions.udf_is_numeric(A.number)=1
 AND A.TYPE IN ('CLOUD','SITES_ENDUSER') -- TO GET ONLY CLOUD FEEDS
 )
WHERE CAST(Account as int64)  >= 10000000
;

---------------------------------------------------------------------------------------------------   
create or replace temp table Contact_BillingPhoneNumbers as
SELECT --INTO   #Contact_BillingPhoneNumbers
    Account,
    contactNumber, 
	STRING_AGG (Number,', ')  as Billing_Phone
FROM  Billing AS x
GROUP BY 
    Account,contactNumber;

--------------------------------------------------------------------------------------------------- 
create or replace temp table Billing_Contact_Info_ALL as
SELECT --INTO	#Billing_Contact_Info_ALL
    ID									  AS Account_ID, 
    contactNumber,
    AccountName							  AS Billing_AccountName, 	
    FirstName								  AS Billing_FirstName,
    LastName								  AS Billing_LastName, 
    ifnull(CAST(REPLACE(substr(SHD_EmailID,5,length(SHD_EmailID)),'-','') as int64),0)  AS SHD_EmailID,
    ifnull(Address,'N/A')					  AS Billing_Email,
    ifnull(substr(Address,strpos(Address,'@')+1,length(Address)),'N/A') 
										  AS Billing_Domain,	
    0									  AS Billing_Internal_Flag,
    0									  AS Billing_Domain_Internal_Flag,
    RTRIM(Street)							  AS Billing_Street,
    RTRIM(City)							  AS Billing_City, 
    RTRIM(ifnull(State,'Unknown'))				  AS Billing_State,
    RTRIM(zipcode)							  AS Billing_PostalCode, 
    RTRIM(Country)							  AS Billing_Country,
    code								  AS Billing_CountryCode	
FROM (
SELECT 
    A.Number								AS ID, 
    B.contactNumber,
    A.Number								  AS Account_Number,
    A.rcn,
    A.Name								  AS AccountName, 		
    A.status,
    actstatus.ID							  AS Account_Status_ID,
    A.createdDate,
    PSN_Name.FirstName,
    PSN_Name.LastName, 
    PSN_Name.username,
    B.contactNumber						  AS SHD_EmailID,
    C.Address, 
    SHD_Address.Street,
    SHD_Address.City, 
    SHD_Address.State,
    SHD_Address.zipcode, 
    SHD_Country.Name						  AS Country,
    SHD_Country.code
FROM 
	`rax-landing-qa`.cms_ods.customer_account A  
LEFT OUTER JOIN
    `rax-landing-qa`.cms_ods.account_statuses  actstatus  
On A.status=actstatus.status
AND  upper(status_source_system_name)='HMDB_US'
LEFT OUTER JOIN
    `rax-landing-qa`.cms_ods.contact_roles B  
ON A.number= B.customerAccountNumber
AND upper(B.CUSTOMERACCOUNTTYPE) IN ('CLOUD','SITES_ENDUSER') -- TO GET ONLY CLOUD FEEDS
AND value='BILLING'
LEFT OUTER JOIN
    `rax-landing-qa`.cms_ods.customer_contact PSN_Name  
ON B.contactNumber= PSN_Name.contactNumber
LEFT OUTER JOIN
    `rax-landing-qa`.cms_ods.contact_emailaddress C  
ON B.contactNumber= C.contactNumber
AND C.primary is true
LEFT OUTER JOIN
    `rax-landing-qa`.cms_ods.contact_addresses SHD_Address  
ON B.contactNumber= SHD_Address.contactNumber
AND SHD_Address.primary is true
LEFT OUTER JOIN
    `rax-landing-qa`.cms_ods.countries SHD_Country  
ON SHD_Address.country= SHD_Country.code
WHERE
       A.type='Cloud'
AND `rax-staging-dev`.bq_functions.udf_is_numeric(A.number)=1
AND upper(A.TYPE) IN ('CLOUD','SITES_ENDUSER') -- TO GET ONLY CLOUD FEEDS
)
WHERE
	CAST(ID as int64)  >= 10000000
	;

create or replace temp table MAX_Billing_SHD_EmailID as
SELECT --INTO    #MAX_Billing_SHD_EmailID
	Account_ID,
	MAX(SHD_EmailID) AS MAX_SHD_EmailID
FROM Billing_Contact_Info_ALL A
GROUP BY
	Account_ID;

----------------------------------------------------------------------------------------------------
UPDATE  Billing_Contact_Info_ALL b
SET	
	b.Billing_Internal_Flag=1,
    b.Billing_Domain_Internal_Flag=1
FROM
	Billing_Contact_Info_ALL A
WHERE
  (lower(A.Billing_Email) LIKE '%@rackspace%.co%' 
OR lower(A.Billing_Email) LIKE '%@rackspace%'
OR lower(A.Billing_Email) LIKE '%@racksapce%'
OR lower(A.Billing_Email) LIKE '%@lists.rackspace%'
OR lower(A.Billing_Email) LIKE '%@mailtrust%' 
OR lower(A.Billing_Email) LIKE '%@mosso%' 
OR lower(A.Billing_Email) LIKE '%@jungledisk%' 
OR lower(A.Billing_Email) LIKE '%@slicehost%'
OR lower(A.Billing_Email) LIKE '%@cloudkick%'
OR lower(A.Billing_Email) like '%@ackspace%'
OR lower(A.Billing_Email) like '%@test.com%'
OR lower(A.Billing_Email) like '%@test.co.uk%'
OR lower(A.Billing_AccountName) like '%rackspace%'
OR lower(A.Billing_AccountName) like '%datapipe%'
);
----------------------------------------------------------------------------------------------------
create or replace temp table Billing_Contact_Info as
SELECT  --INTO    #Billing_Contact_Info
     A.Account_ID, 
     Billing_AccountName, 
	Billing_FirstName,
	Billing_LastName, 
	Billing_Email, 
	CAST(Billing_Domain as string) AS Billing_Domain,
	Billing_Internal_Flag,
	Billing_Domain_Internal_Flag,
	Billing_Phone, 
	Billing_Street,
	Billing_City, 
	Billing_State,
	Billing_PostalCode, 
	Billing_Country,
	Billing_CountryCode
FROM Billing_Contact_Info_ALL A
LEFT OUTER JOIN
   Contact_BillingPhoneNumbers phone  
ON A.contactNumber= phone.contactNumber
INNER JOIN
    MAX_Billing_SHD_EmailID B
ON A.Account_ID = B.Account_ID --added 8/3/2015
AND ifnull(A.SHD_EmailID,0)=ifnull(B.MAX_SHD_EmailID,0);

---------------------------------------------------------------------------------------------------------
create or replace temp table CMS_Consolidated as
SELECT  --INTO    #CMS_Consolidated
      ACCOUNT_ID
      ,LINE_OF_BUSINESS
      ,ACCOUNT_NUMBER
      ,Consolidation_Account
      ,Consolidation_date
      ,Is_Consolidation_Account
FROM 
    `rax-abo-72-dev`.slicehost.brm_cloud_account_profile 
WHERE
    Is_Consolidation_Account=1
AND upper(LINE_OF_BUSINESS)='UK_CLOUD'
AND upper(BRM_ACCOUNT_NO) not like '%INCORRECT%';
---------------------------------------------------------------------------------------------------------
create or replace temp table CMS_Account_Attributes as
SELECT  --INTO    #CMS_Account_Attributes
    ACCOUNT_ID
    ,bdom
    ,LINE_OF_BUSINESS
    ,ACCOUNT_NUMBER
    ,Is_Racker_Account
    ,Is_Internal_Account
FROM 
   `rax-abo-72-dev`.slicehost.brm_cloud_account_profile 
WHERE
     upper(LINE_OF_BUSINESS)='UK_CLOUD'
AND upper(BRM_ACCOUNT_NO) not like '%INCORRECT%';
---------------------------------------------------------------------------------------------------------

create or replace table `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current as
SELECT  
    CAST(0 as int64)										   AS DW_Account_Key,
    Cloud_Account_Key, 
    A.Account_ID, 
    CMS_RCN,
    RCN,
    GCN,
    SF_Account_ID										   AS SF_Account_ID,
    SF_Account_Sub_Type,
    SF_Account_Sub_Type 									   AS SF_Account_Sub_Type_UWBL,
    SF_Account_ID										   AS QA_Account_ID,
    ifnull(Keizan_Core_Account,'-1')						   AS Keizan_Core_Account,
    ifnull(Keizan_Match_Date,'1900-01-01')					   AS Keizan_Match_Date,
    CAST('-1'	as string)								   AS Legally_Linked_Core_Account,
    CAST('1900-01-01'	as datetime)							   AS Legally_Linked_Date,
    Account_Number, 
    SliceHost_CustomerID, 
    AccountName, 
    Account_Tenure, 
    Account_Status, 
    Account_Status_ID,
    Account_Status_Online, 
    Account_Status_Online_ID, 
    Account_Type, 
    Account_Type_ID, 
	Account_Customer_Type,
    Account_SLAType, 
    Account_SLATypeID, 
    Account_Service_Level,
    Account_Service_Level_Type,
    Account_Service_Level_ID, 
    Is_Managed_Flag, 
    Account_SLA_Type_BRM_Desc, 
    Account_SLA_Name_BRM, 
    Account_SLA_Type_BRM, 
    Account_SLA_Name_BRM_Is_Managed,
    Account_SLA_Type_BRM_Effective_Date, 
    Account_Created_Date, 
    DesiredBillingDate										AS Account_Desired_Billed_Date,
    0													AS Account_BDOM_BRM,
    Account_First_Billed_Date, 
    Account_Last_Billed_Date,
    HMDB_Last_Billed_Date,
    Account_End_Date, 
	CAST('1900-01-01' as datetime)								AS Account_Startup_Start_Date,
	CAST('1900-01-01' as datetime)								AS Account_Startup_End_Date,
    ifnull(Keizan_Region,'Other')								AS Keizan_Region,
    ifnull(Keizan_Sub_Region,'Other')							AS Keizan_Sub_Region,		
    ifnull(Keizan_Business_Unit,'Other')						AS Keizan_Business_Unit,
    ifnull(Keizan_Segment,'Other')								AS Keizan_Segment,
    ifnull(Keizan_Reporting_Segment,'Other')						AS Keizan_Reporting_Segment,
    ifnull(Keizan_Sub_Segment,'Other')							AS Keizan_Sub_Segment,
    ifnull(Keizan_Cloud_Team,'Other')							AS Keizan_Cloud_Team,
    ifnull(Keizan_Cloud_Sub_Team,'Other')						AS Keizan_Sub_Team,		
    ifnull(Keizan_Cloud_AM,'Other')							AS Keizan_Cloud_AM,
    ifnull(Keizan_Cloud_Onboarding_Specialist,'Other')				AS Keizan_Cloud_Onboarding_Specialist,
    ifnull(Keizan_Cloud_Advisor,'Other')						AS Keizan_Cloud_Advisor,
    ifnull(Keizan_Cloud_BDC,'Other')							AS Keizan_Cloud_BDC,
    ifnull(Keizan_Cloud_Tech_Lead,'Other')						AS Keizan_Cloud_Tech_Lead, 
    ifnull(Keizan_Cloud_Tech_Lead,'Other')						AS Keizan_Cloud_Sales_Associate, 
    ifnull(Keizan_Cloud_Launch_Manager,'Other')					AS Keizan_Cloud_Launch_Manager,    
    ifnull(Keizan_Cloud_TAM,'Other')							AS Keizan_Cloud_TAM,
    ifnull(Keizan_Cloud_Secondary_TAM,'Other')					AS Keizan_Cloud_Secondary_TAM,
    ifnull(ifnull(SF_Business_Unit,SF_Account_Owner_Group),'Other')	AS SF_Business_Unit,
    ifnull(SF_GM,'Other')									AS SF_GM,
    ifnull(SF_VP,'Other')									AS SF_VP,
    ifnull(SF_Director,'Other')	 							AS SF_Director,
    ifnull(SF_Manager,'Other')	 							AS SF_Manager,
    ifnull(SF_Segment,'Other')								AS SF_Segment,
    ifnull(SF_Sub_Segment,'Other')		 						AS SF_Sub_Segment,
    ifnull(SF_Team,'Other')								     AS SF_Team,
    ifnull(SF_Account_Manager,'Other')							AS SF_Account_Manager,
    ifnull(SF_Account_Owner,'Other')							AS SF_Account_Owner,
    ifnull(SF_Account_Owner_Group,'Other')						AS SF_Account_Owner_Group,
    ifnull(SF_Account_Owner_Sub_Group,'Other')				     AS SF_Account_Owner_Sub_Group,
    ifnull(SF_Account_Owner_Employee_Number,'Other')				AS SF_Account_Owner_EmployeeNumber,
    ifnull(SF_Hierachy_Attribute_Key,'Other')					AS SF_Hierachy_Attribute_Key,
    CAST(CASE 
    WHEN 
    (SF_Core_Account_Number IS NOT NULL OR SF_Core_Account_Number<>'')
    THEN
    'Q_Account'
    ELSE
	   'HMDB'
    END	as string)									AS SF_Account_Source,
    0				   									AS ON_Net_Revenue_Plan,
    DesiredBillingDate, 
    ContractDate, 
   ifnull(Keizan_Core_Account,'-1')							 AS Consolidated_Account,
    CASE
    WHEN 
    Keizan_Core_Account IS NOT NULL 
    THEN
    1
    ELSE
    0
    END													AS Consolidated_Billing,
    ifnull(Keizan_Match_Date,'1900-01-01')						AS Consolidated_Create_Date, 
    CASE
    WHEN 
    Keizan_Core_Account IS NOT NULL 
    THEN
    1
    ELSE
    0
    END													AS Keizan_Linked_Account,
    0													AS Is_Legally_Linked_Account,
     0													AS Is_RackConnect_Linked,
    FirstName, 
    LastName, 
    UserName, 
    Email, 
    Domain, 
    Phone, 
    Street, 
    City, 
    State, 
    PostalCode, 
    Country, 
    CountryCode, 
    Billing_FirstName,
    Billing_LastName, 
    Billing_Email, 
    Billing_Domain,		
    Billing_Internal_Flag,
    Billing_Domain_Internal_Flag,
    Billing_Phone, 
    Billing_Street,
    Billing_City, 
    Billing_State,
    Billing_PostalCode, 
    Billing_Country,
    Billing_CountryCode,
    0						 AS Internal_Flag,
    CASE
    WHEN
	    (Domain_Internal_Flag+Billing_Internal_Flag)<> 0
    THEN
	    1
    ELSE
	    0
    END						 AS Domain_Internal_Flag, 
    0						 AS BRM_Internal_Account,
    0						 AS BRM_Racker_Account,
    Refresh_Date, 
    current_date()					 AS Load_Date

FROM
	Cloud_Account_Contact_Info_Current_Temp A
LEFT OUTER JOIN
	Keizan_ALL BB
ON A.Account_ID=BB.Keizan_Cloud_DDI
LEFT OUTER JOIN
    QAccount_DDI SCI 
ON CAST(A.Account_ID as string)=SF_DDI	
LEFT OUTER JOIN
    Billing_Contact_Info BI
ON A.Account_ID= BI.Account_ID;
----------------------------------------------------------------------------------------------------
create or replace temp table Cloud_US_Dim_account as
SELECT * --INTO	#Cloud_US_Dim_account
FROM (
SELECT 
    A.Account_Key,
    A.account_Number,
    A.account_Source_System_name
FROM
	`rax-datamart-dev`.corporate_dmart.dim_account  A 
WHERE
	A.current_Record = 1
AND upper(account_Source_System_name) In ('HOSTINGMATRIX_UK','CMS')
);

----------------------------------------------------------------------------------------------------
UPDATE `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current c
SET
	c.DW_Account_Key=Account_Key
FROM 
	`rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current A
INNER JOIN Cloud_US_Dim_account B
ON A.Account_ID= B.account_number
where true;
--------------------------------------------------------------------------------------------------
UPDATE `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current c
SET
	c.Account_Type='Cloud UK Startup',
	c.Account_Startup_Start_Date=Startup_Start_Date,
	c.Account_Startup_End_Date=Startup_End_Date
FROM `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current A
INNER JOIN
	start_up B
ON A.Account_ID= cast(B.account_number as string)
where true;
--------------------------------------------------------------------------------------------------
Update  `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current C
SET
    C.Is_RackConnect_Linked=1
FROM
    `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current  A 
 INNER JOIN
	rackconnect B
ON cast(A.Keizan_Core_Account as string)=cast(B.account_number as string)
where true;
----------------------------------------------------------------------------------------------------
UPDATE `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current C
SET
	 C.Is_Legally_Linked_Account=1,
     C.Legally_Linked_Date=creation_date,
     C.Legally_Linked_Core_Account=cast(Core_Account as string)
FROM
	`rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current A
INNER JOIN
	Linked_Accounts B
ON A.Account_ID=B.DDI
where true;
----------------------------------------------------------------------------------------------------
UPDATE `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current C
SET
	 C.Is_Legally_Linked_Account=1,
     C.Legally_Linked_Date=creation_date,
     C.Legally_Linked_Core_Account=cast(Core_Account as string)
FROM
	`rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current A
INNER JOIN
	Linked_Accounts B
ON A.Account_ID=B.DDI
WHERE TRUE;
----------------------------------------------------------------------------------------------------
UPDATE `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current C
SET
	C.Keizan_Core_Account='-1'
FROM
	`rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current A
WHERE
	A.Keizan_Core_Account = '0';
----------------------------------------------------------------------------------------------------
UPDATE `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current
SET
	Account_Customer_Type='Cloud Customer'
WHERE
	Account_Created_Date  >= cast(DATE_ADD(current_date(), INTERVAL -31 DAY) as date)
AND Account_Last_Billed_Date=CAST('1900-01-01' AS DATE)
AND LOWER(Account_Status) not in('closed', 'close');
----------------------------------------------------------------------------------------------------
UPDATE `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current C
SET
    C.Keizan_Core_Account=cast(B.Consolidation_Account as string),
    C.Keizan_Linked_Account=1,
    C.Keizan_Match_Date=Consolidation_date,  
    C.Consolidated_Account=cast(B.Consolidation_Account as string),
    C.Consolidated_Billing=1,
    C.Consolidated_Create_Date=Consolidation_date
FROM
    `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current A
INNER JOIN
    CMS_Consolidated B
On A.Account_ID= B.ACCOUNT_NUMBER
WHERE
    A.Keizan_Core_Account='-1';
----------------------------------------------------------------------------------------------------
UPDATE `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current c
SET
    c.Account_BDOM_BRM=cast(B.BDOM as int64),
    c.BRM_Internal_Account=Is_Internal_Account, 
    c.BRM_Racker_Account=Is_Racker_Account
FROM
    `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current  A
INNER JOIN
    CMS_Account_Attributes B
On A.Account_ID= B.ACCOUNT_NUMBER
where true;
----------------------------------------------------------------------------------------------------
UPDATE `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current  d
SET	
	d.Domain_Internal_Flag=1
WHERE
  (lower(d.Email) LIKE '%@rackspace%.co%' 
OR lower(d.Email) LIKE '%@rackspace%'
OR lower(d.Email) LIKE '%@racksapce%'
OR lower(d.Email) LIKE '%@lists.rackspace%'
OR lower(d.Email) LIKE '%@mailtrust%' 
OR lower(d.Email) LIKE '%@mosso%' 
OR lower(d.Email) LIKE '%@jungledisk%' 
OR lower(d.Email) LIKE '%@slicehost%'
OR lower(d.Email) LIKE '%@cloudkick%'
OR lower(d.Email) like '%@ackspace%'
OR lower(d.Email) like '%@test.com%'
OR lower(d.Email) like '%@test.co.uk%'
OR lower(d.AccountName) like '%rackspace%'
OR lower(d.AccountName) like '%datapipe%'
)
AND Domain_Internal_Flag=0;
----------------------------------------------------------------------------------------------------
UPDATE  `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current c
SET	
	c.Billing_Domain_Internal_Flag=1,
	c.Billing_Internal_Flag=1
WHERE
  ( lower(Billing_Email) LIKE '%@rackspace%.co%' 
OR  lower(Billing_Email) LIKE '%@rackspace%'
OR  lower(Billing_Email) LIKE '%@racksapce%'
OR  lower(Billing_Email) LIKE '%@lists.rackspace%'
OR  lower(Billing_Email) LIKE '%@mailtrust%' 
OR  lower(Billing_Email) LIKE '%@mosso%' 
OR  lower(Billing_Email) LIKE '%@jungledisk%' 
OR  lower(Billing_Email) LIKE '%@slicehost%'
OR  lower(Billing_Email) LIKE '%@cloudkick%'
OR  lower(Billing_Email) like '%@ackspace%'
OR  lower(Billing_Email) like '%@test.com%'
OR  lower(Billing_Email) like '%@test.co.uk%'
OR  lower(AccountName) like '%rackspace%'
OR  lower(AccountName) like '%datapipe%'
)
AND Billing_Domain_Internal_Flag=0;
----------------------------------------------------------------------------------------------------
UPDATE `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current
SET  
    Domain_Internal_Flag=1
where 
    (Domain_Internal_Flag+Billing_Internal_Flag)<> 0
AND Domain_Internal_Flag=0;
----------------------------------------------------------------------------------------------------
UPDATE `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current
SET  
    Internal_Flag=1
where 
    Domain_Internal_Flag+Billing_Domain_Internal_Flag +BRM_Internal_Account+Internal_Flag<>0
AND Internal_Flag=0;
----------------------------------------------------------------------------------------------------
UPDATE `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current
SET  
    Internal_Flag=0
where 
   (lower(accountname) like '%- rackspace%' and  lower(accountname) not like '%support%')
and lower(domain) not like '%rackspace%'
and lower(account_number)<> 'n/a'
;
----------------------------------------------------------------------------------------------------
UPDATE `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current
set  
    internal_flag=0
where 
   (lower(accountname) like '%- rackspace%' and  lower(accountname) not like '%support%')
and lower(billing_domain) not like '%rackspace%'
and lower(account_number)<> 'n/a';
----------------------------------------------------------------------------------------------------
UPDATE `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current
SET  
    SF_Account_Sub_Type_UWBL='Internal'
where 
    Internal_Flag=1
and ifnull( lower(sf_account_sub_type), 'unknown')<>'internal';
----------------------------------------------------------------------------------------------------
UPDATE `rax-abo-72-dev`.cloud_uk.cloud_account_contact_info_current
SET
	Is_Managed_Flag=0
WHERE
	lower(Account_SLA_Name_BRM )<> 'managed';
	
	
end;	