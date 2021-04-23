$DmgcmdPath = "C:\Program Files\Microsoft Integration Runtime\5.0\Shared\dmgcmd.exe"

function Write-Log($Message) {
    function TS { Get-Date -Format 'MM/dd/yyyy hh:mm:ss' }
    Write-Host "[$(TS)] $Message"
}

function Save-SHIR {
    [CmdletBinding()]
    param ()
    end {
        if (Test-Path -Path 'C:\SHIR\IntegrationRuntime_5.4.7749.1.msi') {
            return $True;
        }

        $progress = $ProgressPreference;
        try {
            $ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue;
            Invoke-WebRequest -Uri 'https://download.microsoft.com/download/E/4/7/E4771905-1079-445B-8BF9-8A1A075D8A10/IntegrationRuntime_5.4.7749.1.msi' -OutFile 'C:\SHIR\IntegrationRuntime_5.4.7749.1.msi';
            return $True;
        }
        catch {
            return $False;
        }
        finally {
            $ProgressPreference = $progress;
        }
    }
}

function Install-SHIR {
    param ()
    end {
        Write-Log "Install the Self-hosted Integration Runtime in the Windows container"

        $MsiFileName = (Get-ChildItem -Path C:\SHIR | Where-Object { $_.Name -match [regex] "IntegrationRuntime_.*.msi" })[0].Name
        Start-Process msiexec.exe -Wait -ArgumentList "/i C:\SHIR\$MsiFileName /qn NOFIREWALL=1"
        if (!$?) {
            Write-Log "SHIR MSI Install Failed"
            return $False;
        }

        Write-Log "SHIR MSI Install Successfully"
        return $True;
    }
}

function SetupEnv() {
    Write-Log "Begin to Setup the SHIR Environment"
    Start-Process $DmgcmdPath -Wait -ArgumentList "-Stop -StopUpgradeService -TurnOffAutoUpdate"
    Write-Log "SHIR Environment Setup Successfully"
}

if ((Save-SHIR) -and (Install-SHIR)) {
    exit 0;
}
else {
    exit 1;
}
