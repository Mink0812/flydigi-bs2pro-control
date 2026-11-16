<#
  Flydigi BS2 / BS2 Pro control by Mink0812 for Windows - no install, no background app.
  https://github.com/Mink0812/flydigi-bs2pro-control

  Usage:
    bs2pro-control.ps1           Start the control page (http://localhost:17865)
    bs2pro-control.ps1 -LedOff   Turn all lights off and exit

  Needs: Windows 10/11, Windows PowerShell 5.1 (built in), cooler paired in Windows Bluetooth settings.
  Protocol: GATT service 0xFFF0, commands written to 0xFFF2.
  Frame: 5A A5 <cmd> <len> <payload...> <checksum>, len = payload + 2, checksum = (cmd + len + sum(payload)) & 0xFF
#>
param([switch]$LedOff)

$ErrorActionPreference = 'Stop'

$Port        = 17865
$NameMatch   = 'flydigi|bs2'   # matched against the Bluetooth device name
$WaitSeconds = 15              # -LedOff: how long to wait for the cooler to connect
$ServiceUuid = [Guid]'0000fff0-0000-1000-8000-00805f9b34fb'
$WriteUuid   = [Guid]'0000fff2-0000-1000-8000-00805f9b34fb'

# ---------------------------------------------------------------- WinRT plumbing
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Devices.Bluetooth.BluetoothLEDevice, Windows.Devices.Bluetooth, ContentType = WindowsRuntime]
$null = [Windows.Devices.Bluetooth.GenericAttributeProfile.GattDeviceService, Windows.Devices.Bluetooth, ContentType = WindowsRuntime]
$null = [Windows.Devices.Enumeration.DeviceInformation, Windows.Devices.Enumeration, ContentType = WindowsRuntime]

$asTaskGeneric = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1

function Await($op, [Type]$type) {
    $task = $asTaskGeneric.MakeGenericMethod($type).Invoke($null, @($op))
    $null = $task.Wait(-1)
    $task.Result
}

$G = 'Windows.Devices.Bluetooth.GenericAttributeProfile'
$TStatus   = [Type]"$G.GattCommunicationStatus"
$TCharsRes = [Type]"$G.GattCharacteristicsResult"
$TSvcRes   = [Type]"$G.GattDeviceServicesResult"
$BufExt    = [System.Runtime.InteropServices.WindowsRuntime.WindowsRuntimeBufferExtensions]
$Connected = [Windows.Devices.Bluetooth.BluetoothConnectionStatus]::Connected

$script:dev = $null; $script:wch = $null; $script:opt = $null
$script:name = ''; $script:lastError = ''

# ---------------------------------------------------------------- Cooler
function New-Frame([byte]$cmd, [byte[]]$payload) {
    if ($cmd -eq 0xDF) { throw 'Command 0xDF erases the firmware and is never sent' }
    if ($null -eq $payload) { $payload = [byte[]]@() }
    if ($payload.Length -gt 15) { throw 'Payload too long' }
    $len = $payload.Length + 2
    $sum = $cmd + $len
    foreach ($b in $payload) { $sum += $b }
    [byte[]](@(0x5A, 0xA5, $cmd, $len) + $payload + @($sum -band 0xFF))
}

function Send-Frame([byte]$cmd, [byte[]]$payload) {
    if (-not $script:wch) { throw 'Not connected to the cooler' }
    [byte[]]$bytes = New-Frame $cmd $payload
    $buf = $BufExt::AsBuffer($bytes)
    try   { $op = $script:wch.WriteValueAsync($buf, $script:opt) }
    catch { $op = $script:wch.WriteValueAsync($buf) }
    $st = Await $op $TStatus
    if ($st -ne 'Success') { throw ("Writing command 0x{0:X2} failed ({1})" -f $cmd, $st) }
    Start-Sleep -Milliseconds 40
}

function Disconnect-Cooler {
    if ($script:dev) { try { $script:dev.Dispose() } catch {} }
    $script:dev = $null; $script:wch = $null
}

function Find-Cooler {
    $sel = [Windows.Devices.Bluetooth.BluetoothLEDevice]::GetDeviceSelectorFromPairingState($true)
    $all = Await ([Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync($sel)) ([Windows.Devices.Enumeration.DeviceInformationCollection])
    $info = $all | Where-Object { $_.Name -match $NameMatch } | Select-Object -First 1
    if (-not $info) { throw 'No paired Flydigi BS2 cooler found. Pair it in Settings > Bluetooth & devices first.' }
    $script:name = $info.Name
    $d = Await ([Windows.Devices.Bluetooth.BluetoothLEDevice]::FromIdAsync($info.Id)) ([Windows.Devices.Bluetooth.BluetoothLEDevice])
    if (-not $d) { throw 'Could not open the Bluetooth device' }
    $d
}

function Open-Gatt($d) {
    $sr = Await ($d.GetGattServicesForUuidAsync($ServiceUuid)) $TSvcRes
    if ($sr.Status -ne 'Success' -or $sr.Services.Count -eq 0) { throw "Service 0xFFF0 not found ($($sr.Status)). Is the cooler on and connected?" }
    $cr = Await ($sr.Services[0].GetCharacteristicsForUuidAsync($WriteUuid)) $TCharsRes
    if ($cr.Status -ne 'Success' -or $cr.Characteristics.Count -eq 0) { throw "Characteristic 0xFFF2 not found ($($cr.Status))" }
    $script:wch = $cr.Characteristics[0]
    $script:opt = if (([int]$script:wch.CharacteristicProperties -band 0x08) -ne 0) {
        [Windows.Devices.Bluetooth.GenericAttributeProfile.GattWriteOption]::WriteWithResponse
    } else {
        [Windows.Devices.Bluetooth.GenericAttributeProfile.GattWriteOption]::WriteWithoutResponse
    }
    $script:dev = $d
}

function Connect-Cooler {
    Disconnect-Cooler
    $d = Find-Cooler
    try { Open-Gatt $d } catch { $d.Dispose(); throw }
    $script:lastError = ''
    Write-Host "[OK] Connected: $($script:name)"
}

function Test-Connected {
    [bool]($script:dev -and $script:wch -and $script:dev.ConnectionStatus -eq $Connected)
}

# ---------------------------------------------------------------- -LedOff: one shot
if ($LedOff) {
    $d = $null
    try {
        $d = Find-Cooler
        Write-Host "[i] Found: $($script:name)"
        $waited = 0
        while ($d.ConnectionStatus -ne $Connected) {
            if ($waited -eq 0) { Write-Host "[..] Not connected yet, waiting up to $WaitSeconds s..." }
            if ($waited -ge $WaitSeconds) { Write-Host '[X] The cooler is not connected. Connect it in Bluetooth settings and try again.'; exit 2 }
            Start-Sleep -Seconds 1; $waited++
        }
        Open-Gatt $d
        Send-Frame 0x46 @(0)   # RGB light strip off
        Send-Frame 0x48 @(0)   # gear indicator LEDs off
        Write-Host '[OK] All lights are off.'
        exit 0
    }
    catch { Write-Host "[X] $($_.Exception.Message)"; exit 1 }
    finally { if ($d) { try { $d.Dispose() } catch {} } }
}

# ---------------------------------------------------------------- Control page
function Esc([string]$s) { ($s -replace '\\', '\\' -replace '"', '\"' -replace "[\r\n]+", ' ') }
function Json([string]$s) { [Text.Encoding]::UTF8.GetBytes($s) }

$HtmlPath = Join-Path $PSScriptRoot 'ui.html'
if (-not (Test-Path $HtmlPath)) { Write-Host "[X] ui.html not found next to the script ($HtmlPath)"; exit 1 }
$HtmlBytes = [IO.File]::ReadAllBytes($HtmlPath)
$Url = "http://localhost:$Port/"

# Open the page in its own Edge app window so Quit can close it; fall back to the default browser.
function Open-Page {
    try { Start-Process 'msedge.exe' "--app=$Url" -ErrorAction Stop }
    catch { Start-Process $Url }
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($Url)
try { $listener.Start() }
catch {
    Write-Host '[i] Already running, opening the control page.'
    Open-Page
    exit 0
}

Write-Host "BS2 Pro Control is running: $Url"
Write-Host 'Keep this window open while you use the page. Click Quit on the page to stop (this window closes by itself).'
try { Connect-Cooler } catch { $script:lastError = $_.Exception.Message; Write-Host "[X] $($script:lastError)" }
Open-Page

$running = $true
try {
    while ($running) {
        $ctx = $listener.GetContext()
        $path = $ctx.Request.Url.AbsolutePath
        $code = 200; $type = 'application/json; charset=utf-8'

        try {
            if ($path -eq '/') {
                $type = 'text/html; charset=utf-8'; $out = $HtmlBytes
            }
            elseif ($path -eq '/api/poll') {
                $out = Json ('{"connected":' + (Test-Connected).ToString().ToLower() +
                             ',"name":"' + (Esc $script:name) + '","error":"' + (Esc $script:lastError) + '"}')
            }
            elseif ($path -eq '/api/send' -and $ctx.Request.HttpMethod -eq 'POST') {
                $reader = New-Object IO.StreamReader($ctx.Request.InputStream, [Text.Encoding]::UTF8)
                $cmds = ConvertFrom-Json $reader.ReadToEnd()   # PS 5.1: foreach walks the JSON array
                if (-not $script:wch) { Connect-Cooler }
                foreach ($c in $cmds) {
                    $p = [byte[]]@($c.p | ForEach-Object { [byte]$_ })
                    try   { Send-Frame ([byte]$c.c) $p }
                    catch { Connect-Cooler; Send-Frame ([byte]$c.c) $p }   # one reconnect attempt
                }
                $out = Json '{"ok":true}'
            }
            elseif ($path -eq '/api/connect' -and $ctx.Request.HttpMethod -eq 'POST') {
                Connect-Cooler
                $out = Json '{"ok":true}'
            }
            elseif ($path -eq '/api/quit' -and $ctx.Request.HttpMethod -eq 'POST') {
                $running = $false
                $out = Json '{"ok":true}'
            }
            else { $code = 404; $out = Json '{}' }
        }
        catch {
            $script:lastError = $_.Exception.Message
            Write-Host "[X] $($script:lastError)"
            $out = Json ('{"ok":false,"error":"' + (Esc $script:lastError) + '"}')
        }

        try {
            $ctx.Response.StatusCode = $code
            $ctx.Response.ContentType = $type
            $ctx.Response.Headers.Add('Cache-Control', 'no-store')
            $ctx.Response.ContentLength64 = $out.Length
            $ctx.Response.OutputStream.Write($out, 0, $out.Length)
            $ctx.Response.Close()
        } catch {}
    }
}
finally {
    Disconnect-Cooler
    try { $listener.Stop(); $listener.Close() } catch {}
    Write-Host 'Stopped.'
}
exit 0
