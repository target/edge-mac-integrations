#!/bin/bash
#Created 2/26/18 - Chris Driscoll

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

#Script leverages CocoaDialog to submit a ServiceNow Catalog task for a Mac accessory
#First prompt provides accessory details with option to order or more info...
#Second prompt asks user to select a location to pickup the Accessory
#Third prompt informs the user of a successful submission (or not) and next steps

echo "Start"

#Verify CocoaDialog is installed correctly
if [ -e /Library/Application\ Support/macOS_CPE/CocoaDialog.app ]; then
  echo "CocoaDialog is installed"
  CocoaDialog="/Library/Application Support/macOS_CPE/CocoaDialog.app/Contents/MacOS/CocoaDialog"
else
  echo "CocoaDialog is not installed. Triggering install and notifying user"
  sudo jamf policy -event InstallCocoaDialog
  buttonClick=$(/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
                    -windowType hud \
                    -icon /Library/Application\ Support/macOS_CPE/logo.png \
                    -title "Company • macOS Client Platform Engineering" \
                    -heading "Installing Software" \
                    -button1 "Ok" -defaultButton 1 \
                    -description "Your machine is missing needed software. We're installing it now. Please try again in 5 minutes.")
  exit 1
fi

#Set auth key and bearer token creds
Auth_Key=''
Bearer_Token=''

#Get UID of logged in user for later interaction with the "open" command
User=$(ls -l /dev/console | awk '{print $3}');uID=$(id -u $User)

#####
#Set ServiceNow Catalog API configurations
URL="https://servicenow.api.address.com/service_catalog_entries/v1/mac_hardware_requests?key=${Auth_Key}"
Username=$(/usr/bin/stat -f%Su /dev/console)
Serial=$(ioreg -c IOPlatformExpertDevice -d 2 | awk -F\" '/IOPlatformSerialNumber/{print $(NF-1)}')
Peripheral_Requested="Apple Magic Keyboard"
Approval_Required="false" #this peripheral does not require approval
Approval_Code=""

#Begin prompting user for accessory order
Selections=($("${CocoaDialog}" dropdown --float --string-output --icon computer --title "Virtual Vending Machine" --button1 "Order" --button2 "More info..." --button3 "Cancel" --text "Apple Magic Keyboard



Retail Price: \$99

Magic Keyboard combines a sleek design with a built-in rechargeable battery and enhanced key features. With a stable scissor mechanism beneath each key, as well as optimized key travel and a low profile, Magic Keyboard provides a remarkably comfortable and precise typing experience.

Click the 'Order' button and the fulfillment team will follow-up.
If this is a replacement, please return the defective keyboard for potential reuse or recycle." --items "-- Select Pickup Location--" "HQ Location 1" "HQ Location 2" "Remote Office"))

Button=${Selections[0]}
#Only need the location after confirming the button clicked was Order
if [[ $Button == "Cancel" ]]; then
  echo "User selected Cancel"
  exit 1
elif [[ $Button == "More" ]]; then
  echo "User selected More Info..."
  sudo launchctl asuser $uID open https://www.apple.com/shop/product/MLA22LL/A/magic-keyboard-us-english
else
  echo "User selected Order"

  #If Order was selected, every other element in the array is the Location
  Location=${Selections[@]:1}
  echo "Location selected: $Location"

  # Verify user selected a valid location
  if [[ $Location == "-- Select Pickup Location--" ]]; then
    # Prompt user with new CocoaDialog box informing them to restart the process and select a location
    echo "User did not select a pickup location. Prompting to restart the ordering process"
    "${CocoaDialog}" msgbox --icon x --title "Virtual Vending Machine" --text "Error" --informative-text "You did not select a Pickup location. Please restart the ordering process" --button1 "Ok"
    exit 1
  else

    #####
    #Create a CocoaDialog progressbar so the user knows we're doing something in the background. This is beneficial when the API doesn't immediately respond.
    rm -f /tmp/hpipe
    mkfifo /tmp/hpipe
    "$CocoaDialog" progressbar --indeterminate --title "Virtual Vending Machine" --text "Submitting your request..." < /tmp/hpipe &
    exec 3<> /tmp/hpipe
    
    echo "Submitting to ServiceNow..."
    echo "----------"
    echo "Requested For: $Username"
    echo "Location: $Location"
    echo "Computer Name: $Serial"
    echo "Approval Code: $Approval_Code"
    echo "Peripheral Requested: $Peripheral_Requested"
    echo "Approval Required: $Approval_Required"
    echo "----------"

    #Submit to ServiceNow via Catalog API
    APIResponse=($(curl -X POST \
      $URL \
      -H 'Authorization: Bearer '$Bearer_Token \
      -H 'Content-Type: application/json' \
      -d "{
        \"requested_for\": \"$Username\",
        \"location\": \"$Location\",
        \"computer_name\": \"$Serial\",
        \"approval_code\": \"$Approval_Code\",
        \"peripheral_requested\": \"$Peripheral_Requested\",
        \"approval_required\": \"$Approval_Required\"
      }"))

      echo ""
      echo "ServiceNow submission complete"

      RequestNumber=$(echo $APIResponse | cut -d \" -f 8)

      #Exit CocoaDialog progress bar
      exec 3>&-

      #Verify if API submit was successful
      RTMreturned=$(echo $RequestNumber | cut -c 1-3)
      if [[ $RTMreturned != "RTM" ]]; then
        echo "API Failure - RTM number not returned"
        "${CocoaDialog}" msgbox --icon x --title "Virtual Vending Machine" --text "Error" --informative-text "There was a problem submitting your request.
Please try again in 5 minutes.

If the problem persists, please contact your IT helpdesk" --button1 "Ok"
        exit 1
      else
        echo "Request Number: $RequestNumber"
        echo "Informing user of next steps"
        "$CocoaDialog" msgbox --icon computer --title "Virtual Vending Machine" --text "Request Submitted" --informative-text "
$RequestNumber

The fulfillment team received your request.

• If you selected an HQ pickup location, you can stop by at your next convenience.
• If you are located at a Remote Office, the team will follow up with shipping details." --button1 "Ok"

      fi
    fi
fi

echo "End"
