[CmdletBinding()]
param (
    [Parameter(Mandatory = $False)]
    [String]$NODE_NAME = $Env:NODE_NAME,

    [Parameter(Mandatory = $False)]
    [String]$HA_PORT = $Env:HA_PORT,

    [Parameter(Mandatory = $False)]
    [String]$ENABLE_HA_CONTAINER = $Env:ENABLE_HA_CONTAINER
)

if ([String]::IsNullOrEmpty($NODE_NAME)) {
    $NODE_NAME = $Env:COMPUTERNAME;
}

if ([String]::IsNullOrEmpty($HA_PORT)) {
    $HA_PORT = '8060';
}

$DmgcmdPath = "C:\Program Files\Microsoft Integration Runtime\5.0\Shared\dmgcmd.exe"


function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)]
        [String]$Message
    )
    process {
        $ts = Get-Date -Format 'yyyy/MM/ss hh:mm:ss';
        Write-Host "[$NODE_NAME][$ts] $Message";
    }
}

function Check-Is-Registered() {
    $result = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\DataTransfer\DataManagementGateway\ConfigurationManager' -Name HaveRun -ErrorAction SilentlyContinue
    if (($result -ne $null) -and ($result.HaveRun -eq 'Mdw')) {
        return $TRUE
    }
    return $FALSE
}

function Check-Main-Process() {
    $ProcessResult = Get-WmiObject Win32_Process -Filter "name = 'diahost.exe'"
    
    if ($ProcessResult) {
        return $TRUE
    }
    else {
        throw "Main Process not found"   
    }
}

function Check-Node-Connection() {
    Start-Process $DmgcmdPath -Wait -ArgumentList "-cgc" -RedirectStandardOutput "C:\SHIR\status-check.txt"
    $ConnectionResult = Get-Content "C:\SHIR\status-check.txt"
    Remove-Item -Force "C:\SHIR\status-check.txt"

    if ($ConnectionResult -like "Connected") {
        return $TRUE
    }
    else {
        throw "Node is offline"    
    }
}

function EnableNodeRemoteAccess {
    [CmdletBinding()]
    param ()
    process {
        if ($ENABLE_HA_CONTAINER -eq 'true') {
            Write-Log 'Enabling High Availability';
            Start-Process $DmgcmdPath -Wait -ArgumentList '-EnableRemoteAccessInContainer', $HA_PORT;
        }
        elseif ($ENABLE_HA -eq 'true') {
            Write-Log 'Enabling High Availability';
            Start-Process $DmgcmdPath -Wait -ArgumentList '-EnableRemoteAccess', $HA_PORT;
        }
    }
}

function RegisterNewNode {
    Param(
        $AUTH_KEY,
        $NODE_NAME,
        $ENABLE_HA,
        $ENABLE_HA_CONTAINER,
        $HA_PORT
    )

    Write-Log "Start registering the new SHIR node"

    if (!$NODE_NAME) {
        Start-Process $DmgcmdPath -Wait -ArgumentList "-RegisterNewNode", "$($AUTH_KEY)" -RedirectStandardOutput "C:\SHIR\register-out.txt" -RedirectStandardError "C:\SHIR\register-error.txt"
    } else {
        Start-Process $DmgcmdPath -Wait -ArgumentList "-RegisterNewNode", "$($AUTH_KEY)", "$($NODE_NAME)" -RedirectStandardOutput "C:\SHIR\register-out.txt" -RedirectStandardError "C:\SHIR\register-error.txt"
    }

    EnableNodeRemoteAccess

    $StdOutResult = Get-Content "C:\SHIR\register-out.txt"
    $StdErrResult = Get-Content "C:\SHIR\register-error.txt"


    if ($StdOutResult)
    {
        Write-Log "Registration output:"
        $StdOutResult | ForEach-Object { Write-Log $_ }
    }

    if ($StdErrResult)
    {
        Write-Log "Registration errors:"
        $StdErrResult | ForEach-Object { Write-Log $_ }
    }
}

#
# Main entry point
#

# Register SHIR with key from Env Variable: AUTH_KEY
if (Check-Is-Registered) {
    Write-Log "Restart the existing node"
    Start-Process $DmgcmdPath -Wait -ArgumentList '-Start'
    # Start-Sleep -Seconds 30

    # EnableNodeRemoteAccess;
} elseif (Test-Path Env:AUTH_KEY) {

    while (!(Check-Is-Registered)) {
        Write-Log "Registering SHIR with the node key: $((Get-Item Env:AUTH_KEY).Value)"
        Write-Log "Registering SHIR with the node name: $((Get-Item Env:NODE_NAME).Value)"
        Write-Log "Registering SHIR with the enable high availability flag: $((Get-Item Env:ENABLE_HA).Value)"
        Write-Log "Registering SHIR with the enable container high availability flag: $((Get-Item Env:ENABLE_HA_CONTAINER).Value)"
        Write-Log "Registering SHIR with the tcp port: $((Get-Item Env:HA_PORT).Value)"
        Start-Process $DmgcmdPath -Wait -ArgumentList "-Start"
        Start-Sleep -Seconds 30
        RegisterNewNode (Get-Item Env:AUTH_KEY).Value (Get-Item Env:NODE_NAME).Value (Get-Item Env:ENABLE_HA).Value (Get-Item Env:ENABLE_HA_CONTAINER).Value (Get-Item Env:HA_PORT).Value

    }
} else {
    Write-Log "Invalid AUTH_KEY Value"
    exit 1
}

Write-Log "Waiting 30 seconds waiting for connecting"
Start-Sleep -Seconds 30

try {
    while ($TRUE) {
        if ((Check-Main-Process) -and (Check-Node-Connection)) {   
            Write-Log "Node Health Check Pass"
            Start-Sleep -Seconds 60
            continue
        }
    }
}
finally {
    Write-Log "Stop the node connection"
    Start-Process $DmgcmdPath -Wait -ArgumentList "-Stop"
    Write-Log "Stop the node connection successfully"
    exit 0
}

exit 1