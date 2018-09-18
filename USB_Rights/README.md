# Architectural framework:

USB Rights are restricted via a Configuration Profile scoped out to all users

There is an exclusion scoped out to a Smart User Group based on the following criteria:                                                   
                                                
```
USB Grant Date more than 0 days ago
and
USB Grant Date less than 365 days ago
```
                
Where "USB Grant Date" is a User Extension Attribute (EA) with Data Type of Date and Input Type of Text Field populated as part of the USBFulfillment.sh script in lines 102 and 122 called with the `USBDate` function (set on line 167)

Once user falls into scope of the Smart User Group, they are excluded from the Configuration Profile restriction and profile is removed as soon as MDM communication occurs with the client device (typically a matter of seconds)

Individual scripts are covered below:


## USB15DayPrompt.sh

This is scoped out to a Smart User Group with an execution frequency of "Once every week", as to not totally inundate the user, but give them a few reminders prior to their access expiring

This Smart User Group is based on the following criteria:                                                   

```
USB Grant Date more than 350 days ago
and
USB Grant Date less than 370 days ago
```

NOTE: This has the possibility to deliverer a final reminder after rights have been expired, since the USB restriction will reapply once the user falls out of spec past 365 days in the aforementioned Extension Attribute

This code runs in three parts:

- First part will determine the top user on the machine by logged in time (`ac -p`)
- Next, check their user EA to get the number of days until expiration
- Finally, if that number is found to be 15 days or fewer, call a policy to remind the user to renew their rights with a Jamf Helper prompt


## USBRights.sh

This is the front-end script that is called via Jamf Pro Self Service which can:

- Request USB rights for the first itme
- Detail information regarding an existing request in ServiceNow
- Show how many days remain with the currently granted rights
- Provide information about USB rights via a Wiki page that contains the documented process
- Re-request rights

The script is well commented and includes information about every function and section of code.


## USBFulfillment.sh

This is the fulfillment side of granting USB rights after a request has been properly submitted via the `USBRights.sh` code above

The crux of the code:
- Writes the approved task number (TSK#) to the requestor's user EA in a field for tracking purposes
- Appends the current date to a separate user EA
	- This causes the user to fall into scope of a Smart Group (mentioned above), which then excludes the user from the USB restriction on their primary machine(s)

It's roughly equal parts Jamf Pro and ServiceNow interaction, and includes the ability to submit failure notices via Slack webhooks

The high level overview of the process is as follows:

- Looks in the catalog task bucket for open USB tasks identifiable by their short name, and puts the TSKs into an iterable array
- Iterates over the array of tasks, grabbing user information and includes error handling/notifying connected to Slack
- The happy path is that a user already has a user account in the JSS and we add today's date and the associated TSK# to two EAs in Jamf Pro via functions defined in the code
- If a user is not identified in Jamf Pro, we create their account via the API with the associated TSK attached and then proceed to add the date
- Finally, write back to the user and close the associated TSK (via another function) before fulfilling any others in the array

This code is loaded in as a Jenkins job set to run every 5 minutes, but could be loaded as a crontab or other scheduled task manager
