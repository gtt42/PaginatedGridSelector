# Copyright (c) 2023 gtt42.
# Licensed under MIT License.

<#
.SYNOPSIS
PowerShell CLI UI function that can display user selectable paginated data in a table.

.DESCRIPTION
The paginated grid selector is a UI element for the PowerShell CLI that can display large amounts of data in a paginated fashion.
The user can move forward and backward between pages and make a selection which gets returned to the calling function.
Custom headers can (and currently must) be passed to the function to be displayed in the table.

The function is intended to and can only be used interactively. 

Due to PowerShells primitive rendering options and not being able to manipulate previous output directly without losing multi-platform support 
each page gets rendered fully and the previous output is cleared. This also means that the PaginatedGridSelector can not be displayed in-line.
Once it is called it overtakes the session until either a value is returned or selection is canceled. 

.PARAMETER title
Title displayed above the table
e. g. "Select one of the items"

.PARAMETER headers
Headers displayed in the table. 
A position header is automatically added.

For the header to be displayed correctly it is important to define your headers object like the following example.
The key contains the header name while the value specifies the property name.
Pay attention to the [ordered] type accelerator, otherwise the headers will get jumbled. 

Example:
$headers = [ordered]@{
    'Username' = 'name'
    'Real name' = 'displayName'
    'Department' = 'department'
}

.PARAMETER data
The data to be displayed in the table.
The values have to be one-dimensional and can't be arrays since the table can't be nested.
A position object is automatically calculated and added to the data and assigned to the automatically created header so the user can select the wanted item.

.PARAMETER previousStartIndex
Internal parameter used for recursive pagination calls.
It is currently not intended to specify a custom starting position so passing a value to this parameter could cause unintended behavior.

.PARAMETER action
Internal parameter used for pagination calls.
#>
function PaginatedGridSelector(){
    param (
        [string]$title,
        [System.Collections.Specialized.OrderedDictionary]$headers,
        [System.Collections.ArrayList]$data,
        [int]$previousStartIndex = 0,
        [string]$action = ""
    )

    if ($data.Count -le 0){
        return $null
    }

    Clear-Host
    Write-Host $title -BackgroundColor White -ForegroundColor Black
    
    #add calculated position property to data
    if ($data | Where-Object {$null -eq $_.position}){
        for ($i=0; $i -lt $data.Count; $i++){
            $data[$i] | Add-Member -Name 'position' -Type NoteProperty -Value $i
        }
    }
    
    $calculatedDataHeight = $Host.UI.RawUI.WindowSize.Height - 7 #height of the terminal that remains for data after CLI, ...

    #calculate next or previous page start position
    switch($action){
        '' {$startIndex = 0; break}
        'n' {
            if (($previousStartIndex + $calculatedDataHeight) -le $data.Count){
                $startIndex = $previousStartIndex + $calculatedDataHeight
            }
            break
        }
        'p' {
            ($startIndex -le 0) ? ($startIndex = 0) : ($startIndex = $previousStartIndex - $calculatedDataHeight)
            break
        }
    }

    if ($data.Count -gt $calculatedDataHeight){ #split data for paginated display
        if (($startIndex + $calculatedDataHeight) -gt $data.Count){ #make sure no data out of bounds is selected for last page
            $displayedData = $data.GetRange($startIndex, ($data.Count - $startIndex))
        }else{
            $displayedData = $data.GetRange($startIndex, $calculatedDataHeight)
        }
    } else{ #show whole data
        $displayedData = $data
    }

    #create position header
    $formatting = @()
    $scriptBlock = [ScriptBlock]::Create("`$_.position")
    $formatting += @{Name="Position";Expression=$scriptBlock}

    #convert passed headers to needed format
    foreach ($header in $headers.GetEnumerator()){
        $scriptBlock = [ScriptBlock]::Create("`$_.$($header.value)")
        $formatting += @{Name=$header.key;Expression=$scriptBlock}
    }

    #display table with data
    $displayedData | Select-Object $formatting | Format-Table | Out-String | Write-Host -NoNewLine #we have to do the out-string / write-host trickery here so the output isn't redirected but instead displayed to the user since this is always interactive

    #calculate and display pages
    $totalPages = [math]::ceiling($data.Count / $calculatedDataHeight)
    $currentPage = [math]::ceiling($startIndex / $calculatedDataHeight) + 1
    $pageDisplayText = ($totalPages -gt 1) ? "Page $currentPage of $totalPages | (n)ext page | (p)revious page" : "Page 1 of 1"
    Write-Host "$pageDisplayText | (c)ancel selection" -BackgroundColor White -ForegroundColor Black

    do{
        try{
            [ValidatePattern('^n|p|c|\d$')]$selectedOption = Read-Host "Selection"

            switch($selectedOption){
                'n' { #recursive call to display next page
                    $previousStartIndex = $displayedData[0].Position 
                    PaginatedGridSelector $title $headers $data $previousStartIndex "n"
                    break
                }
                'p' { #recursive call to display previous page
                    $previousStartIndex = $displayedData[0].Position 
                    PaginatedGridSelector $title $headers $data $previousStartIndex "p"
                    break
                 }
                'c'{ #cancel PaginatedGridSelector
                    return $null
                }
                default { #return selected value
                    if ([int]$selectedOption -gt ($data.Count - 1)){
                        throw
                    }

                    return [int]$selectedOption
                }
            }
        } catch{}
    } until ($?)
}

Export-ModuleMember -Function PaginatedGridSelector