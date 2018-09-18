#!/bin/bash
#Created 11/6/2017 - Chris Driscoll

# Copyright (C) 2018 Target Brands, Inc.

# Permission is hereby granted, free of charge, to any person obtaining a 
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

#Script will verify if the user has the application already installed.
#If so, user can uninstall or reinstall
#If no, the script will verify if the user has the proper entitlement
## If so, the user will be prompted to install the Application
## If no, the user will be prompted to request an entitlement


#Get UID of logged in user for later interaction with the "open" command
User=$(ls -l /dev/console | awk '{print $3}');uID=$(id -u $User)

### FUNCTIONS ###

#Determine if the user has a Universal Type Client entitlement.
checkGroup ()
{
  security_group_valid=$(ldapsearch -LLL -x -D USERNAME -H ldaps://LDAPaddress.company.com -w PASSWORD -b DC=company,DC=com samAccountName=$(stat -f%Su /dev/console) | grep -i 'UTC-Entitlement')
}

#Install UTC
installUTC ()
{
jamf policy -event InstallUTCTrigger
}

#Uninstall UTC
uninstallUTC ()
{
jamf policy -event UninstallUTCTrigger
}


#UTC not installed; prompt either asks user to install or visit the Wiki page for more info
missingUTC ()
{
buttonClick=$(/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
                  -windowType hud \
                  -icon /Library/Application\ Support/macOS_CPE/logo.png \
                  -title "Company • macOS Client Platform Engineering" \
                  -heading "Universal Type Client" \
                  -button1 "Install" -defaultButton 1 \
                  -button2 "More info..." \
                  -description "Universal Type Client provides access to your font server.

To learn more about UTC, please click the 'More info...' button.")

    if [ $buttonClick == 0 ]; then
      echo "User clicked Install"
      installUTC

    elif [ $buttonClick == 2 ]; then
      echo "User clicked More info..."
      sudo launchctl asuser $uID open http://wiki.company.com/wiki/index.php/Universal_Type_Client

    else
      echo "User closed the window"
      exit 0
    fi
}


#UTC is installed; prompt either asks user to uninstall or reinstall
hasUTC ()
{
    buttonClick=$(/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
                  -windowType hud \
                  -icon /Library/Application\ Support/macOS_CPE/logo.png \
                  -title "Company • macOS Client Platform Engineering" \
                  -heading "Universal Type Client" \
                  -button1 "Uninstall" -defaultButton 1 \
                  -button2 "Reinstall" \
                  -description "Universal Type Client is installed on this computer.

To remove the application from this machine, click the 'Uninstall' button.

To reinstall UTC, please click the 'Reinstall' button.")

    if [ $buttonClick == 0 ]; then
      echo "User clicked Uninstall"
      uninstallUTC

    elif [ $buttonClick == 2 ]; then
      echo "User clicked Reinstall"
      installUTC

    else
      echo "User closed the window"
      exit 0
    fi
}

#User missing entitlement; prompts user to navigate to the Directory Services Portal to request entitlement or to the Wiki for more information
moreInfo ()
{
buttonClick=$(/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
                  -windowType hud \
                  -icon /Library/Application\ Support/macOS_CPE/logo.png \
                  -title "Company • macOS Client Platform Engineering" \
                  -heading "Universal Type Client" \
                  -button1 "Request" -defaultButton 1 \
                  -button2 "More info..." \
                  -description "Before installing Universal Type Client, you must request the appropriate security group in the Directory Services Portal

To request access, please click the 'Request' button.

To learn more about UTC, please click the 'More info...' button.")

if [ $buttonClick == 0 ]; then
    echo "User clicked Request"
    sudo launchctl asuser $uID open https://directoryservices.company.com/requests/makeRequest

elif [ $buttonClick == 2 ]; then
    echo "User clicked More info..."
    sudo launchctl asuser $uID open http://wiki.company.com/wiki/index.php/Universal_Type_Client

else
    echo "User closed the window"
    exit 0
fi
}


### MAIN ###

#user has UTC already installed so no entitlement check is necessary
if [ -e /Applications/Universal\ Type\ Client.app ]; then
  echo "UTC is installed. Skipping entitlement check."
  echo "Prompting to install/uninstall"
  hasUTC

#UTC not installed, verify if the user has entitlement
else
  echo "UTC is not installed. Checking entitlement"
  if checkGroup; then
    #User has the proper entitlement so prompt to install the application
    echo "User has one of the Font Server entitlements"
    missingUTC
  else
    echo "User does not have one of the Font Server entitlements"
    echo "Prompting to request entitlement"
    moreInfo
  fi
fi
