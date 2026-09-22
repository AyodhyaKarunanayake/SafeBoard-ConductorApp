<#
.SYNOPSIS
  Read-only check: did a passenger's "end journey" actually reach Firebase, and would the
  conductor app notice it?

.DESCRIPTION
  Lists running trips (per conductor, or all conductors), and for each one summarises its
  seat_allocations by status. Flags any 'released' booking whose journey/bus doesn't match a
  currently running trip (the conductor app would never see it, because JourneyStreamProvider
  only listens to the trip it is currently running). Nothing is written.

.EXAMPLE
  powershell -File tool\check_seat_release.ps1
  powershell -File tool\check_seat_release.ps1 -ConductorId CND_NB_8710
#>
param([string]$ConductorId = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$options = Get-Content (Join-Path $root 'lib\firebase_options.dart') -Raw
$apiKey = [regex]::Match($options, "apiKey:\s*'([^']+)'").Groups[1].Value
$projectId = [regex]::Match($options, "projectId:\s*'([^']+)'").Groups[1].Value
$restRoot = "https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents"
$headers = @{ 'x-goog-api-key' = $apiKey }

function Field($doc, $name) {
  $f = $doc.fields.$name
  if ($null -eq $f) { return '' }
  foreach ($k in 'stringValue', 'integerValue', 'booleanValue') { if ($null -ne $f.$k) { return "$($f.$k)" } }
  return ''
}

function Run-Query($collection, $field, $value) {
  $q = @{ structuredQuery = @{
      from  = @(@{ collectionId = $collection })
      where = @{ fieldFilter = @{ field = @{ fieldPath = $field }; op = 'EQUAL'; value = @{ stringValue = $value } } } } } | ConvertTo-Json -Depth 8
  $r = Invoke-RestMethod -Method Post -Uri "${restRoot}:runQuery" -Headers $headers -ContentType 'application/json' -Body $q
  return @($r | Where-Object { $_.document } | ForEach-Object { $_.document })
}

Write-Host '== journey_instances =='
try {
  $allTrips = Invoke-RestMethod -Method Get -Uri "$restRoot/journey_instances?pageSize=100" -Headers $headers
} catch {
  Write-Host "  Could not read journey_instances: $($_.Exception.Message)"; return
}
$trips = @($allTrips.documents)
if ($ConductorId) { $trips = @($trips | Where-Object { (Field $_ 'conductor_id') -eq $ConductorId }) }
if ($trips.Count -eq 0 -or $null -eq $trips[0]) { Write-Host '  (none)'; return }

$running = @()
foreach ($t in $trips) {
  $status = Field $t 'status'
  $journeyId = Field $t 'journey_id'
  $busId = Field $t 'bus_id'
  $conductor = Field $t 'conductor_id'
  $isRunning = $status -ne 'completed'
  Write-Host ("  journey={0}  bus={1}  conductor={2}  status={3}{4}" -f $journeyId, $busId, $conductor, $status, $(if ($isRunning) { '  <- RUNNING (conductor app would show this one)' } else { '' }))
  if ($isRunning) { $running += [pscustomobject]@{ JourneyId = $journeyId; BusId = $busId; Conductor = $conductor } }
}

Write-Host ''
Write-Host '== seat_allocations status, per running trip =='
if ($running.Count -eq 0) { Write-Host '  No running trip, so the conductor app has nothing open to react on.' }
foreach ($r in $running) {
  Write-Host "  Journey $($r.JourneyId) / bus $($r.BusId) (conductor $($r.Conductor)):"
  $docs = Run-Query 'seat_allocations' 'journey_id' $r.JourneyId
  $onThisBus = @($docs | Where-Object { (Field $_ 'bus_id') -eq $r.BusId -or (Field $_ 'bus_id') -eq '' })
  $byStatus = $onThisBus | Group-Object { $s = Field $_ 'status'; if ($s) { $s } else { '(none = active)' } }
  if ($byStatus.Count -eq 0) { Write-Host '    No seat_allocations for this journey/bus yet.' }
  foreach ($g in $byStatus) { Write-Host "    $($g.Name): $($g.Count)" }
  $released = @($onThisBus | Where-Object { (Field $_ 'status') -eq 'released' })
  foreach ($d in ($released | Select-Object -First 5)) {
    Write-Host ("      released: seat={0}  allocation_id={1}" -f (Field $d 'seat_number'), (Field $d 'allocation_id'))
  }
}

Write-Host ''
Write-Host '== every "released" seat_allocation, anywhere =='
try {
  $q = @{ structuredQuery = @{ from = @(@{ collectionId = 'seat_allocations' }); where = @{ fieldFilter = @{ field = @{ fieldPath = 'status' }; op = 'EQUAL'; value = @{ stringValue = 'released' } } } } } | ConvertTo-Json -Depth 8
  $r = Invoke-RestMethod -Method Post -Uri "${restRoot}:runQuery" -Headers $headers -ContentType 'application/json' -Body $q
  $releasedAll = @($r | Where-Object { $_.document } | ForEach-Object { $_.document })
} catch { $releasedAll = @() }

if ($releasedAll.Count -eq 0) {
  Write-Host '  NONE. No passenger has ever released a seat in this Firebase project.'
  Write-Host '  This means the write never happened - the running passenger app does not have the patch, or was not rebuilt.'
} else {
  foreach ($d in $releasedAll) {
    $journeyId = Field $d 'journey_id'; $busId = Field $d 'bus_id'
    $match = $running | Where-Object { $_.JourneyId -eq $journeyId -and ($_.BusId -eq $busId -or $busId -eq '') }
    $verdict = if ($match) { 'matches a running trip - the conductor app should have reacted to this' }
               else { 'NO running trip matches (journey/bus mismatch) - the conductor app never saw this journey/bus, so it could not react' }
    Write-Host ("  seat={0}  journey={1}  bus={2}  -> {3}" -f (Field $d 'seat_number'), $journeyId, $busId, $verdict)
  }
}
