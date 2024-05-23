# Define log files in the current user's Documents folder
$scriptLogFile = "$($env:USERPROFILE)\Documents\robocopy_script_log.txt"
$robocopyLogFile = "$($env:USERPROFILE)\Documents\robocopy_log.txt"

# Function to display the opening message
function Display-OpeningMessage {
    Write-Host "Welcome to the Automated Robocopy Script" -ForegroundColor Green
    Write-Host "--------------------------------------" -ForegroundColor Green
    Write-Host "This script allows you to copy a specified folder to a destination of your choice using Robocopy."
    Write-Host "You will be prompted to provide the following information:"
    Write-Host "1. The path of the folder to be copied."
    Write-Host "2. Whether the source path is a network location."
    Write-Host "   - If yes, you will be prompted to provide the network username and password."
    Write-Host "3. The destination path."
    Write-Host "4. Whether the destination is a network location."
    Write-Host "   - If yes, you will be prompted to provide the network username and password."
    Write-Host "5. The name for the folder in the destination."
    Write-Host "   - If left blank, the folder will be named after the computer name."
    Write-Host ""
    Write-Host "Warning: No path validation is performed. Please ensure that the paths you enter are correct."
    Write-Host "Please ensure you have the necessary permissions to access both the source and destination locations."
    Write-Host "The script will attempt to elevate permissions if not run as an administrator."
    Write-Host ""
    Write-Host "Press Enter to continue..." -ForegroundColor Yellow
    Read-Host
}

# Function to log messages
function Log-Message {
    param (
        [string]$message,
        [string]$logFilePath = $scriptLogFile
    )
    try {
        Add-Content -Path $logFilePath -Value "$((Get-Date).ToString()): $message"
    } catch {
        Write-Host "Failed to write to log file: $logFilePath. Error: $_"
    }
}

# Function to check if the drive is already mapped
function Is-DriveMapped {
    param (
        [string]$driveLetter,
        [string]$networkPath
    )
    $mappedDrives = net use | Select-String -Pattern "$driveLetter"
    return $mappedDrives -match "$driveLetter\s+"
}

# Function to run robocopy and display log output
function Run-Robocopy {
    param (
        [string]$source,
        [string]$destination,
        [string]$logFilePath
    )

    Write-Host "Starting robocopy from $source to $destination..."
    Log-Message "Starting robocopy from $source to $destination."

    $robocopyArgs = @("$source", "$destination", "/E", "/XO", "/R:0", "/W:0", "/XF", "desktop.ini", "/XD", "All Users", "Default", "Default User", "/V", "/LOG:$logFilePath")

    $scriptBlock = { param($source, $destination, $robocopyArgs)
        robocopy @robocopyArgs
    }

    $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $source, $destination, $robocopyArgs

    while ($job.State -eq "Running") {
        if (Test-Path $logFilePath) {
            Clear-Host
            Get-Content $logFilePath -Tail 20 | ForEach-Object { Write-Host $_ }
        }
        Start-Sleep -Seconds 2
    }

    Receive-Job -Job $job -Keep | Out-Host
    Remove-Job -Job $job

    if ($job.ExitCode -ge 8) {
        Write-Host "Robocopy encountered an error. Exit code: $($job.ExitCode)"
        Log-Message "Robocopy encountered an error. Exit code: $($job.ExitCode)"
    } else {
        Write-Host "Robocopy completed successfully."
        Log-Message "Robocopy completed successfully."
    }
}

# Function to elevate the script
function Elevate-Script {
    if (!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Start-Process powershell "-File `"$PSCommandPath`"" -Verb RunAs
        exit
    }
}

# Function to get user input
function Get-UserInput {
    param (
        [string]$prompt,
        [bool]$mandatory = $true
    )
    do {
        $input = Read-Host $prompt
        if ($mandatory -and [string]::IsNullOrWhiteSpace($input)) {
            Write-Host "This field is mandatory. Please provide a value."
        }
    } while ($mandatory -and [string]::IsNullOrWhiteSpace($input))
    return $input
}

# Function to get yes/no input
function Get-YesNoInput {
    param (
        [string]$prompt
    )
    do {
        $input = Read-Host $prompt
        if ($input -match '^(y|n|yes|no)$') {
            return $input -in 'y', 'yes'
        } else {
            Write-Host "Invalid input. Please enter 'y' or 'n'."
        }
    } while ($true)
}

# Display the opening message
Display-OpeningMessage

# Start logging
Log-Message "Script started."

# Elevate the script
Elevate-Script

try {
    # Get user input for the source folder and whether it's a network location
    $sourceFolder = Get-UserInput -prompt "Enter the path of the folder to be copied"
    $isSourceNetworkLocation = Get-YesNoInput -prompt "Is the source path a network location? (y/n)"

    if ($isSourceNetworkLocation) {
        $sourceNetworkUsername = Get-UserInput -prompt "Enter the source network username"
        $sourceNetworkPassword = Get-UserInput -prompt "Enter the source network password" -mandatory $true
        $sourceDriveLetter = "Y:"

        # Map network drive for source
        $netUseSource = net use $sourceDriveLetter $sourceFolder /user:$sourceNetworkUsername $sourceNetworkPassword
        if ($netUseSource -notmatch "The command completed successfully.") {
            Log-Message "Failed to map network drive for source. Output: $netUseSource"
            Write-Host "Failed to map network drive for source. Output: $netUseSource"
            throw "Failed to map network drive for source"
        }
        Log-Message "Source network drive mapped successfully."
        Write-Host "Source network drive mapped successfully."
        $sourceFolder = "$sourceDriveLetter"
    }

    # Get user input for the destination path and whether it's a network location
    $destinationRoot = Get-UserInput -prompt "Enter the destination path"
    $isDestinationNetworkLocation = Get-YesNoInput -prompt "Is this a network location? (y/n)"

    if ($isDestinationNetworkLocation) {
        $destinationNetworkUsername = Get-UserInput -prompt "Enter the destination network username"
        $destinationNetworkPassword = Get-UserInput -prompt "Enter the destination network password" -mandatory $true
        $destinationDriveLetter = "Z:"

        # Map network drive for destination
        $netUseDestination = net use $destinationDriveLetter $destinationRoot /user:$destinationNetworkUsername $destinationNetworkPassword
        if ($netUseDestination -notmatch "The command completed successfully.") {
            Log-Message "Failed to map network drive for destination. Output: $netUseDestination"
            Write-Host "Failed to map network drive for destination. Output: $netUseDestination"
            throw "Failed to map network drive for destination"
        }
        Log-Message "Destination network drive mapped successfully."
        Write-Host "Destination network drive mapped successfully."
        $destinationRoot = "$destinationDriveLetter"
    }

    $destinationFolderName = Get-UserInput -prompt "Enter the name for the folder in the destination (leave blank to use the computer name)" -mandatory $false
    if ([string]::IsNullOrWhiteSpace($destinationFolderName)) {
        $destinationFolderName = $env:COMPUTERNAME
    }
    $destinationPath = Join-Path -Path $destinationRoot -ChildPath $destinationFolderName

    # Check if the destination directory exists, and create it if it doesn't
    if (!(Test-Path $destinationPath)) {
        try {
            New-Item -ItemType Directory -Path $destinationPath -ErrorAction Stop
            Log-Message "Destination directory created at $destinationPath."
            Write-Host "Destination directory created at $destinationPath."
        } catch {
            Log-Message "Failed to create destination directory at $destinationPath. Error: $_"
            Write-Host "Failed to create destination directory at $destinationPath. Error: $_"
            throw "Failed to create destination directory at $destinationPath"
        }
    } else {
        Log-Message "Destination directory already exists at $destinationPath."
        Write-Host "Destination directory already exists at $destinationPath."
    }

    # Run robocopy and display log output
    Run-Robocopy -source $sourceFolder -destination $destinationPath -logFilePath $robocopyLogFile

    Log-Message "Script execution completed."
    Write-Host "Script execution completed."

} catch {
    Log-Message "An error occurred: $_"
    Write-Host "An error occurred: $_"
}

# Wait for user input before closing
Read-Host "Press Enter to exit"
