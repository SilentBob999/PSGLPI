# Internal Functions have names WITHOUT dash "-" caracter.

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Function Set-GLPIToken {
    param($Creds)
    if (("Basic","user_token") -ccontains $Creds.AuthorizationType) {
        $Script:GLPICreds = $Creds
        GetGLPISessionToken -force $true | Out-Null
    }
    else {
        throw 'AuthorizationType MUST be "user_token" or "Basic". This is Case Sensitive.'
    }
}
Function GetGLPISessionToken {
    [CmdletBinding()]
    param(
        [bool]$Force=$false,
        $creds
        )

    if ( ("$($Script:GLPICreds)" -eq "") ){
        if ("$Creds" -ne "") {
            Set-GLPIToken $creds
        } else {
            throw "GLPI credential not set.  Please use Set-GLPIToken"
        }
    }
    try {
        if ( ("$($Script:SessionToken)" -eq "") -or ($true -eq $Force) ) {
            $Script:SessionToken = Invoke-RestMethod "$($Script:GLPICreds.AppURL)/initSession" -Headers @{"Content-Type" = "application/json";"Authorization" = "$($Script:GLPICreds.AuthorizationType) $($Script:GLPICreds.UserToken)";"App-Token"=$Script:GLPICreds.AppToken}
        }

        # Test session, also serve as workaround against a bug from plugin MyDashboard (first request return html)
        Invoke-RestMethod "$($Script:GLPICreds.AppUrl)/getActiveProfile/" -Headers @{"session-token"=$Script:SessionToken.session_token; "App-Token" = "$($Script:GLPICreds.AppToken)"} -ErrorAction SilentlyContinue | Out-Null
    } catch {
        try {
            $Script:SessionToken = Invoke-RestMethod "$($Script:GLPICreds.AppURL)/initSession" -Headers @{"Content-Type" = "application/json";"Authorization" = "$($Script:GLPICreds.AuthorizationType) $($Script:GLPICreds.UserToken)";"App-Token"=$Script:GLPICreds.AppToken}
            Invoke-RestMethod "$($Script:GLPICreds.AppUrl)/getActiveProfile/" -Headers @{"session-token"=$Script:SessionToken.session_token; "App-Token" = "$($Script:GLPICreds.AppToken)"} -ErrorAction SilentlyContinue | Out-Null
        } catch {
            $CustomMessage = "Cannot get a GLPI session token"
            $CustomError = New-Object Management.Automation.ErrorRecord (
                [System.Exception]::new($CustomMessage ,$_.Exception),'NotSpecified','OperationStopped',$_)
            $PScmdlet.ThrowTerminatingError($CustomError)
        }
    }
    # return for original function compatibility
    return $Script:SessionToken
}

function Stop-GlpiSession {
    param ()
    Invoke-RestMethod "$($Script:GLPICreds.AppUrl)/killSession" -Headers @{"session-token"=$Script:SessionToken.session_token; "App-Token" = "$($Script:GLPICreds.AppToken)"} -ErrorAction SilentlyContinue| Out-Null
}

function Get-GlpiBase64Login {
    <#
.SYNOPSIS
    The Base64 encoded login & password.
.DESCRIPTION
    Generate the Base64 login & password string used to authenticate with GLPI.
.PARAMETER login
    User name
.PARAMETER password
    Password
.EXAMPLE
     Get-GLPILoginBase64 -login "MyGlpiUser" -password "MyGlpiPassword"
.INPUTS
    Strings
.OUTPUTS
    String
.NOTES
    Author:  Jean-Christophe Pirmolin #>
    param([parameter(Mandatory=$true)][String]$login,[parameter(Mandatory=$true)][String]$password)
    $sStringToEncode="$($login):$($password)"
    $sEncodedString=[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($sStringToEncode))
    return $sEncodedString
}


Function Get-GlpiItems {
    <#
.SYNOPSIS
    Get all items of a specific item type.
.DESCRIPTION
    Retrieve all items of a specific item type by range.
    Useful for instance, to load a list in memory and avoid multiple call to an existing collection.
.PARAMETER ItemType
    Type of item wanted.
    Exemples : Computer, Monitor, User, etc.
.PARAMETER Range
    Range of the results.
    Exemple : 0-199
.PARAMETER SearchText
    SearchText (default NULL): hashtable of filters to pass on the query (with key = field and value the text to search).
    By default it act as a like "*". Use ^ and $ to force an exact match.
.PARAMETER QueryOptions
    Give flexibility to use other option not set in module
    Like : "searchText[name]=^computername$&only_id=true&get_hateoas=false"
.PARAMETER Creds
    Credetials for the GLPI API. This is an object.
    Exemple : $GlpiCreds = @{
                    AppURL =     "https://[MyGlpiServer]/apirest.php"
                    UserToken =  "c8BRf8uJHPDr1AyDTgt2zm95S6EdMAHPXK6qTxlA"
                    AppToken =   "EaNdrm33jKDFVdK8gvFQtOf1XHki2Y4BVtPKssgl"
                    AuthorizationType = "Basic" or "user_token"
                    }
.EXAMPLE
     Get-GlpiItems -ItemType "Location" -Range "0-99" -Creds $GlpiCreds
     Get-GlpiItems -ItemType "Group_Ticket" -SearchText @{"groups_id"="^10$" ; "type"="^2$"}
.INPUTS
    None
.OUTPUTS
    Array
.NOTES
    Author:  Jean-Christophe Pirmolin #>
    param([parameter(Mandatory=$true)][String]$ItemType,[parameter(Mandatory=$false)][String]$Range="ALL",$QueryOptions="",[parameter(Mandatory=$false)][hashtable]$SearchText,[parameter(Mandatory=$false)][Object]$Creds)
    if ("$QueryOptions" -ne ""){$QueryOptions = "&$QueryOptions"}
    $SessionToken = GetGLPISessionToken -Creds $Creds
    $SearchTextString = ""
    foreach ($key in $SearchText.Keys) {
        $SearchTextString += "&searchText[$($key)]=$($SearchText[$key])"
    }
    if ($Range -like "ALL") {
        $SearchResult = @()
        $x = 0
        do {
            try {
                $while = $true
                $SearchResult += Invoke-RestMethod "$($Script:GLPICreds.AppUrl)/$($ItemType)/?range=$x-$($x+999)$($SearchTextString)$($QueryOptions)" -Headers @{"session-token"=$SessionToken.session_token; "App-Token" = "$($Script:GLPICreds.AppToken)"}
                $x = $x + 1000
            }
            catch {
                if ($_ -like "*ERROR_RANGE_EXCEED_TOTAL*") {
                    $while = $false
                } else {
                    $CustomMessage = "$_"
                    $CustomError = New-Object Management.Automation.ErrorRecord (
                        [System.Exception]::new($CustomMessage ,$_.Exception),'NotSpecified','OperationStopped',$_)
                    $PScmdlet.ThrowTerminatingError($CustomError)
                }
            }
        } while ($while)
    } else {
        $SearchResult = Invoke-RestMethod "$($Script:GLPICreds.AppUrl)/$($ItemType)/?range=$($Range)$($SearchTextString)$($QueryOptions)" -Headers @{"session-token"=$SessionToken.session_token; "App-Token" = "$($Script:GLPICreds.AppToken)"}
    }

    if ($SearchResult.Count -ge 1) {$SearchResult}
    else {$false}
}

Function Get-GlpiItem {
    <#
.SYNOPSIS
    Get a specific item by item type.
.DESCRIPTION
    Retrieve a specific item.
    Return the instance fields of item identified by id
.PARAMETER ItemType
    Type of item wanted.
    Exemples : Computer, Monitor, User, etc.
.PARAMETER ID
    ID of item wanted.
    Exemples : 114
.PARAMETER Creds
    Credetials for the GLPI API. This is an object.
    Exemple : $GlpiCreds = @{
                    AppURL =     "https://[MyGlpiServer]/apirest.php"
                    UserToken =  "c8BRf8uJHPDr1AyDTgt2zm95S6EdMAHPXK6qTxlA"
                    AppToken =   "EaNdrm33jKDFVdK8gvFQtOf1XHki2Y4BVtPKssgl"
                    AuthorizationType = "Basic" or "user_token"
                    }
.EXAMPLE
     Get-GlpiItem -ItemType "Monitor" -ID 114 -Creds $GlpiCreds
.INPUTS
    None
.OUTPUTS
    Array
.NOTES
    Author:  Jean-Christophe Pirmolin #>
    param([parameter(Mandatory=$true)][String]$ItemType, [parameter(Mandatory=$true)][Int]$ID, $QueryOptions="", [parameter(Mandatory=$false)][object]$Creds)
    $SessionToken = GetGLPISessionToken -Creds $Creds
    $SearchResult = Invoke-RestMethod "$($Script:GLPICreds.AppUrl)/$($ItemType)/$($ID)?$QueryOptions" -Headers @{"session-token"=$SessionToken.session_token; "App-Token" = "$($Script:GLPICreds.AppToken)"} -ErrorAction Ignore
    if ($SearchResult) {$SearchResult}
    else {$false}
}

Function Get-GlpiSubItems {
    <#
.SYNOPSIS
    Get a sub_itemtype for the identified item.
.DESCRIPTION
    Return a collection of rows of the sub_itemtype for the identified item.
.PARAMETER ItemType
    Type of item wanted.
    Exemples : Computer, Monitor, User, etc.
.PARAMETER ID
    ID of item wanted.
    Exemples : 114
.PARAMETER QueryOptions
    Give flexibility to use other option not set in module
    Exemples : ???
.PARAMETER Relation
    Name of the subitem.
    Exemples : Infocom, NetworkPort, ComputerModel, etc.
.PARAMETER Creds
    Credetials for the GLPI API. This is an object.
    Exemple : $GlpiCreds = @{
                    AppURL =     "https://[MyGlpiServer]/apirest.php"
                    UserToken =  "c8BRf8uJHPDr1AyDTgt2zm95S6EdMAHPXK6qTxlA"
                    AppToken =   "EaNdrm33jKDFVdK8gvFQtOf1XHki2Y4BVtPKssgl"
                    AuthorizationType = "Basic" or "user_token"
                    }
.EXAMPLE
     Get-GlpiItem -ItemType "computer" -ID 114 -Creds $GlpiCreds -Relation infocom
.INPUTS
    None
.OUTPUTS
    Array
.NOTES
    Author:  Jean-Christophe Pirmolin #>
    param([parameter(Mandatory=$true)][String]$ItemType, [parameter(Mandatory=$true)][Int]$ID, [String]$QueryOptions="", [parameter(Mandatory=$false)][Object]$Creds, [parameter(Mandatory=$true)][String]$Relation)
    $SessionToken = GetGLPISessionToken -Creds $Creds
    $SearchResult = Invoke-RestMethod "$($Script:GLPICreds.AppUrl)/$($ItemType)/$($ID)/$($Relation)?$QueryOptions" -Headers @{"session-token"=$SessionToken.session_token; "App-Token" = "$($Script:GLPICreds.AppToken)"} -ErrorAction Ignore
    if ($SearchResult) {$SearchResult}
    else {$false}
}

Function Search-GlpiItem {
    <#
.SYNOPSIS
    Use the GLPI Search Engine.
.DESCRIPTION
    Expose the GLPI searchEngine and combine criteria to retrieve a list of elements of specified itemtype.
.PARAMETER ItemType
    Type of item wanted.
    Note : you can use 'AllAssets' itemtype to retrieve a combination of all asset's types.
    Exemples : Computer, Monitor, User, etc.
.PARAMETER SearchOptions
    SearchOptions should be given in a form of array of arrays.
    ("AND",1,"contains","AMC0132"),("OR",1,"contains","AMC0176")
    If only ONE criteria is present, start with a COMA!
     ,("OR",1,"contains","AMC0176")
    BE CAREFULL the first coma in the SearchOption definition!!
    You can use Get-GlpiSearchOptions to display the list of search options (fields) available for a specific item type.
    If you want to retreive a specific field that is missing the default result view, you can add it to the SearchOptions under the form of ,("OR",[FieldID],"contains","")
    Exemples : ("AND",1,"contains","AMC"),("AND",105,"is","Luxembourg") to find items that contains "AMC" in the name AND are located in "Luxembourg".
    ,("OR",1,"contains","AMC0176") to find items that contains "AMC0176" in the name.
.PARAMETER ForceDisplay
    A simple array of desired fields in the answer. Based on visible fields with Get-GlpiSearchOptions.
    Fields can be numbered or named for more lax use.
    Examples: @("hostnamefield", "otherserial", "1", "2", "5")
.PARAMETER Range
    Range of the results. (Optional, default is 0-999)
    Exemple : 0-199
.PARAMETER Creds
    Credetials for the GLPI API. This is an object.
    Exemple : $GlpiCreds = @{
                    AppURL =     "https://[MyGlpiServer]/apirest.php"
                    UserToken =  "c8BRf8uJHPDr1AyDTgt2zm95S6EdMAHPXK6qTxlA"
                    AppToken =   "EaNdrm33jKDFVdK8gvFQtOf1XHki2Y4BVtPKssgl"
                    AuthorizationType = "Basic" or "user_token"
                    }
.EXAMPLE
     Search-GlpiItem -ItemType "Monitor" -SearchOptions @(,@("AND",1,"is","DELL P2214H")) -ForceDisplay @("1","2","4","serial") -Creds $GlpiCreds
.INPUTS
    None
.OUTPUTS
    Array
.NOTES
    Author:  Jean-Christophe Pirmolin #>
    param([Parameter(Mandatory=$true)][String] $ItemType,[Parameter(Mandatory=$true)][array] $SearchOptions,[String]$Range="0-99999",[array]$ForceDisplay=@("1","2"),[Parameter(Mandatory=$false)][Object]$Creds)

    # Building the SearchOptions String
    $i=0
    foreach ($Criteria in $SearchOptions) {
        if ($i -eq 0) {$StrSearchOptions = "criteria[$($i)][link]=$($Criteria[0])&criteria[$($i)][field]=$($Criteria[1])&criteria[$($i)][searchtype]=$($Criteria[2])&criteria[$($i)][value]=$($Criteria[3])"
        }
        else {$StrSearchOptions = "$($StrSearchOptions)&criteria[$($i)][link]=$($Criteria[0])&criteria[$($i)][field]=$($Criteria[1])&criteria[$($i)][searchtype]=$($Criteria[2])&criteria[$($i)][value]=$($Criteria[3])"
        }
        $i++
    }
    $SessionToken = GetGLPISessionToken -Creds $Creds

    $forcedisplayString = ""
    $i=0
    foreach ($F in $(Get-GlpiSearchOptions -ItemType $ItemType -Creds $Creds  | Where-Object {(($_."ID" -in $ForceDisplay)  -or ($_."Name" -in $ForceDisplay) -or ($_."Field Name" -in $($ForceDisplay | Where-Object {$_ -notlike "name" -and $_ -notlike "id"})))})){
        $forcedisplayString += "&forcedisplay[$i]=$($F.ID)"
      $i++
    }

    $SearchResult = Invoke-RestMethod "$($Script:GLPICreds.AppUrl)/search/$($ItemType)?$StrSearchOptions&range=$($Range)$forcedisplayString" -Headers @{"session-token"=$SessionToken.session_token; "App-Token" = "$($Script:GLPICreds.AppToken)"} -ErrorAction Ignore
    if ($SearchResult) {$SearchResult.data}
    else {return $false}
}

Function Get-GlpiSearchOptions {
    <#
.SYNOPSIS
    List search option for GLPI Search Engine.
.DESCRIPTION
    Expose the GLPI searchEngine options / fields for a specified item type.
.PARAMETER ItemType
    Type of item wanted.
    Note : you can use 'AllAssets' itemtype to retrieve a combination of all asset's types.
    Exemples : Computer, Monitor, User, etc.
.PARAMETER Creds
    Credetials for the GLPI API. This is an object.
    Exemple : $GlpiCreds = @{
                    AppURL =     "https://[MyGlpiServer]/apirest.php"
                    UserToken =  "c8BRf8uJHPDr1AyDTgt2zm95S6EdMAHPXK6qTxlA"
                    AppToken =   "EaNdrm33jKDFVdK8gvFQtOf1XHki2Y4BVtPKssgl"
                    AuthorizationType = "Basic" or "user_token"
                    }
.EXAMPLE
     Get-GlpiSearchOptions -ItemType "Monitor" -Creds $GlpiCreds
.INPUTS
    None
.OUTPUTS
    Array
.NOTES
    Author:  Jean-Christophe Pirmolin #>
    param([parameter(Mandatory=$true)][String]$ItemType,[parameter(Mandatory=$false)][Object]$Creds)
    $SessionToken = GetGLPISessionToken -Creds $Creds
    $SearchResult = Invoke-RestMethod "$($Script:GLPICreds.AppURL)/listSearchOptions/$($ItemType)" -Headers @{"session-token"=$SessionToken.session_token; "App-Token" = "$($Script:GLPICreds.AppToken)"} -ErrorAction Ignore
    $SearchResultRaw = Invoke-RestMethod "$($Script:GLPICreds.AppURL)/listSearchOptions/$($ItemType)?raw" -Headers @{"session-token"=$SessionToken.session_token; "App-Token" = "$($Script:GLPICreds.AppToken)"} -ErrorAction Ignore
    if ($SearchResult) {
        $SearchOptions = $SearchResult.PSObject.Properties #| Select-Object -property Value | Select-Object -Property *
        $SearchOptionsRaw = $SearchResultRaw.PSObject.Properties
        $Result = @()
        $count = 0
        foreach ($Option in $SearchOptions) {
            $item = New-Object psobject
            $Item | Add-Member -Type NoteProperty -Name ID -Value $Option.name
            $Item | Add-Member -Type NoteProperty -Name "Field Name" -Value $Option.value.field
            $Item | Add-Member -Type NoteProperty -Name Name -Value $Option.value.name
            $Item | Add-Member -Type NoteProperty -Name table -Value $Option.value.table
            $Item | Add-Member -Type NoteProperty -Name datatype -Value $Option.value.datatype
            $Item | Add-Member -Type NoteProperty -Name available_searchtypes -Value $Option.value.available_searchtypes
            $Item | Add-Member -Type NoteProperty -Name uid -Value $Option.value.uid
            $Item | Add-Member -Type NoteProperty -Name nosearch -Value $Option.value.nosearch
            $Item | Add-Member -Type NoteProperty -Name nodisplay -Value $Option.value.nodisplay
            $Item | Add-Member -Type NoteProperty -Name linkfield -Value @($SearchOptionsRaw)[$count].value.linkfield
            $Item | Add-Member -Type NoteProperty -Name joinparams -Value @($SearchOptionsRaw)[$count].value.joinparams
            $Item | Add-Member -Type NoteProperty -Name massiveaction -Value @($SearchOptionsRaw)[$count].value.massiveaction
            $Item | Add-Member -Type NoteProperty -Name forcegroupby -Value @($SearchOptionsRaw)[$count].value.forcegroupby
            $Item | Add-Member -Type NoteProperty -Name usehaving -Value @($SearchOptionsRaw)[$count].value.usehaving
            $Item | Add-Member -Type NoteProperty -Name searchtype -Value @($SearchOptionsRaw)[$count].value.searchtype
            $Result += $item
            $count += 1
            }
        }
    else {return $false}
    return $Result
}


Function Add-GlpiItem {
        <#
.SYNOPSIS
    Add an object into GLPI.
.DESCRIPTION
    Add an object (or multiple objects) into GLPI.
.PARAMETER ItemType
    Type of item wanted.
    Note : you can use 'AllAssets' itemtype to retrieve a combination of all asset's types.
    Exemples : Computer, Monitor, User, etc.
.PARAMETER Details
    Describe the details of the object you wan to add into GLPI.
    It is expected to be an object that you can create using :
    $Details = @{
        name="PC99999"
        serial="01.02.03.04.05"}
.PARAMETER Creds
    Credetials for the GLPI API. This is an object.
    Exemple : $GlpiCreds = @{
                    AppURL =     "https://[MyGlpiServer]/apirest.php"
                    UserToken =  "c8BRf8uJHPDr1AyDTgt2zm95S6EdMAHPXK6qTxlA"
                    AppToken =   "EaNdrm33jKDFVdK8gvFQtOf1XHki2Y4BVtPKssgl"
                    AuthorizationType = "Basic" or "user_token"
                    }
.EXAMPLE
    $Details = @{
        name="PC99999"
        serial="01.02.03.04.05"}
    Add-GlpiItem -ItemType "computer" -Details $Details -Creds $GlpiCreds
.INPUTS
    None
.OUTPUTS
    Array
.NOTES
    Author:  Jean-Christophe Pirmolin #>
    param([parameter(Mandatory=$true)][String]$ItemType,[parameter(Mandatory=$true)][Object]$Details,[parameter(Mandatory=$false)][Object]$Creds)
    $Details = @{input=$Details}
    $SessionToken = GetGLPISessionToken -Creds $Creds
    $json = ConvertTo-Json $Details
    if (($Details["input"] | Get-Member -MemberType Properties).Count -eq 1){
        $json = $json.Remove(($lastIndex = $json.LastIndexOf("]")),1).Insert($lastIndex,"").Remove(($firstIndex = $json.IndexOf("[")),1).Insert($firstIndex,"")
    }
    $AddResult = Invoke-RestMethod "$($Script:GLPICreds.AppUrl)/$($ItemType)" -Method Post -Headers @{"session-token"=$SessionToken.session_token; "App-Token" = "$($Script:GLPICreds.AppToken)"} -Body  ([System.Text.Encoding]::UTF8.GetBytes($json)) -ContentType 'application/json; charset=utf8'
    return $AddResult
}


Function Update-GlpiItem {
    <#
.SYNOPSIS
    Update an object into GLPI.
.DESCRIPTION
    Update an object into GLPI.
.PARAMETER ItemType
    Type of item wanted.
    Note : you can use 'AllAssets' itemtype to retrieve a combination of all asset's types.
    Exemples : Computer, Monitor, User, etc.
.PARAMETER Details
    Describe the details of the object you wan to update into GLPI.
    It is expected to be an object that you can create using :
    ID field is mandatory.
    $Details = @{
        id="107"
        name="PC99999"
        serial="01.02.03.04.05"}
.PARAMETER Creds
    Credetials for the GLPI API. This is an object.
    Exemple : $GlpiCreds = @{
                    AppURL =     "https://[MyGlpiServer]/apirest.php"
                    UserToken =  "c8BRf8uJHPDr1AyDTgt2zm95S6EdMAHPXK6qTxlA"
                    AppToken =   "EaNdrm33jKDFVdK8gvFQtOf1XHki2Y4BVtPKssgl"
                    AuthorizationType = "Basic" or "user_token"
                    }
.EXAMPLE
    $Details = @{
        id="107"
        name="PC99999"
        serial="01.02.03.04.05"}
    Update-GlpiItem -ItemType "computer" -Details $Details -Creds $GlpiCreds
.INPUTS
    None
.OUTPUTS
    Array
.NOTES
    Author:  Jean-Christophe Pirmolin #>
    param($ItemType, $Details, $Creds)
    $Details = @{input=$Details}
    $SessionToken = GetGLPISessionToken -Creds $Creds
    $json = $Details | ConvertTo-Json
    if (($Details["input"] | Get-Member -MemberType Properties).Count -eq 1){
        $json = $json.Remove(($lastIndex = $json.LastIndexOf("]")),1).Insert($lastIndex,"").Remove(($firstIndex = $json.IndexOf("[")),1).Insert($firstIndex,"")
    }
    $UpdateResult = Invoke-RestMethod "$($Script:GLPICreds.AppUrl)/$($ItemType)" -Method Put -Headers @{"session-token"=$SessionToken.session_token; "App-Token" = "$($Script:GLPICreds.AppToken)"} -Body  ([System.Text.Encoding]::UTF8.GetBytes($json)) -ContentType 'application/json; charset=utf8'

    # Result formating
    $Result = @()
    foreach ($R in $UpdateResult){
        $ResultItem = New-Object psobject
        $ResultItem | Add-Member -Type NoteProperty -Name id -Value $(($R.PSObject.Properties | Where-Object TypeNameOfValue -EQ "System.Boolean").name)
        $ResultItem | Add-Member -Type NoteProperty -Name message -Value "Update $($ItemType): $(($R.PSObject.Properties | Where-Object TypeNameOfValue -EQ "System.Boolean").value) ($(($R.PSObject.Properties | Where-Object TypeNameOfValue -EQ "System.Boolean").name))$(($R.PSObject.Properties | Where-Object name -EQ "message").value)"
        $Result += $ResultItem
    }

    return $Result
}

Function Remove-GlpiItems {
    <#
.SYNOPSIS
    Get a specific item by item type.
.DESCRIPTION
    Retrieve a specific item.
    Return the instance fields of item identified by id
.PARAMETER ItemType
    Type of item wanted.
    Exemples : Computer, Monitor, User, etc.
.PARAMETER IDs
    Array of IDs of item to remove. If only ONE criteria is present, start with a COMA!
    Exemples : ,(114) or (110,114)
.PARAMETER Creds
    Credetials for the GLPI API. This is an object.
    Exemple : $GlpiCreds = @{
                    AppURL =     "https://[MyGlpiServer]/apirest.php"
                    UserToken =  "c8BRf8uJHPDr1AyDTgt2zm95S6EdMAHPXK6qTxlA"
                    AppToken =   "EaNdrm33jKDFVdK8gvFQtOf1XHki2Y4BVtPKssgl"
                    AuthorizationType = "Basic" or "user_token"
                    }
.PARAMETRE Purge
    If the itemtype have a trashbin, you can force purge (delete finally).Default: False
.PARAMETRE History
    Set to false to disable saving of deletion in global history. Default: True.
.EXAMPLE
     Remove-GlpiItems -ItemType "Monitor" -IDs 114 -Purge $true -History $false -Creds $GlpiCreds
.INPUTS
    None
.OUTPUTS
    Array
.NOTES
    Author:  Jean-Christophe Pirmolin #>
    param([parameter(Mandatory=$true)][String]$ItemType, [parameter(Mandatory=$true)]$IDs, [Boolean]$Purge=$false, [Boolean]$History=$true, [parameter(Mandatory=$false)][object]$Creds)
    # Build array of IDs.
    if ($IDs -notcontains "ID"){
        $ids2 = @()
        foreach ($ID in $IDs){
            $hash = [ordered]@{}
            $hash.add("id" , $ID)
            $ids2 += [pscustomobject]$hash
        }
        $IDs = $ids2
    }
    $Details = @{
        input=$IDs
        force_purge =  $Purge
        history = $History}
    $json = $Details | ConvertTo-Json
    #if (($Details["input"] | Get-Member -MemberType Properties).Count -eq 1){
    #    $json = $json.Remove(($lastIndex = $json.LastIndexOf("]")),1).Insert($lastIndex,"").Remove(($firstIndex = $json.IndexOf("[")),1).Insert($firstIndex,"")
    # }
    $SessionToken = GetGLPISessionToken -Creds $Creds
    Invoke-RestMethod "$($Script:GLPICreds.AppUrl)/$($ItemType)" -Method Delete -Headers @{"session-token"=$SessionToken.session_token; "App-Token" = "$($Script:GLPICreds.AppToken)"} -Body $json -ContentType 'application/json'
}
Function Remove-GlpiItems {
    <#
.SYNOPSIS
    Remove a specific item by item type.
.DESCRIPTION
    Remove a specific item.
.PARAMETER ItemType
    Type of item wanted.
    Exemples : Computer, Monitor, User, etc.
.PARAMETER IDs
    Array of IDs of item to remove. If only ONE criteria is present, start with a COMA!
    Exemples : ,(114) or (110,114)
.PARAMETER Creds
    Credetials for the GLPI API. This is an object.
    Exemple : $GlpiCreds = @{
                    AppURL =     "https://[MyGlpiServer]/apirest.php"
                    UserToken =  "c8BRf8uJHPDr1AyDTgt2zm95S6EdMAHPXK6qTxlA"
                    AppToken =   "EaNdrm33jKDFVdK8gvFQtOf1XHki2Y4BVtPKssgl"
                    AuthorizationType = "Basic" or "user_token"
                    }
.PARAMETRE Purge
    If the itemtype have a trashbin, you can force purge (delete finally).Default: False
.PARAMETRE History
    Set to false to disable saving of deletion in global history. Default: True.
.EXAMPLE
     Remove-GlpiItems -ItemType "Monitor" -IDs 114 -Purge $true -History $false -Creds $GlpiCreds
.INPUTS
    None
.OUTPUTS
    Array
.NOTES
    Author:  Jean-Christophe Pirmolin #>
    param([parameter(Mandatory=$true)][String]$ItemType, [parameter(Mandatory=$true)]$IDs, [Boolean]$Purge=$false, [Boolean]$History=$true, [parameter(Mandatory=$true)][object]$Creds)
    # Build array of IDs.
    if ($IDs -notcontains "ID"){
        $ids2 = @()
        foreach ($ID in $IDs){
            $hash = [ordered]@{}
            $hash.add("id" , $ID)
            $ids2 += [pscustomobject]$hash
        }
        $IDs = $ids2
    }
    $Details = @{
        input=$IDs
        force_purge =  $Purge
        history = $History}
    $json = $Details | ConvertTo-Json
    #if (($Details["input"] | Get-Member -MemberType Properties).Count -eq 1){
    #    $json = $json.Remove(($lastIndex = $json.LastIndexOf("]")),1).Insert($lastIndex,"").Remove(($firstIndex = $json.IndexOf("[")),1).Insert($firstIndex,"")
   # }
   $SessionToken = GetGLPISessionToken -Creds $Creds
    Invoke-RestMethod "$($Creds.AppUrl)/$($ItemType)" -Method Delete -Headers @{"session-token"=$SessionToken.session_token; "App-Token" = "$($Creds.AppToken)"} -Body $json -ContentType 'application/json'
    Invoke-RestMethod "$($Creds.AppUrl)/killSession" -Headers @{"session-token"=$SessionToken.session_token; "App-Token" = "$($Creds.AppToken)"} -ErrorAction SilentlyContinue| Out-Null
}
