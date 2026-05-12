while($true) {

    Clear-Host

    $leader = kubectl get lease jenkins-leader -n jenkins-ha -o jsonpath='{.spec.holderIdentity}'

    $image = kubectl get statefulset jenkins-ha -n jenkins-ha -o jsonpath='{.spec.template.spec.containers[0].image}'

    try {

        Invoke-WebRequest -Uri "http://localhost:32000/login" -TimeoutSec 3 -UseBasicParsing | Out-Null

        $ui = "UP"
        $uiColor = "Green"

    }
    catch {

        $ui = "DOWN"
        $uiColor = "Red"
    }

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "       JENKINS HA LIVE STATUS           " -ForegroundColor Cyan
    Write-Host "  $(Get-Date -Format 'dd-MM-yyyy HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    Write-Host ""
    Write-Host "PODS:" -ForegroundColor Yellow

    $pods = kubectl get pods -n jenkins-ha --no-headers

    $pods | ForEach-Object {

        $parts = $_ -split '\s+'

        $name = $parts[0]
        $ready = $parts[1]
        $status = $parts[2]

        if ($name -eq $leader) {

            Write-Host ("  {0,-20} {1,-6} {2,-15} LEADER" -f $name, $ready, $status) -ForegroundColor Green

        }
        else {

            Write-Host ("  {0,-20} {1,-6} {2,-15} STANDBY" -f $name, $ready, $status) -ForegroundColor Gray
        }
    }

    Write-Host ""
    Write-Host "CURRENT LEADER : $leader" -ForegroundColor Green
    Write-Host "IMAGE VERSION  : $image" -ForegroundColor Magenta
    Write-Host "JENKINS UI     : $ui" -ForegroundColor $uiColor

    Write-Host ""
    Write-Host "Refreshes every 3 sec - Ctrl+C to stop" -ForegroundColor DarkGray
    Write-Host "========================================" -ForegroundColor Cyan

    Start-Sleep -Seconds 3
}