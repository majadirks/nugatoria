--Nugatoria: A Personal Notebook App
--Drop sequences
DROP SEQUENCE container_id_sequence;
DROP SEQUENCE account_id_sequence;

--Drop tables so that the script can be re-run
DROP TABLE ContainerTagBridge;
DROP TABLE Hashtag;
DROP TABLE Revision;
DROP TABLE Notebook;
DROP TABLE ReceivedInvitation;
DROP TABLE SentInvitation;
DROP TABLE Invitation;
DROP TABLE NugatoriaPermission;
DROP TABLE NugatoriaContainer;
DROP TABLE ContainerType;
DROP TABLE PermissionLevel;
DROP TABLE AccountBalanceChange;
DROP TABLE Account;

--Create tables and sequences
CREATE TABLE Account(
account_id DECIMAL(12) PRIMARY KEY,
last_name VARCHAR(1024),
first_name VARCHAR(1024),
signature VARCHAR(32),
username VARCHAR(32) UNIQUE NOT NULL,
email VARCHAR(1024),
salt_str VARCHAR(1024) UNIQUE NOT NULL,
hashed_password VARCHAR(1024) NOT NULL,
account_balance DECIMAL(12, 2),
monthly_charge DECIMAL(12, 2));
CREATE SEQUENCE account_id_sequence START WITH 2; --for Account pk

CREATE TABLE AccountBalanceChange(
change_id DECIMAL(12) PRIMARY KEY,
account_id DECIMAL(12) NOT NULL,
old_balance DECIMAL(12, 2) NOT NULL,
new_balance DECIMAL(12, 2) NOT NULL,
change_date DATE NOT NULL,
FOREIGN KEY (account_id) REFERENCES Account (account_id));

CREATE TABLE PermissionLevel(
permission_level_id DECIMAL(12) PRIMARY KEY,
permission_description VARCHAR(1024));

CREATE TABLE ContainerType(
container_type_id DECIMAL(12) PRIMARY KEY,
container_type VARCHAR(32) NOT NULL);

CREATE TABLE NugatoriaContainer(
container_id DECIMAL(12) PRIMARY KEY,
container_type_id DECIMAL(12) NOT NULL,
container_name VARCHAR(64) NOT NULL,
owner_id DECIMAL(12),
is_movable INTEGER,
FOREIGN KEY (container_type_id) REFERENCES ContainerType(container_type_id));
CREATE SEQUENCE container_id_sequence START WITH 7; --for NugatoriaContainer PK

CREATE TABLE NugatoriaPermission(
account_id DECIMAL(12) NOT NULL,
container_id DECIMAL(12) NOT NULL,
permission_level_id DECIMAL(12),
PRIMARY KEY (account_id, container_id), -- Composite PK
FOREIGN KEY (permission_level_id) REFERENCES PermissionLevel(permission_level_id));

CREATE TABLE Invitation(
invitation_id DECIMAL(12) PRIMARY KEY,
permission_level_id DECIMAL(12) NOT NULL,
accepted INTEGER,
container_id DECIMAL(12),
time_sent TIMESTAMP,
FOREIGN KEY (permission_level_id) REFERENCES PermissionLevel (permission_level_id),
FOREIGN KEY (container_id) REFERENCES NugatoriaContainer(container_id));

CREATE TABLE SentInvitation(
invitation_id DECIMAL(12) NOT NULL,
sender_id DECIMAL(12) NOT NULL,
PRIMARY KEY (invitation_id, sender_id),
FOREIGN KEY (invitation_id) REFERENCES Invitation (invitation_id),
FOREIGN KEY (sender_id) REFERENCES Account (account_id));

CREATE TABLE ReceivedInvitation(
invitation_id DECIMAL(12) NOT NULL,
recipient_id DECIMAL(12) NOT NULL,
PRIMARY KEY (invitation_id, recipient_id),
FOREIGN KEY (invitation_id) REFERENCES Invitation (invitation_id),
FOREIGN KEY (recipient_id) REFERENCES Account (account_id));

CREATE TABLE Notebook(
container_id DECIMAL(12) PRIMARY KEY,
time_created TIMESTAMP NOT NULL,
last_sync TIMESTAMP UNIQUE NOT NULL,
owning_account DECIMAL(12),
FOREIGN KEY (container_id) REFERENCES NugatoriaContainer (container_id),
FOREIGN KEY (owning_account) REFERENCES Account (account_id)
);

CREATE TABLE Revision(
container_id DECIMAL(12) PRIMARY KEY,
location VARCHAR(4000) UNIQUE NOT NULL,
time_saved TIMESTAMP NOT NULL,
deprecated INTEGER,
predecessor_id DECIMAL(12),
FOREIGN KEY (container_id) REFERENCES NugatoriaContainer (container_id));

CREATE TABLE Hashtag(
hashtag_id DECIMAL(12) PRIMARY KEY,
label VARCHAR(32));

CREATE TABLE ContainerTagBridge(
hashtag_id DECIMAL(12) NOT NULL,
container_id DECIMAL(12) NOT NULL,
deprecated INTEGER,
PRIMARY KEY (hashtag_id, container_id),
FOREIGN KEY (hashtag_id) REFERENCES Hashtag (hashtag_id),
FOREIGN KEY (container_id) REFERENCES Revision (container_id));

--Create indexes
--Primary key indexes are created automatically

--Foreign key indexes:
CREATE INDEX invitation_permission_level_id_idx
ON Invitation (permission_level_id);

CREATE INDEX invitation_container_id_idx
ON Invitation (container_id);

CREATE INDEX permission_permissionlevel_id_idx
ON NugatoriaPermission (permission_level_id);

CREATE INDEX container_containertype_id_idx
ON NugatoriaContainer (container_type_id);

CREATE INDEX balance_change_account_id_idx
ON AccountBalanceChange (account_id);

CREATE INDEX owning_account_idx
ON Notebook (owning_account);

--Query-based indexes
CREATE INDEX container_owner_id_idx
ON NugatoriaContainer (owner_id);

CREATE INDEX predecessor_id_idx
ON Revision (predecessor_id);

CREATE INDEX time_saved_idx
ON Revision (time_saved);

--Enumerate creator types
INSERT INTO ContainerType (container_type_id, container_type)
VALUES (1, 'Notebook');
INSERT INTO ContainerType (container_type_id, container_type)
VALUES (2, 'Section Group');
INSERT INTO ContainerType (container_type_id, container_type)
VALUES (3, 'Section');
INSERT INTO ContainerType (container_type_id, container_type)
VALUES (4, 'Page');
INSERT INTO ContainerType (container_type_id, container_type)
VALUES (5, 'Revision');

--Enumerate permission levels
INSERT INTO PermissionLevel(permission_level_id, permission_description)
VALUES (1, 'Read');
INSERT INTO PermissionLevel(permission_level_id, permission_description)
VALUES (2, 'ReadEdit');
INSERT INTO PermissionLevel(permission_level_id, permission_description)
VALUES (3, 'ReadEditShare');
INSERT INTO PermissionLevel(permission_level_id, permission_description)
VALUES (4, 'Owner');

--Stored Procedure to create a new notebook containing a new section,
--a new page, and a new revision
CREATE OR REPLACE PROCEDURE
ADD_NOTEBOOK_WITH_OWNING_ACCT(owning_account_arg IN DECIMAL,
notebook_name_arg IN VARCHAR, initial_revision_location_arg IN VARCHAR)
IS
    v_notebook_id DECIMAL(12);
    v_section_id DECIMAL(12);
    v_page_id DECIMAL(12);
    v_revision_id DECIMAL(12);
BEGIN
    v_notebook_id := container_id_sequence.NEXTVAL;
    v_section_id := container_id_sequence.NEXTVAL;
    v_page_id := container_id_sequence.NEXTVAL;
    v_revision_id := container_id_sequence.NEXTVAL;
    --Create Notebook: first update NugatoriaContainer table
    INSERT INTO NugatoriaContainer(container_id,
                                    container_type_id, is_movable, container_name)
    VALUES (v_notebook_id,
            (SELECT container_type_id
            FROM ContainerType
            WHERE container_type = 'Notebook'),
            0, --not movable since has no owning container
            notebook_name_arg);
    --Then update Notebook table
    INSERT INTO Notebook(container_id, owning_account, time_created, last_sync)
    VALUES (v_notebook_id, owning_account_arg,
    (SELECT(CURRENT_TIMESTAMP) FROM Dual),
    (SELECT(CURRENT_TIMESTAMP) FROM Dual));
    --Create section
  INSERT INTO NugatoriaContainer(container_id,
                                    container_type_id, owner_id, 
                                    is_movable, container_name)
    VALUES (v_section_id,
           (SELECT container_type_id FROM ContainerType
            WHERE container_type = 'Section'),
            v_notebook_id, --owned by notebook
            1, --sections are movable
            'New Section');
    --Create page
    INSERT INTO NugatoriaContainer(container_id,
                                    container_type_id, owner_id, 
                                    is_movable, container_name)
    VALUES (v_page_id,
           (SELECT container_type_id FROM ContainerType
            WHERE container_type = 'Page'),
            v_section_id, --owned by section
            1, --pages are movable
            'New Page');
    --Create revision: update NugatoriaContainer table
    INSERT INTO NugatoriaContainer(container_id,
                                    container_type_id, owner_id, 
                                    is_movable, container_name)
    VALUES (v_revision_id,
           (SELECT container_type_id FROM ContainerType
            WHERE container_type = 'Revision'),
            v_page_id, --owned by page
            0, --revisions are not movable
            'Init Rev ' ||
            TO_CHAR((SELECT(CURRENT_TIMESTAMP) FROM Dual)));
    --Update Revision table
    INSERT INTO Revision(container_id, location, time_saved, deprecated)
    VALUES (v_revision_id, initial_revision_location_arg, 
    (SELECT(CURRENT_TIMESTAMP) FROM Dual),
    0);
END;
/
    
--Stored procedure to grant permission to a given user
CREATE OR REPLACE PROCEDURE Grant_Permission(
                account_id_arg IN DECIMAL,
                container_id_arg IN DECIMAL,
                permission_desc_arg IN VARCHAR)
IS
    v_preexisting_permissions DECIMAL(12);
    v_permission_level_id DECIMAL(12);
BEGIN
    SELECT COUNT(container_id) 
    INTO v_preexisting_permissions 
    FROM NugatoriaPermission
        WHERE account_id = account_id_arg
        AND container_id = container_id_arg;
    SELECT permission_level_id
    INTO v_permission_level_id
    FROM PermissionLevel
    WHERE permission_description = permission_desc_arg;
    IF v_preexisting_permissions = 0 THEN
        INSERT INTO NugatoriaPermission(
            account_id, 
            container_id,
            permission_level_id)
        VALUES (account_id_arg, container_id_arg,
                v_permission_level_id);
    ELSE --user has permission already; update
        UPDATE NugatoriaPermission
        SET permission_level_id = v_permission_level_id
        WHERE account_id = account_id_arg
        AND container_id = container_id_arg;
    END IF;
END;
/
    

--Stored Procedure to create new user account
--For now all accounts are 'free'
CREATE OR REPLACE PROCEDURE Create_Free_Account(
username_arg IN VARCHAR,
last_name_arg IN VARCHAR,
first_name_arg IN VARCHAR,
email_arg IN VARCHAR,
salt_str_arg IN VARCHAR,
hashed_password_arg IN VARCHAR,
initial_rev_location_arg IN VARCHAR
)
IS
    v_new_account_id DECIMAL(12);
    v_new_account_notebook_id DECIMAL(12);
BEGIN
    v_new_account_id := account_id_sequence.NEXTVAL;
    INSERT INTO Account(account_id,
    username,
    last_name,
    first_name,
    signature,
    email,
    salt_str,
    hashed_password,
    account_balance,
    monthly_charge)
    VALUES (v_new_account_id,
    username_arg, last_name_arg, first_name_arg,
    last_name_arg, -- by default, signature is last name
    email_arg,
    salt_str_arg,
    hashed_password_arg,
    0,0);
    ADD_NOTEBOOK_WITH_OWNING_ACCT(v_new_account_id, 
    'My Notebook', initial_rev_location_arg);
    --Find ID of the (unique) notebook with this owning account
    --(unique because the account is new!)
    SELECT container_id 
    INTO v_new_account_notebook_id
    FROM Notebook
    WHERE owning_account = v_new_account_id;
    GRANT_PERMISSION(v_new_account_id, v_new_account_notebook_id, 'Owner');
END;
/
            
--AccountBalance Change Trigger
CREATE OR REPLACE TRIGGER AccoutBalanceChangeTrigger
BEFORE UPDATE OF account_balance ON Account
FOR EACH ROW
BEGIN
    IF (:OLD.account_balance <> :NEW.account_balance)
    OR (:OLD.account_balance IS NULL) THEN
        INSERT INTO AccountBalanceChange(change_id, account_id,
        old_balance, new_balance, change_date)
        VALUES(
        NVL((SELECT MAX(change_id)+1 FROM AccountBalanceChange), 1),
        :NEW.account_id,
        NVL(:OLD.account_balance, 0), -- if no previous balance, insert 0
        :NEW.account_balance,
        TRUNC(sysdate));
    END IF;
END;
/

--Questions and Queries
--First query: which pages are experiencing edit conflicts?

--Named subquery: Most_Recent_Revision
--returns the most recent revision of each page
WITH Most_Recent_Revision AS
(SELECT AllRevisions.container_id, owner_id, time_saved
FROM Revision AllRevisions 
JOIN NugatoriaContainer AllContainers ON AllRevisions.container_id = AllContainers.container_id
WHERE time_saved = (SELECT MAX(time_saved) 
                    FROM Revision ThisRevision
                    JOIN NugatoriaContainer ThisContainer ON ThisRevision.container_id = ThisContainer.container_id
                    WHERE AllContainers.owner_id = ThisContainer.owner_id)
)

--Using those two named subqueries, identify any conflicting edits
SELECT OwningPage.container_name,
ConflictingRevision.container_id AS id_of_older_conflicting_revision,
ConflictingRevision.time_saved AS time_of_older_revision,
Most_Recent_Revision.container_id AS id_of_newer_conflicting_revision,
Most_Recent_Revision.most_recent_time_saved AS time_of_newer_revision,
ConflictingRevision.predecessor_id
FROM NugatoriaContainer ConflictingContainer
JOIN Revision ConflictingRevision ON ConflictingContainer.container_id = ConflictingRevision.container_id
JOIN NugatoriaContainer OwningPage on ConflictingContainer.owner_id = OwningPage.container_id
JOIN Most_Recent_Revision ON Most_Recent_Revision.predecessor_id = ConflictingRevision.predecessor_id --problem here (MRR doesn't have predecessor_id)
WHERE ConflictingContainer.owner_id = 3 --belonging to Page 3. Hardcoded magic number alert!
--Not the most recent revision
AND ConflictingRevision.time_saved != (SELECT time_saved FROM Most_Recent_Revision) --anonymous subquery 
--and predecessor_id is same as that of most recent
AND ConflictingRevision.predecessor_id = (SELECT predecessor_id FROM Most_Recent_Revision); --anonymous subquery 


--Tests and Examples
--Create a simple notebook
INSERT INTO NugatoriaContainer (container_id, container_type_id, owner_id, is_movable, container_name)
VALUES (1, (SELECT container_type_id FROM ContainerType WHERE container_type = 'Notebook'), NULL, 1, 'My Notebook');
--Create a section within that notebook
INSERT INTO NugatoriaContainer (container_id, container_type_id, owner_id, is_movable, container_name)
VALUES (2, (SELECT container_type_id FROM ContainerType WHERE container_type = 'Section'), 1, 1, 'Section A');
--Test that the section belongs to the notebook
SELECT Member.container_id AS member_id, Member.container_name AS member_name, Owner.container_name AS owner_name
FROM NugatoriaContainer Member
JOIN NugatoriaContainer Owner ON Owner.container_id = Member.owner_id
WHERE Owner.container_id = 1;

--Create a dummy user
INSERT INTO Account(account_id, last_name, first_name, signature, username, email, salt_str, hashed_password)
VALUES (1, 'Smith', 'James', 'js', 'jsmith', 'jsmith@smithles.net', 'saltsaltsalt', 'HashBrownsYum123');
--Grant James Smith the permission level 'Owner' for 'My Notebook'
INSERT INTO NugatoriaPermission (account_id, container_id, permission_level_id)
VALUES (1, 1, 4);
--List names of all notebooks for which James Smith has permission, and the permission type
SELECT email, container_name AS notebook_name, permission_description
FROM Account
JOIN NugatoriaPermission ON NugatoriaPermission.account_id = Account.account_id
JOIN PermissionLevel ON NugatoriaPermission.permission_level_id = PermissionLevel.permission_level_id
JOIN NugatoriaContainer ON NugatoriaPermission.container_id = NugatoriaContainer.container_id
WHERE Account.account_id = 1;

--Conflict Detection
--Create a page
INSERT INTO NugatoriaContainer (container_id, container_type_id, owner_id, is_movable, container_name)
VALUES (3, 4, 2, 1, 'Page 3'); --Belongs to 'Section A'
--Create the first revision of that page
INSERT INTO NugatoriaContainer (container_id, container_type_id, owner_id, is_movable, container_name)
VALUES (4, 5, 3, 1, 'Initial Revision');
INSERT INTO Revision(container_id, location, time_saved, deprecated)
VALUES (4, 'http://www.nugatoria.com/rev4.html', TO_TIMESTAMP('01-DEC-2020 09:00:00.00 AM'), 0);
--Create the second revision of that page
INSERT INTO NugatoriaContainer (container_id, container_type_id, owner_id, is_movable, container_name)
VALUES (5, 5, 3, 1, '11am revision');
INSERT INTO Revision(container_id, location, time_saved, deprecated, predecessor_id)
VALUES (5, 'http://www.nugatoria.com/rev5.html', TO_TIMESTAMP('01-DEC-2020 11:00:00.00 AM'), 0, 4);
--Create a conflicting revision of that page
INSERT INTO NugatoriaContainer (container_id, container_type_id, owner_id, is_movable, container_name)
VALUES (6, 5, 3, 1, 'Conflicting revision');
INSERT INTO Revision(container_id, location, time_saved, deprecated, predecessor_id)
VALUES (6, 'http://www.nugatoria.com/rev6.html', TO_TIMESTAMP('01-DEC-2020 10:00:00.00 AM'), 0, 4);
--List any conflicting Revisions
--ie revisions belonging to this page (page 3) that have the same predecessor
--First named subquery, RevisionsOfPage, returns all revisions of page 3
WITH RevisionsOfPage AS (SELECT container_id, time_saved, predecessor_id
FROM NugatoriaContainer
NATURAL JOIN Revision
WHERE NugatoriaContainer.owner_id = 3),  --Hardcoded magic number alert!
--Second named subquery, Most_Recent_Revision,
--returns the most recent revision of Page 3
Most_Recent_Revision AS
(SELECT * 
FROM RevisionsOfPage
WHERE RevisionsOfPage.time_saved = (SELECT MAX(time_saved)
FROM RevisionsOfPage))
--Using those two named subqueries, identify any conflicting edits
SELECT OwningPage.container_name,
ConflictingRevision.container_id AS id_of_older_conflicting_revision,
ConflictingRevision.time_saved AS time_of_older_revision,
Most_Recent_Revision.container_id AS id_of_newer_conflicting_revision,
Most_Recent_Revision.time_saved AS time_of_newer_revision,
ConflictingRevision.predecessor_id
FROM NugatoriaContainer ConflictingContainer
JOIN Revision ConflictingRevision ON ConflictingContainer.container_id = ConflictingRevision.container_id
JOIN NugatoriaContainer OwningPage on ConflictingContainer.owner_id = OwningPage.container_id
JOIN Most_Recent_Revision ON Most_Recent_Revision.predecessor_id = ConflictingRevision.predecessor_id
WHERE ConflictingContainer.owner_id = 3 --belonging to Page 3. Hardcoded magic number alert!
--Not the most recent revision
AND ConflictingRevision.time_saved != (SELECT time_saved FROM Most_Recent_Revision) --anonymous subquery 
--and predecessor_id is same as that of most recent
AND ConflictingRevision.predecessor_id = (SELECT predecessor_id FROM Most_Recent_Revision); --anonymous subquery 

--Test of AccountBalanceChangeTrigger
--Initially James Smith does not have an account balance
SELECT username, account_balance, change_id,
old_balance, new_balance, change_date
FROM Account
LEFT JOIN AccountBalanceChange
ON Account.account_id = AccountBalanceChange.account_id
WHERE Account.username = 'jsmith';

--Update Jame Smith's account balance
UPDATE Account
SET account_balance = 3.99
WHERE username = 'jsmith';

--Now we should see a change reflected
SELECT username, account_balance, change_id,
old_balance, new_balance, change_date
FROM Account
LEFT JOIN AccountBalanceChange
ON Account.account_id = AccountBalanceChange.account_id
WHERE Account.username = 'jsmith';

--Update but do not change James Smith's account balance
UPDATE Account
SET account_balance = 3.99
WHERE username = 'jsmith';

--Still only one change reflected
SELECT username, account_balance, change_id,
old_balance, new_balance, change_date
FROM Account
LEFT JOIN AccountBalanceChange
ON Account.account_id = AccountBalanceChange.account_id;

--Update the balance to $7.98
UPDATE Account
SET account_balance = 7.98
WHERE username = 'jsmith';

--Two changes reflected now
SELECT username, account_balance, change_id,
old_balance, new_balance, change_date
FROM Account
LEFT JOIN AccountBalanceChange
ON Account.account_id = AccountBalanceChange.account_id;

--Test ADD_NOTEBOOK_WITH_OWNING_ACCT by creating a new notebook for James Smith
DECLARE 
    jsmith_id DECIMAL(12);
BEGIN
    SELECT account_id 
    INTO jsmith_id
    FROM Account WHERE username = 'jsmith';
    
    ADD_NOTEBOOK_WITH_OWNING_ACCT(jsmith_id,
    'James Smith Notebook 2',
    'C:\Users\jsmith\Documents\notebook2_rev_1.ngdat');
END;
/  
SELECT * FROM NugatoriaContainer;

--Test GRANT_PERMISSION
DECLARE 
    jsmith_id DECIMAL(12);
BEGIN
    --Grant owner permission for Container 7
    SELECT account_id 
    INTO jsmith_id
    FROM Account WHERE username = 'jsmith';
    GRANT_PERMISSION(jsmith_id, 7, 'Owner');
    --Downgrade to Read permission for Container 1
    GRANT_PERMISSION(jsmith_id, 1, 'Read');
END;
/
--We should see that James Smith has 
--Owner permission for container 7
--and Read permission for Container 1
SELECT * FROM NugatoriaPermission
NATURAL JOIN PermissionLevel;
/

--Test Create_Free_Account
BEGIN
    Create_Free_Account('ljones', 
    'Jones', 
    'Liz', 
    'lizjones@troutlake.org', 
    'af8@lnfprjy4', --Salt
    'sdfgthknbvdfjmcdrtyuio9876rfvbnky', --hashed password
    'C:\Users\ljones\Documents\rev1.ngdat');
END;
/
SELECT * FROM Account WHERE username = 'ljones';

SELECT account_ID, username, container_name, permission_description
FROM NugatoriaPermission 
NATURAL JOIN Account 
NATURAL JOIN NugatoriaContainer
NATURAL JOIN PermissionLevel
WHERE username = 'ljones';