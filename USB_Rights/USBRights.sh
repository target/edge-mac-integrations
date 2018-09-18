#!/bin/bash
#Created 6/7/18 - Chris Driscoll
#Updated 6/29/18 - Noah Anderson

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

#Script assists users in requesting USB Rights via ServiceNow API
#We set all variables and the bearer token needed for ServiceNow access
#We validate the user isn't local and has a record in Jamf Pro
#We verify where the user might be in the request process: No request, Request but no fulfillment, Fulfillment
#We submit a request and/or re-request depending on the user's scenario
#We prompt the user throughout the process and allow him/her to access the wiki for more information

setVariables() {
  #Enter in the URL of the JSS we are are pulling and pushing the data to. (NOTE: We will need the https:// and :8443. EX:https://jss.company.com:8443 )
  jssURL=''

  #Enter in a username and password that has the correct permissions to the JSS API for what data we need
  #JSS user must have CRUD access for Users, User Extension Attributes, and Static Computer Groups
  jssUser=""
  jssPass=""

  #Define JAMFHelper settings
  jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
  jamfIconSecurity="/Library/Application Support/macOS_CPE/InfoSecurityLogo.png"
  jamfTitle="Company • macOS Client Platform Engineering"
  jamfHeadingUSB="USB Rights Request"
  jamfHeadingError="Error"
  jamfHeadingSubmitted="Request Submitted"
  jamfButtonOK="Ok"
  jamfButtonLookup="Lookup"
  jamfButtonMoreInfo="More info..."
  jamfButtonRequest="Request"
  jamfButtonManual="Manual"

  ServiceNowURL="https://company.service-now.com"
  ServiceNowUSBRequest="https://company.service-now.com/sp?id=sc_cat_item&sys_id=SYSTEM_ID_OF_SN_FORM"
  USBRightsWikiPage="https://wiki.company.com/wiki/index.php/Portal:Mac/Software/Request_USB"
  Auth_Key=""
  Bearer_Token=""
  #Below grabs the SysID of the dynamically generated ServiceNow URL and creates a variable for the ServiceNow webpage to be opened later
  #This will allow the user to be taken directly into the ServiceNow webpage with their requested item
  function SNURL() {
  SysID=$(curl -s -H "Authorization: Bearer ${Bearer_Token}" -X GET "https://servicenow.api.address.com/service_catalog_entries/v1/requested_item/$UserUSBRequestInJSS"?key=${Auth_Key} -H 'Cache-Control: no-cache'  -H 'Content-Type: application/json' | tr , "\n" | sed -n -e 's/^.*record_id//p' | cut -d '"' -f3)
  SNLookup="https://company.service-now.com/nav_to.do?uri=%2Fsc_req_item.do%3Fsys_id%3D${SysID}%26sysparm_stack%3D%26sysparm_view%3Ddefault%26sysparm_view_forced%3Dtrue"
}

  #####
  #Set ServiceNow Catalog API configs
  #ServiceNow Prod
  ServiceNowAPIURL="https://servicenow.api.address.com/service_catalog_entries/v1/mac_usb_requests"
  UserAccount=$(/usr/bin/stat -f%Su /dev/console)
  #We also have the option for users to submit a bulk request manually, so we have to set the field below as "No" for bulk when submitting via API
  Bulk="No"
  Notes="USB Rights requested via Self Service"
  #####

  echo "Variables set"
  #Call the next function
  localUser
}

localUser() {
  #Need to determine if the account requesting access is a local account or a valid network username

  uID=$(id -u $UserAccount)
  echo "UID is $uID"
  if [ "$uID" -gt "1000" ]; then
  	echo "$UserAccount appears to be a valid domain account"
    Username=$UserAccount
    UserInJSS
  elif [[ "/Library/Application Support/macOS_CPE/Enterprise Connect/UserADInfo.txt" ]]; then
    #The user account *could* be local and connecting via Enterprise Connect, so we'll check for credentialed information there
    Username=$(grep -i adUsername /Library/Application\ Support/macOS_CPE/Enterprise\ Connect/UserADInfo.txt | cut -d ":" -f2 | xargs)
    UserInJSS
  else
    #If we fail to find any, it's an almost certainty this is a local account
    echo "$UserAccount appears to be a local account"
    "$jamfHelper" \
      -windowType hud \
      -icon "$jamfIconSecurity" \
      -title "$jamfTitle" \
      -heading "$jamfHeadingError" \
      -button1 "$jamfButtonOK" -defaultButton 1 \
      -description "The account currently logged in appears to be a local account. Please log back into this machine with your domain username and try again.

If you believe this message is incorrect, please email your IT helpdesk for more information."
  fi
  exit 1
}

UserInJSS() {
  #Validate user is associated with a machine in Jamf Pro
  UserRecordInJSS=$(/usr/bin/curl -s -u $jssUser:$jssPass $jssURL/JSSResource/users/name/$Username -H "Accept: application/xml" | /usr/bin/xpath '/user/full_name/text()' 2>/dev/null)
  if [ "$UserRecordInJSS" != "" ]; then
    echo "$Username / $UserRecordInJSS exists in Jamf Pro"
    pullUserUSBRequestInJSS
  else
    #If not, run a recon with the current logged in user to associate the machine and create the user record in the JSS
    echo $Username "does not exist in JSS"
    sudo /usr/local/bin/jamf recon -endUsername $Username &
    echo $Username "now associated with the machine in Jamf Pro"
    #Assume no USB Rights have been requested via Self Service so routing user to next step in request process
    submitUSBRequestInSN
  fi
}


pullUserUSBRequestInJSS() {
  #Validate if user already has USB Rights Request / Fulfillment

  UserUSBRequestInJSS=$(/usr/bin/curl -s -u $jssUser:$jssPass $jssURL/JSSResource/users/name/$Username -H "Accept: application/xml" | /usr/bin/xpath '/user/extension_attributes/extension_attribute[id = "3"]/value/text()' 2>/dev/null)
  RTMvTSK=$(echo $UserUSBRequestInJSS | cut -c 1-3)
  if [[ $RTMvTSK = "RTM" ]]; then
    echo $UserUSBRequestInJSS "- request was made but not fulfilled"
    #We know the request wasn't fulfilled because the fulfillment side overwrites the existing RTM with the completed TSK# and the date of completion
    lookupUSBRequestInSN
  elif [[ $RTMvTSK = "TSK" ]]; then
    echo $UserUSBRequestInJSS "- request was fulfilled"
    #user potentially re-requesting USB Rights
    reRequestUSBRights
  else
    echo "No request on file in Jamf Pro"
    askIfRequestExists
  fi
}

lookupUSBRequestInSN() {
  #Validate if a request exists for this user in ServiceNow
  #If so, get the current status and state of the request
  RTMStatus=$(curl -s -X GET -H "Authorization: Bearer ${Bearer_Token}" "https://servicenow.api.address.com/service_catalog_entries/v1/requested_item/$UserUSBRequestInJSS"?key=${Auth_Key} -H 'Cache-Control: no-cache'  -H 'Content-Type: application/json' | tr , "\n" | sed -n -e 's/^.*stage//p' | cut -d '"' -f3)
  RTMState=$(curl -s -X GET -H "Authorization: Bearer ${Bearer_Token}" "https://servicenow.api.address.com/service_catalog_entries/v1/requested_item/$UserUSBRequestInJSS"?key=${Auth_Key} -H 'Cache-Control: no-cache'  -H 'Content-Type: application/json' | tr , "\n" | sed -n -e 's/^.*state//p' | cut -d '"' -f3)

echo "API return status of the requested item $UserUSBRequestInJSS is $RTMStatus, $RTMState"

#The responses in ServiceNow aren't super intuitive for knowing where in the process we are
#As a result, we feed the responses into a large case statement which translates below as a Jamf Helper window
#This is not universal for every TSK/RTM, so you will need to adjust them based on what behavior your observe at each state
case ${RTMStatus}_${RTMState} in

 "Request Cancelled"_"Closed Incomplete") RTMState="Request: Rejected

Your USB Rights Request ($UserUSBRequestInJSS) was rejected by your approving manger. If you believe it was rejected in error, please submit another request below." ;;

 "Waiting for Approval"_"Work in Progress") RTMState="Request: Waiting for Approval

Your USB Rights Request ($UserUSBRequestInJSS) has still not been approved by your manager. Please follow up with them and ask to approve the pending request." ;;

 "Waiting for Approval"_"Open") RTMState="Request: Waiting for Approval

Your USB Rights Request ($UserUSBRequestInJSS) has still not been approved by your manager. Please follow up with them and ask to approve the pending request." ;;

 "Waiting for Approval"_"Closed Incomplete") RTMState="Request: Canceled

Your USB Rights Request ($UserUSBRequestInJSS) was canceled, either by you, another user, or your approving manger. If you believe it was canceled in error, please submit another request below." ;;

 "fulfillment"_"Work in Progress") RTMState="Request: Awaiting Fulfillment

Your USB Rights Request ($UserUSBRequestInJSS) has been approved and is waiting for our backend system to process. If rights have not been granted within a half hour, please reach out to your IT helpdesk with your RTM# for followup." ;;

 "Fulfillment"_"Work in Progress") RTMState="Request: Awaiting Fulfillment

Your USB Rights Request ($UserUSBRequestInJSS) has been approved and is waiting for our backend system to process. If rights have not been granted within a half hour, please reach out to your IT helpdesk with your RTM# for followup." ;;

 "Fulfillment"_"Closed Complete") RTMState="Request: Fulfilled

Your USB Rights Request ($UserUSBRequestInJSS) has been approved and fulfilled. If you still do not have USB rights on your machine, please restart and try again. If you continue to have issues, please reach out to your IT helpdesk with your RTM# for followup." ;;

 "Completed"_"Closed Complete") RTMState="Request: Completed

Your USB Rights Request ($UserUSBRequestInJSS) has been approved and fulfilled. If you still do not have USB rights on your machine, please restart and try again. If you continue to have issues, please reach out to your IT helpdesk with your RTM# for followup." ;;


     *) RTMState="Something went wrong with the ServiceNow process - please reach out to your IT helpdesk with your RTM# ($UserUSBRequestInJSS) for followup." ;;

esac

echo ${RTMState}

  buttonClick1=$("$jamfHelper" \
    -windowType hud \
    -icon "$jamfIconSecurity" \
    -title "$jamfTitle" \
    -heading "$jamfHeadingUSB" \
    -button1 "$jamfButtonLookup" -defaultButton 1 \
    -button2 "$jamfButtonRequest" \
    -description "$RTMState

Click 'Lookup' to view your RTM on the ServiceNow page
Click 'Request' if you need to submit a new request")

  if [ $buttonClick1 == 0 ]; then
    echo "User clicked Lookup"
    SNURL
    sudo launchctl asuser $uID open $SNLookup
  elif [ $buttonClick1 == 2 ]; then
    echo "User clicked Request"
    submitUSBRequestInSN
  else
    echo "User closed the window"
  fi
  exit 0

}


reRequestUSBRights() {
  echo "Looking up expiration date of previous request"

  #Below lines look up current date from the User EA field (identified with id 4)
  #Then, parses it out in one long Bash string to compare against today's date and return the number of days between
  USBExpirationDate=$(/usr/bin/curl -s -u $jssUser:$jssPass $jssURL/JSSResource/users/name/$Username -H "Accept: application/xml" | /usr/bin/xpath '/user/extension_attributes/extension_attribute[id = "4"]/value/text()' 2>/dev/null)
  echo "Expiration Date: $USBExpirationDate"
  DaysTilExpiration=$(expr 365 - $(expr $(expr $(date '+%s') - $(date -j -f '%Y-%m-%d' $USBExpirationDate '+%s')) / 86400))
  echo "Days til expiration: $DaysTilExpiration"

  if [[ $DaysTilExpiration -lt 0 ]]; then
    echo "User's previous USB Rights have expired"

    buttonClick2=$("$jamfHelper" \
      -windowType hud \
      -icon "$jamfIconSecurity" \
      -title "$jamfTitle" \
      -heading "$jamfHeadingUSB" \
      -button1 "$jamfButtonRequest" -defaultButton 1 \
      -button2 "$jamfButtonMoreInfo" \
      -description "Your previous USB Rights have expired.

Click Request, to submit a new request for USB Rights
Click More Info to learn more about the USB Rights process")

    if [ $buttonClick2 == 0 ]; then
      echo "User clicked Request"
      submitUSBRequestInSN
    elif [ $buttonClick2 == 2 ]; then
      echo "User clicked More info..."
      sudo launchctl asuser $uID open $USBRightsWikiPage
    else
      echo "User closed the window"
    fi
    exit 0

  else
    echo "User still has active USB Rights"

    buttonClick3=$("$jamfHelper" \
      -windowType hud \
      -icon "$jamfIconSecurity" \
      -title "$jamfTitle" \
      -heading "$jamfHeadingUSB" \
      -button1 "$jamfButtonRequest" -defaultButton 1 \
      -button2 "$jamfButtonMoreInfo" \
      -description "Your USB Rights are valid for another $DaysTilExpiration days.

Click Request to renew your rights for another year
Click More Info to learn more about the USB Rights process")

    if [ $buttonClick3 == 0 ]; then
      echo "User clicked Request"
      submitUSBRequestInSN
    elif [ $buttonClick3 == 2 ]; then
      echo "User clicked More info..."
      sudo launchctl asuser $uID open $USBRightsWikiPage
    else
      echo "User closed the window"
    fi
    exit 0

  fi
}


askIfRequestExists() {
  #The user does not have a Request in their Jamf Pro profile so we need to determine if the user submitted via ServiceNow or if they'd like us to submit a request for them

  buttonClick4=$("$jamfHelper" \
    -windowType hud \
    -icon "$jamfIconSecurity" \
    -title "$jamfTitle" \
    -heading "$jamfHeading" \
    -button1 "$jamfButtonRequest" -defaultButton 1 \
    -button2 "$jamfButtonLookup" \
    -description "We do not have a record of a USB Rights request.

If you submitted your request in ServiceNow, please look up your request - it's likely awaiting approval.

If you've never submitted a request, click Request and we'll submit for you.")

  if [ $buttonClick4 == 0 ]; then
    echo "User clicked Request"
    submitUSBRequestInSN
  elif [ $buttonClick4 == 2 ]; then
    echo "User clicked Lookup"
    sudo launchctl asuser $uID open $ServiceNowURL
  else
    echo "User closed the window"
  fi
  exit 0

}

submitUSBRequestInSN() {

  # Submit a ServiceNow ticket
  echo "Submitting to ServiceNow..."
  echo "----------"
  echo "Recipient: $Username"
  echo "Bulk Request: $Bulk"
  echo "Note: $Notes"
  echo "----------"

  #Submit to ServiceNow via Catalog API
  #Production
  APIResponse=($(curl -X POST \
    ${ServiceNowAPIURL}?key=${Auth_Key} \
    -H 'Authorization: Bearer '$Bearer_Token \
    -H 'Content-Type: application/json' \
    -d "{
      \"recipient\": \"$Username\",
      \"bulk_request\": \"$Bulk\",
      \"notes\": \"$Notes\"
    }"))

  echo ""
  echo "ServiceNow submission complete"

  RequestNumber=$(echo $APIResponse | cut -d \" -f 8)

  verifySNResponse

}

verifySNResponse () {
  #verify if API submit was successful
  RTMreturned=$(echo $RequestNumber | cut -c 1-3)
  if [[ $RTMreturned != "RTM" ]]; then
  #Determine if SN cannot find the Approving Manager and proceed with manual submission
    if [[ $(echo "${APIResponse}" | grep "Unable to find manager") ]]; then
      echo "Unable to locate Approving Manager for user. Informing them thusly..."

      "$jamfHelper" \
      -windowType hud \
      -icon "$jamfIconSecurity" \
      -title "$jamfTitle" \
      -heading "$jamfHeadingError" \
      -button1 "$jamfButtonManual" -defaultButton 1 \
      -description "ServiceNow is unable to determine your Approving Manager.

Please click 'Manual' to generate your request in the ServiceNow webform.

NOTE: Be sure to manually input your manager in the correct field."
      sudo launchctl asuser $uID open $ServiceNowUSBRequest
      exit 0
    fi

    echo "API Failure - RTM number not returned"
    echo "Advising user to try again or manually submit request"

    buttonClick5=$("$jamfHelper" \
      -windowType hud \
      -icon "$jamfIconSecurity" \
      -title "$jamfTitle" \
      -heading "$jamfHeadingError" \
      -button1 "$jamfButtonOK" -defaultButton 1 \
      -button2 "$jamfButtonManual" \
      -description "There was a problem submitting your request. Please try again.

If the problem persists, please select Manual to generate your request in ServiceNow")

    if [ $buttonClick5 == 0 ]; then
      echo "User clicked Ok"
    elif [ $buttonClick5 == 2 ]; then
      echo "User clicked Manual"
      sudo launchctl asuser $uID open $ServiceNowUSBRequest
    else
      echo "User closed the window"
    fi
    exit 0

  else
    echo "Request Number: $RequestNumber"

    updateJamfPro

  fi

}

updateJamfPro() {
  #Create an .xml file to use for the PUT into the JSS
  echo "Create temporary USB Request XML file"
  touch /private/tmp/tmpUSBRequest.XML

  #echo the XML section for the user into the .xml file
  echo '<user><name>'$Username'</name><extension_attributes><extension_attribute><id>3</id><name>Authorized for USB</name><type>String</type><value>'$RequestNumber'</value></extension_attribute></extension_attributes></user>' > "/private/tmp/tmpUSBRequest.XML"

  ## If it passes the XMLlint test, try uploading the XML file to the JSS
  if [[ $(XMLlint --format "/private/tmp/tmpUSBRequest.XML" >/dev/null 2>&1; echo $?) == 0 ]]; then
    echo "XML creation successful. Attempting upload to JSS"

    curl -u $jssUser:$jssPass $jssURL/JSSResource/users/name/$Username -H "Content-Type: application/xml" -T "/private/tmp/tmpUSBRequest.XML" -X PUT
    echo "" #add a blank line to the log

    # Check to see if we got a 0 exit status from the PUT command
    if [ $? == 0 ]; then
      echo "Jamf Pro User data updated with request details"
      ## Clean up the XML files
      rm -f "/private/tmp/tmpUSBRequest.XML"
      echo "Delete temporary USB Request XML file"
    else
      echo "Jamf Pro User data update failed"
      # Clean up the XML file
      rm -f "/private/tmp/tmpUSBRequest.XML"
      echo "Delete temporary USB Request XML file"
    fi
  else
    echo "USB Request XML file creation failed"
    # Delete poorly formed XML file
    rm -f "/private/tmp/tmpUSBRequest.XML"
    echo "Delete temporary USB Request XML file"

  fi

  #We can use the same notification regardless of result because the fulfillment process accounts for updating the Request number in Jamf Pro when the request is approved.
  notifyUser
}

notifyUser() {
  echo "Notifying user of Summary Details"

  buttonClick6=$("$jamfHelper" \
    -windowType hud \
    -icon "$jamfIconSecurity" \
    -title "$jamfTitle" \
    -heading "$jamfHeadingSubmitted" \
    -button1 "$jamfButtonOK" -defaultButton 1 \
    -button2 "$jamfButtonMoreInfo" \
    -description "Your USB Rights request was submitted

$RequestNumber

Please follow up with your Manager for approval.
When approval is provided, your machine's USB ports will be available for use.")

  if [ $buttonClick6 == 0 ]; then
    echo "User clicked Ok"
  elif [ $buttonClick6 == 2 ]; then
    echo "User clicked More Info..."
    sudo launchctl asuser $uID open $USBRightsWikiPage
  else
    echo "User closed the window"
  fi

}

##### MAIN #####

echo "Start"
setVariables
echo "End"
