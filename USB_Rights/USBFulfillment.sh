#!bin/bash
#Created 6/8/18 - Noah Anderson

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

#Dependencies:
#jq (for JSON parsing from ServiceNow)
#xpath (for XML parsing from Jamf Pro)

#The below function completes the following steps:
#Looks in the catalog task bucket for open USB tasks identifiable by their short name, and puts the TSKs into an iterable array
#Iterates over the array of tasks, grabbing user information and includes error handling/notifying connected to Slack
#The happy path is that a user already has a user account in the JSS and we add today's date and the associated TSK# to two Extension Attributes in Jamf Pro via functions defined below
#If a user is not identified in Jamf Pro, we create their account via the API with the associated TSK attached and then proceed to add the date
#Finally, after confirming all is well, write back to the user and close the associated TSK (via function defined below) before continuing with any others in the array

#Set variables for later ServiceNow interaction
Bearer_Token=''
Auth_Key=''

	function USBGrant()
{

#This gets all open tasks for USB individual requests in the bucket (if any exist)

#Prod URL and auth
#We're looking for open fulfillment tasks in the bucket of the group, grabbing the short description and number from the JSON with jq, and parsing out the ones that are for USB requests
TaskArray=($(curl -X GET -H "Authorization: Bearer ${Bearer_Token}" "https://servicenow.api.address.com/fulfillment_tasks/v1?assignment_group=Name%2520Of%2520Client%2520Group&field_groups=without_variables&key=${Auth_Key}" | jq '.[] | { short_description, number}' 2>/dev/null | grep -A1 'USB.*Individual' | awk '/USB/{getline; print}' | awk -F'"' '$0=$4'  | fmt))

#If TaskArray is empty, then we know there are no SN USB tasks to address
if [[ ${TaskArray[@]} = "" ]]; then
	echo "No USB tasks in the bucket; exiting script..."
	exit 0
else
    echo "Addressing ${#TaskArray[@]} USB tasks..."

    for SNTask in "${TaskArray[@]}"
    do
        echo "Fulfilling ServiceNow task#" $SNTask

        #Set the JSS URL for later policy interaction
        jssURL=''
        #Define API username and password information for the JSS interaction; JSS user must have CRUD access for Users, User Extension Attributes, and Static Computer Groups
        apiUser=''
        apiPass=''

        #Pulls the requesting user's username from the downloaded catalog task JSON for later verification
        UserToGrant=$(curl -X GET -H "Authorization: Bearer ${Bearer_Token}" "https://servicenow.api.address.com/fulfillment_tasks/v1/$SNTask?key=${Auth_Key}" | jq -C '.variables[] ' | awk '/Recipient/,/user_name/' | grep user_name | awk -F'"' '$0=$4')

        #Echo statements to track progress of the provision in the logs
        echo "User requesting access is" $UserToGrant
        sleep 1

        #We've sometimes seen empty cURL responses when interacting with the API to pull down JSON data. If the variable $UserToGrant is blank (which is pulled from a mandatory field), we know there was an empty reply from the server, to cancel out of the current request, notify the Slack channel, and pick it up at the next run time.
        if [ "$UserToGrant" == "" ]; then
            echo "We're unable to pull down a response from the SN API server at this time. Exiting out and we'll try again later..."
	    exit 1
	    USBFail
        else
            echo "User value is intact... continuing"
        fi

	#This *shouldn't* be needed with the Self Service side checks we have for users in the JSS, but in case we need to for fulfillment, we'll create a user record (manual requests in Self Service)
        UserCheck=$(curl -sfku "${apiUser}:${apiPass}" "${jssURL}/JSSResource/users/name/$UserToGrant" -H "Accept: application/xml" | xpath '/user/name/text()' 2>/dev/null)

        if [ ! "$UserCheck" ]; then

                echo "User doesn't exist yet in the JSS -- adding record"

                curl -fku "${apiUser}":"${apiPass}" ${jssURL}/JSSResource/users/id/0 -X POST -H "Content-Type: application/xml" -d "<user>
  <name>$UserToGrant</name>
  <extension_attributes>
    <extension_attribute>
      <id>3</id>
      <name>Authorized for USB</name>
      <type>String</type>
      <value>$SNTask</value>
    </extension_attribute>
  </extension_attributes>
</user>"

sleep 2

	USBDate
	
	if [[ "$USBDateCode" == 0 ]]; then
                        echo "All good! Writing back to user and informing them thusly."
	                USBComplete
			sleep 2
                        #Call the function again to proceed with remaining tasks (if any)
                        USBGrant
	else
		echo "One or more user EA add failed... exiting out and trying again next time."
                USBFail
		exit 1

	fi
	
        else

                echo "User record exists... adding SN TSK# to user EA."
                USBYes
		sleep 2
		USBDate

		if [[ "$USBYesCode" == 0 ]] && [[ "$USBDateCode" == 0 ]]; then
			echo "All good! Writing back to user and informing them thusly."
			USBComplete
			#Call the function again to proceed with remaining tasks (if any)
                	USBGrant	
		else
			echo "One or more user EA add failed... exiting out and trying again next time."
			USBFail
			exit 1
		fi
        fi

    done
fi

}

#Set USB failure with current TSK if notification is necessary to report to Slack
#More information with getting started is available here: https://api.slack.com/incoming-webhooks
	function USBFail()
{
curl -X POST --data-urlencode "payload={\"attachments\": [{\"color\": \"#FF0000\", \"title\": \"USB Fulfillment Failure\", \"title_link\": \"https://company.service-now.com/text_search_exact_match.do?sysparm_search=${SNTask}\", \"text\": \"Fulfillment of $SNTask failed at $(date "+%r")\"}], \"channel\": \"#CHANNEL\", \"username\": \"USB Failure\", \"icon_emoji\": \":slack:\"}" https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX
}


#Defining USB approval EAs
        function USBYes()
{
#Function appends ServiceNow TSK# to user's JSS record and echos out an exit code which we'll check against to indicate success or failure
 curl -fku "${apiUser}":"${apiPass}" ${jssURL}/JSSResource/users/name/$UserToGrant -X PUT -H "Content-Type: application/xml" -d "<user>
  <name>$UserToGrant</name>
  <extension_attributes>
    <extension_attribute>
      <id>3</id>
      <name>Authorized for USB</name>
      <type>String</type>
      <value>$SNTask</value>
    </extension_attribute>
  </extension_attributes>
</user>"

USBYesCode=$(echo $?)

}
	 function USBDate()
{

Date=$(date +%Y-%m-%d)

#Function appends today's date to user's JSS record in a format understandable by Jamf Pro (YYYY-MM-DD) and echos out an exit code which we'll check against to indicate success or failure
curl -fku "${apiUser}":"${apiPass}" ${jssURL}/JSSResource/users/name/$UserToGrant -X PUT -H "Content-Type: application/xml" -d "<user>
  <name>$UserToGrant</name>
  <extension_attributes>
    <extension_attribute>
      <id>4</id>
      <name>USB Grant Date</name>
      <type>Date</type>
      <value>$Date</value>
    </extension_attribute>
  </extension_attributes>
</user>"

USBDateCode=$(echo $?)

}

#This function submits a comment to the existing ServiceNow TSK indicating USB Rights have been granted and then closes the task as complete
	function USBComplete()
{
        #Message complete; Prod
        curl -X PUT -H "Authorization: Bearer ${Bearer_Token}" -H "Content-Type: application/json" -d '{"comments":"USB rights for user '"$UserToGrant"' have been granted and should take effect within a few minutes. If USB rights are not enabled after a restart, please reach out to your IT helpdesk."}' "https://servicenow.api.address.com/fulfillment_tasks/v1/$SNTask?key=${Auth_Key}"
        #Close complete; Prod
        curl -X PUT -H "Authorization: Bearer ${Bearer_Token}" -H "Content-Type: application/json" -d '{"state":"3"}' "https://servicenow.api.address.com/fulfillment_tasks/v1/$SNTask?key=${Auth_Key}"
}

#MAIN
echo "Begin"
USBGrant
echo "End"
