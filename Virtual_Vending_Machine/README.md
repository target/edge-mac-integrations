## KeyboardMagic.sh

This code is loaded in as a Self Service policy to provide options for users to order a Magic Keyboard peripheral for their Macintosh computer

- Script leverages CocoaDialog to submit a ServiceNow Catalog task for a Mac accessory
    - First prompt provides accessory details with option to order or more info...
    - Second prompt asks user to select a location to pickup the Accessory
    - Third prompt informs the user of a successful submission (or not) and next steps


## Technical Requirements

- CocoaDialog
- ServiceNow with exposed API endpoints (in this case, service_catalog_entries)

## Technical Tidbits

- The code interacts with the service_catalog_entries table in ServiceNow to place the order, so that API needs to be exposed/created for successful interaction
- To show progress, the code also creates a named pipe on the system, and then ties the CocoaDialog progress bar to a background job which takes its input from the named pipe
    - Once we close that pipe, the CD dialog closes
    - The progress bar will show as long as there is some interaction taking place to indicate to the user that the process is still ongoing
