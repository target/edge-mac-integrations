#!/bin/bash
#Created 6/6/18 - Noah Anderson

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

#Once run, script proceeds in three parts:
#Code will determine the top user on the machine by logged in time
#Next, check their user Extension Attribute to get the number of days until expiration
#Finally, if that number is found to be 15 days or fewer, call a policy to remind the user to renew their rights with a Jamf Helper prompt

if [ "$EUID" -ne 0 ]; then
        echo "Script must be run with sudo or as root"
        exit
fi

#Set the JSS URL for later policy interaction
jssURL=''
#Define API username and password information for interacting with the JSS; JSS user must have CRUD access for Users and User Extension Attributes
apiUser=''
apiPass=''

#Get the top user by login time on the machine to determine if rights are about to expire for this user
top_user=$(ac -p | sort -nk 2 | grep -E -v 'total|admin|root|mbsetup|adobe' | awk 'END{print $1}')
ExpDate=$(curl -s -u ${apiUser}:${apiPass} "${jssURL}JSSResource/users/name/${top_user}" -H "Accept: application/xml" | xpath '/user/extension_attributes/extension_attribute[id = "4"]/value/text()' 2>/dev/null)
#Some one-liner math to get date of granted USB rights from the EA and days until expiration from the current date
DaysTilExp=$(expr 365 - $(expr $(expr $(date '+%s') - $(date -j -f '%Y-%m-%d' "${ExpDate}" '+%s')) / 86400))

if [[ $DaysTilExp -gt 15 ]]; then

	echo "We're only notifying users for less than 15 days... fail out and notify again later."

else

#Define JAMFHelper settings
jamfIcon="/Library/Application Support/macOS_CPE/logo.png"
jamfTitle="Company • macOS Client Platform Engineering"
jamfHeading="USB Rights"
jamfButton_Request="Request"
jamfButton_MoreInfo="More info..."
jamfDesc="Your USB rights are set to expire in ${DaysTilExp} day(s).

Click 'Request' below to re-request your rights for another year.

NOTE: Manager approval *is* required for another year of USB rights."

#Message user that rights have already been elevated
function USBSoonExpires()
{
buttonClick=$(/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
      -windowType hud \
      -icon "${jamfIcon}"\
      -title "${jamfTitle}" \
      -heading "${jamfHeading}" \
      -button1 "${jamfButton_Request}" -defaultButton 1 \
      -button2 "${jamfButton_MoreInfo}" \
      -description "${jamfDesc}")

if [ $buttonClick == 0 ]; then
    echo "User clicked Request"
    #Call policy with the trigger of RequestUSB to re-request rights
    jamf policy -trigger RequestUSB
    exit 0

elif [ $buttonClick == 2 ]; then
    echo "User clicked More info..."
    #Opening the Wiki page on USB Rights on macOS
    User=$(ls -l /dev/console | awk '{print $3}');UserID=$(id -u $User);sudo launchctl asuser $UserID open https://wiki.company.com/wiki/index.php/Portal:Mac/Software/Request_USB

else
    echo "User closed the window"
    exit 0
fi
}

USBSoonExpires

fi
