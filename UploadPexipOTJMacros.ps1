# Source helper functions
. .\HelperFunctions.ps1

# Function to log messages to a file
function Log-Message {
    param (
        [string]$message,
        [string]$logFile
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp - $message"
    Add-Content -Path $logFile -Value $logEntry
}

# Function to display messages in the console
function Display-Message {
    param (
        [string]$message
    )
    Write-Host $message
}

# Initialize log file
$logFile = "UploadPexipOTJMacros.log"

Display-Message "Option 1 selected: Upload Pexip OTJ macros"
Log-Message -message "Option 1 selected: Upload Pexip OTJ macros" -logFile $logFile

# Prompt user for CSV file path
$csvFilePath = Get-FilePath -promptMessage "Please enter the full path to the CSV file:"

# Prompt user for the directory containing ZIP files
$zipDirectory = Get-FilePath -promptMessage "Please enter the full path to the directory containing the Pexip OTJ ZIP files:"

# List ZIP files
$zipFiles = Get-ChildItem -Path $zipDirectory -Filter *-otj-macro-latest*.zip

# Import CSV
$systems = Import-Csv -Path $csvFilePath

# Check for matching systems
$matchingSystems = @()
$nonMatchingSystems = 0

foreach ($system in $systems) {
    $systemName = $system.'system name'.Replace(" ", "")
    $matchingZipFiles = $zipFiles | Where-Object { $_.Name -like "$systemName-otj-macro-latest*.zip" }
    if ($matchingZipFiles.Count -gt 0) {
        $matchingSystems += [PSCustomObject]@{ SystemName = $systemName; IPAddress = $system.'ip address'; Username = $system.'username'; Password = $system.'password'; ZipFile = $matchingZipFiles }
    } else {
        $nonMatchingSystems++
    }
}

Display-Message "Found $($matchingSystems.Count) systems with matching Pexip OTJ ZIP files."
Display-Message "Found $nonMatchingSystems systems with no matching Pexip OTJ ZIP files."
Log-Message -message "Found $($matchingSystems.Count) systems with matching Pexip OTJ ZIP files." -logFile $logFile
Log-Message -message "Found $nonMatchingSystems systems with no matching Pexip OTJ ZIP files." -logFile $logFile

# Confirm upload
if (-not (Get-Confirmation -promptMessage "Do you want to proceed with the upload?")) {
    Display-Message "Upload cancelled."
    Log-Message -message "Upload cancelled." -logFile $logFile
    return
}

# Function to upload macros from a ZIP file
function Upload-MacroFromZip {
    param (
        [string]$endpointIp,
        [string]$username,
        [string]$password,
        [string]$zipFilePath,
        [string]$logFile
    )

    $message = "Attempting to upload macros from $zipFilePath to $endpointIp..."
    Display-Message $message
    Log-Message -message $message -logFile $logFile

    $tempDir = Join-Path -Path $env:TMPDIR -ChildPath ([System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetRandomFileName()))
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    try {
        Expand-Archive -Path $zipFilePath -DestinationPath $tempDir -Force
        $jsFiles = Get-ChildItem -Path $tempDir -Filter *.js

        foreach ($jsFile in $jsFiles) {
            $macroName = [System.IO.Path]::GetFileNameWithoutExtension($jsFile.Name)
            $jsCode = Get-Content -Path $jsFile.FullName -Raw

            $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $headers.Add("Content-Type", "application/xml")
            $headers.Add("Authorization", "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${username}:${password}")))

            $body = @"
<Command>
    <Macros>
        <Macro>
            <Save command="True">
                <name>$macroName</name>
                <body><![CDATA[$jsCode]]></body>
                <overWrite>True</overWrite>
                <Transpile>False</Transpile>
            </Save>
        </Macro>
    </Macros>
</Command>
"@

            try {
                $response = Invoke-RestMethod -Uri "https://$endpointIp/putxml" -Method 'POST' -Headers $headers -Body $body -SkipCertificateCheck -TimeoutSec 10
                $message = "Macro $macroName uploaded successfully to $endpointIp from $zipFilePath."
                Display-Message $message
                Log-Message -message $message -logFile $logFile
            } catch {
                $errorDetails = $_.Exception.Message
                $message = "Error uploading macro $macroName to: $endpointIp from $zipFilePath. Response: $errorDetails"
                Display-Message $message
                Log-Message -message $message -logFile $logFile
            }
        }

    } catch {
        $message = "Error unzipping file $zipFilePath"
        Display-Message $message
        Log-Message -message $message -logFile $logFile
    } finally {
        Remove-Item -Recurse -Force -Path $tempDir
    }
}

# Function to restart macro runtime
function Restart-MacroRuntime {
    param (
        [string]$endpointIp,
        [string]$username,
        [string]$password,
        [string]$logFile
    )

    $message = "Attempting to restart macro runtime on $endpointIp..."
    Display-Message $message
    Log-Message -message $message -logFile $logFile

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/xml")
    $headers.Add("Authorization", "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${username}:${password}")))

    $body = @"
<Command>
    <Macros>
        <Runtime>
            <Restart command="True"/>
        </Runtime>
    </Macros>
</Command>
"@

    try {
        $response = Invoke-RestMethod -Uri "https://$endpointIp/putxml" -Method 'POST' -Headers $headers -Body $body -SkipCertificateCheck -TimeoutSec 10
        $message = "Macro runtime restarted successfully on $endpointIp."
        Display-Message $message
        Log-Message -message $message -logFile $logFile
    } catch {
        $errorDetails = $_.Exception.Message
        $message = "Error restarting macro runtime on $endpointIp. Response: $errorDetails"
        Display-Message $message
        Log-Message -message $message -logFile $logFile
    }
}

# Perform the upload and restart macro runtime
$uploadedSystems = 0

foreach ($system in $matchingSystems) {
    foreach ($zipFile in $system.ZipFile) {
        Upload-MacroFromZip -endpointIp $system.IPAddress -username $system.Username -password $system.Password -zipFilePath $zipFile.FullName -logFile $logFile
        Restart-MacroRuntime -endpointIp $system.IPAddress -username $system.Username -password $system.Password -logFile $logFile
        $uploadedSystems++
    }
}

$message = "Upload completed. Successfully uploaded macros to $uploadedSystems systems."
Display-Message $message
Log-Message -message $message -logFile $logFile
