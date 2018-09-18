## UTCPrompt.sh

This code is loaded in as a Self Service policy to provide options for users to install/uninstall/request entitlement access for Universal Type Client

- Script will verify if the user has the application already installed
- If so, user can uninstall or reinstall
- If no, the script will verify if the user has the proper entitlement
	- If so, the user will be prompted to install the Application
	- If no, the user will be prompted to request an entitlement

## Technical Requirements

- Some LDAP services/the ability to query for security groups/entitlement access (may require a privileged account)

## Technical Tidbits

- Install/uninstall is invoked by `jamf policy -trigger` calls to individual policies that contain the installer or uninstaller packages
- Entitlement verification takes place by doing an `ldapsearch` query against a user's group membership in an LDAP environment
