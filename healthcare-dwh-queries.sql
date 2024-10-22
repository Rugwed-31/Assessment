-- 1. First, let's create the staging table to load the initial data
CREATE TABLE Customer_Staging (
    Customer_Name VARCHAR(255) NOT NULL,
    Customer_ID VARCHAR(18) NOT NULL,
    Open_Date DATE NOT NULL,
    Last_Consulted_Date DATE,
    Vaccination_Type CHAR(5),
    Doctor_Consulted CHAR(255),
    State CHAR(5),
    Country CHAR(5),
    PostCode INT,
    Date_Of_Birth DATE,
    Is_Active CHAR(1),
    -- Adding derived columns
    Age INT GENERATED ALWAYS AS (
        YEAR(CURRENT_DATE) - YEAR(Date_Of_Birth)
    ) STORED,
    Days_Since_Last_Consulted INT GENERATED ALWAYS AS (
        DATEDIFF(DAY, Last_Consulted_Date, CURRENT_DATE)
    ) STORED,
    Needs_Followup CHAR(1) GENERATED ALWAYS AS (
        CASE WHEN DATEDIFF(DAY, Last_Consulted_Date, CURRENT_DATE) > 30 THEN 'Y' ELSE 'N' END
    ) STORED,
    Created_Date DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT PK_Customer_Staging PRIMARY KEY (Customer_Name, Customer_ID)
);

-- 2. Create country-specific tables
-- Example for India
CREATE TABLE Customer_India (
    Customer_Name VARCHAR(255) NOT NULL,
    Customer_ID VARCHAR(18) NOT NULL,
    Open_Date DATE NOT NULL,
    Last_Consulted_Date DATE,
    Vaccination_Type CHAR(5),
    Doctor_Consulted CHAR(255),
    State CHAR(5),
    PostCode INT,
    Date_Of_Birth DATE,
    Is_Active CHAR(1),
    Age INT,
    Days_Since_Last_Consulted INT,
    Needs_Followup CHAR(1),
    Created_Date DATETIME DEFAULT CURRENT_TIMESTAMP,
    Last_Updated_Date DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT PK_Customer_India PRIMARY KEY (Customer_Name, Customer_ID)
);

-- Similar tables for other countries (USA, AU, PHIL, etc.)
CREATE TABLE Customer_USA LIKE Customer_India;
CREATE TABLE Customer_Australia LIKE Customer_India;
CREATE TABLE Customer_Philippines LIKE Customer_India;

-- 3. Create validation table for tracking errors
CREATE TABLE Data_Validation_Errors (
    Error_ID INT AUTO_INCREMENT PRIMARY KEY,
    Customer_Name VARCHAR(255),
    Customer_ID VARCHAR(18),
    Error_Type VARCHAR(50),
    Error_Description VARCHAR(255),
    Created_Date DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 4. Create stored procedure for data validation
DELIMITER //
CREATE PROCEDURE ValidateCustomerData()
BEGIN
    -- Insert validation errors for missing mandatory fields
    INSERT INTO Data_Validation_Errors (Customer_Name, Customer_ID, Error_Type, Error_Description)
    SELECT 
        Customer_Name,
        Customer_ID,
        'Missing Mandatory Field',
        CASE 
            WHEN Customer_Name IS NULL OR TRIM(Customer_Name) = '' THEN 'Customer Name is missing'
            WHEN Customer_ID IS NULL OR TRIM(Customer_ID) = '' THEN 'Customer ID is missing'
            WHEN Open_Date IS NULL THEN 'Open Date is missing'
        END
    FROM Customer_Staging
    WHERE 
        Customer_Name IS NULL OR TRIM(Customer_Name) = '' OR
        Customer_ID IS NULL OR TRIM(Customer_ID) = '' OR
        Open_Date IS NULL;

    -- Validate date formats
    INSERT INTO Data_Validation_Errors (Customer_Name, Customer_ID, Error_Type, Error_Description)
    SELECT 
        Customer_Name,
        Customer_ID,
        'Invalid Date',
        'Invalid date format or future date'
    FROM Customer_Staging
    WHERE 
        Open_Date > CURRENT_DATE OR
        (Last_Consulted_Date IS NOT NULL AND Last_Consulted_Date > CURRENT_DATE) OR
        (Date_Of_Birth IS NOT NULL AND Date_Of_Birth > CURRENT_DATE);

    -- Validate country codes
    INSERT INTO Data_Validation_Errors (Customer_Name, Customer_ID, Error_Type, Error_Description)
    SELECT 
        Customer_Name,
        Customer_ID,
        'Invalid Country',
        'Invalid country code'
    FROM Customer_Staging
    WHERE Country NOT IN ('IND', 'USA', 'AU', 'PHIL');
END //
DELIMITER ;

-- 5. Create procedure to distribute data to country-specific tables
DELIMITER //
CREATE PROCEDURE DistributeCustomerData()
BEGIN
    -- Handle India customers
    INSERT INTO Customer_India
    SELECT 
        Customer_Name, Customer_ID, Open_Date, Last_Consulted_Date,
        Vaccination_Type, Doctor_Consulted, State, PostCode,
        Date_Of_Birth, Is_Active, Age, Days_Since_Last_Consulted,
        Needs_Followup, Created_Date, CURRENT_TIMESTAMP
    FROM Customer_Staging
    WHERE Country = 'IND'
    ON DUPLICATE KEY UPDATE
        Last_Consulted_Date = 
            CASE 
                WHEN Customer_Staging.Last_Consulted_Date > Customer_India.Last_Consulted_Date 
                THEN Customer_Staging.Last_Consulted_Date 
                ELSE Customer_India.Last_Consulted_Date 
            END,
        Last_Updated_Date = CURRENT_TIMESTAMP;

    -- Similar INSERT statements for other countries
    -- USA
    INSERT INTO Customer_USA
    SELECT 
        Customer_Name, Customer_ID, Open_Date, Last_Consulted_Date,
        Vaccination_Type, Doctor_Consulted, State, PostCode,
        Date_Of_Birth, Is_Active, Age, Days_Since_Last_Consulted,
        Needs_Followup, Created_Date, CURRENT_TIMESTAMP
    FROM Customer_Staging
    WHERE Country = 'USA'
    ON DUPLICATE KEY UPDATE
        Last_Consulted_Date = 
            CASE 
                WHEN Customer_Staging.Last_Consulted_Date > Customer_USA.Last_Consulted_Date 
                THEN Customer_Staging.Last_Consulted_Date 
                ELSE Customer_USA.Last_Consulted_Date 
            END,
        Last_Updated_Date = CURRENT_TIMESTAMP;

    -- Add similar blocks for other countries
END //
DELIMITER ;
